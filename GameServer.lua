-- GameServer - Per Location Games (paste into ServerScriptService > GameServer)
-- Each hut/campfire runs its own independent game!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local SendWord = ReplicatedStorage:WaitForChild("SendWord")
local GameUpdate = ReplicatedStorage:WaitForChild("GameUpdate")
local TimerUpdate = ReplicatedStorage:WaitForChild("TimerUpdate")

-- Create TypingUpdate if it doesn't exist
local TypingUpdate = ReplicatedStorage:FindFirstChild("TypingUpdate")
if not TypingUpdate then
	TypingUpdate = Instance.new("RemoteEvent")
	TypingUpdate.Name = "TypingUpdate"
	TypingUpdate.Parent = ReplicatedStorage
end

local TURN_TIME = 15
local MAX_HEARTS = 3
local CHECK_DICTIONARY = true
local NEXT_GAME_DELAY = 5

-- Tracks which game instance each player is currently in
local playerToInstance = {}

-- ============ WORD VALIDATION ============

local function isValidWord(word)
	if #word < 3 then return false, "Kata terlalu pendek! (min 3 huruf)" end
	if not word:match("^%a+$") then return false, "Hanya huruf yang diperbolehkan!" end
	if CHECK_DICTIONARY then
		local ok, result = pcall(function()
			return HttpService:GetAsync("https://kbbi.kemendikdasmen.go.id/entri/" .. word, true)
		end)
		if not ok then warn("KBBI tidak bisa diakses: " .. word); return true, nil end
		if result and result:find("Entri tidak ditemukan.", 1, true) then
			return false, "Kata '" .. word .. "' tidak ada di KBBI!"
		end
		if result and (result:find("BatasSehari", 1, true) or result:find("Banned", 1, true)) then
			warn("KBBI rate limit!"); return true, nil
		end
	end
	return true, nil
end

-- ============ GAME INSTANCE ============
-- One instance is created for each location (hut/campfire)

local function createGameInstance(locationName, seats, model)
	local game_inst = {
		name = locationName,
		model = model,
		seats = seats,
		seatToPlayer = {},
		seatedPlayers = {},   -- ordered: [1] and [2] are active, rest are queue
		gameRunning = false,
		activePlayers = {},
		currentTurnIndex = 1,
		currentWord = "",
		usedWords = {},
		playerHearts = {},
		countdownRunning = false,
		lastLetterHistory = {},  -- tracks consecutive repeated starting letters
		billboard = nil,
		countLabel = nil,
	}

	-- Create floating player count billboard above the table
	local function setupBillboard()
		if not model then return end

		-- Get the table position - model is the table itself
		local tablePos = nil
		local topY = 0

		if model:IsA("BasePart") then
			tablePos = model.Position
			topY = model.Position.Y + model.Size.Y / 2
		elseif model:IsA("Model") then
			-- Find the highest point of the table model
			for _, child in pairs(model:GetDescendants()) do
				if child:IsA("BasePart") then
					if not tablePos then tablePos = child.Position end
					local partTop = child.Position.Y + child.Size.Y / 2
					if partTop > topY then
						topY = partTop
						tablePos = Vector3.new(child.Position.X, child.Position.Y, child.Position.Z)
					end
				end
			end
		end

		if not tablePos then return end

		-- Create an invisible anchor part above the table
		local anchor = Instance.new("Part")
		anchor.Name = "CountAnchor"
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Position = Vector3.new(tablePos.X, topY + 4.5, tablePos.Z)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.Transparency = 1
		anchor.Parent = workspace

		local bb = Instance.new("BillboardGui")
		bb.Name = "PlayerCount"
		bb.Size = UDim2.new(0, 90, 0, 45)
		bb.StudsOffset = Vector3.new(0, 1, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 80
		bb.Adornee = anchor
		bb.Parent = anchor

		local countLbl = Instance.new("TextLabel")
		countLbl.Size = UDim2.new(1, 0, 1, 0)
		countLbl.BackgroundTransparency = 1
		countLbl.Font = Enum.Font.GothamBold
		countLbl.Text = "0/2"
		countLbl.TextSize = 24
		countLbl.TextColor3 = Color3.fromRGB(0, 255, 128)
		countLbl.TextStrokeColor3 = Color3.fromRGB(0, 40, 20)
		countLbl.TextStrokeTransparency = 0.2
		countLbl.Parent = bb

		game_inst.billboard = bb
		game_inst.countLabel = countLbl
	end

	setupBillboard()

	function game_inst:updatePlayerCount()
		if self.countLabel then
			local count = #self.seatedPlayers
			self.countLabel.Text = count .. "/2"
			if count == 0 then
				self.countLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
			elseif count == 1 then
				self.countLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
			else
				self.countLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
			end
		end
	end

	game_inst:updatePlayerCount()

	-- Send event to all seated players in this location
	function game_inst:broadcast(msgType, data)
		for _, p in pairs(self.seatedPlayers) do
			if p and p.Parent then GameUpdate:FireClient(p, msgType, data) end
		end
	end

	function game_inst:getCurrentPlayer()
		if #self.activePlayers == 0 then return nil end
		return self.activePlayers[self.currentTurnIndex]
	end

	function game_inst:getActiveNames()
		return {
			self.activePlayers[1] and self.activePlayers[1].Name or "",
			self.activePlayers[2] and self.activePlayers[2].Name or ""
		}
	end

	function game_inst:getHeartsTable()
		local t = {}
		for _, p in pairs(self.activePlayers) do t[p.Name] = self.playerHearts[p] or 0 end
		return t
	end

	function game_inst:setJumpEnabled(plr, enabled)
		local char = plr.Character
		if not char then return end
		local hum = char:FindFirstChild("Humanoid")
		if not hum then return end

		if enabled then
			hum.JumpPower = 50
			hum.JumpHeight = 7.2
			-- Disconnect the anti-jump listener
			if self._jumpConns and self._jumpConns[plr] then
				self._jumpConns[plr]:Disconnect()
				self._jumpConns[plr] = nil
			end
		else
			hum.JumpPower = 0
			hum.JumpHeight = 0
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			-- Also continuously block jump attempts while seated
			if not self._jumpConns then self._jumpConns = {} end
			if self._jumpConns[plr] then self._jumpConns[plr]:Disconnect() end
			self._jumpConns[plr] = hum.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall then
					hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
					hum:ChangeState(Enum.HumanoidStateType.Seated)
				end
			end)
		end
	end

	function game_inst:unseatPlayer(plr)
		local char = plr.Character
		if not char then return end
		local hum = char:FindFirstChild("Humanoid")
		if not hum then return end
		-- Jump off the seat
		hum.Sit = false
	end

	function game_inst:unseatAllPlayers()
		for _, p in pairs(self.seatedPlayers) do
			if p and p.Parent then
				self:unseatPlayer(p)
			end
		end
	end

	function game_inst:killPlayer(plr)
		local char = plr.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum.Health = 0 end
		end
	end

	function game_inst:eliminatePlayer(plr, reason)
		self:broadcast("eliminated", {playerName = plr.Name, reason = reason, hearts = 0})
		local idx = table.find(self.activePlayers, plr)
		if idx then
			table.remove(self.activePlayers, idx)
			if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
		end
		self.playerHearts[plr] = 0
		self:setJumpEnabled(plr, true)
		task.delay(1.2, function() self:killPlayer(plr) end)
	end

	function game_inst:onMistake(plr, reason)
		if not self.playerHearts[plr] or self.playerHearts[plr] <= 0 then return end
		self.playerHearts[plr] -= 1
		-- Find the opponent (attacker)
		local attacker = nil
		for _, p in pairs(self.activePlayers) do
			if p ~= plr then attacker = p; break end
		end
		self:broadcast("heartLost", {
			playerName = plr.Name,
			attackerName = attacker and attacker.Name or nil,
			heartsLeft = self.playerHearts[plr],
			reason = reason
		})
		if self.playerHearts[plr] <= 0 then
			task.wait(0.8)
			self:eliminatePlayer(plr, reason)
		end
	end

	function game_inst:endGame(reason)
		if not self.gameRunning then return end
		self.gameRunning = false
		for _, p in pairs(self.activePlayers) do self:setJumpEnabled(p, true) end
		self:broadcast("gameEnded", {reason = reason})
		self.activePlayers = {}
		self.playerHearts = {}
		self.currentWord = ""
		self.usedWords = {}
		self.lastLetterHistory = {}
		self.currentTurnIndex = 1
		-- Kick everyone off seats after a delay
		task.delay(3, function() self:unseatAllPlayers() end)
	end

	function game_inst:startTurn()
		if not self.gameRunning then return end

		if #self.activePlayers <= 1 then
			local winnerName = #self.activePlayers == 1 and self.activePlayers[1].Name or nil
			if winnerName then
				self:setJumpEnabled(self.activePlayers[1], true)
				self:broadcast("winner", {playerName = winnerName})
			else
				self:broadcast("noWinner", {})
			end
			self.gameRunning = false
			self.activePlayers = {}
			self.playerHearts = {}
			self.currentWord = ""
			self.usedWords = {}
			self.currentTurnIndex = 1
			-- Kick everyone off seats after a delay
			task.delay(3, function() self:unseatAllPlayers() end)
			return
		end

		local plr = self:getCurrentPlayer()
		if not plr or not plr.Parent then
			local idx = table.find(self.activePlayers, plr)
			if idx then
				table.remove(self.activePlayers, idx)
				if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
			end
			self:startTurn()
			return
		end

		local lastLetter = self:getRequiredPrefix()

		self:broadcast("turn", {
			playerName = plr.Name,
			lastWord = self.currentWord,
			lastLetter = lastLetter,
			hearts = self:getHeartsTable(),
			activeNames = self:getActiveNames()
		})

		local turnPlayer = plr
		for i = TURN_TIME, 0, -1 do
			if not self.gameRunning then return end
			if self:getCurrentPlayer() ~= turnPlayer then return end
			for _, p in pairs(self.seatedPlayers) do
				if p and p.Parent then TimerUpdate:FireClient(p, i) end
			end
			task.wait(1)
		end

		if self:getCurrentPlayer() == turnPlayer and self.gameRunning then
			self:onMistake(turnPlayer, "waktu habis!")
			task.wait(0.3)
			if self.gameRunning then
				if table.find(self.activePlayers, turnPlayer) then
					self.currentTurnIndex += 1
					if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
				end
				self:startTurn()
			end
		end
	end

	function game_inst:startGame(p1, p2)
		if self.gameRunning then return end
		self.activePlayers = {p1, p2}
		if math.random(1,2) == 2 then self.activePlayers = {p2, p1} end
		self.currentTurnIndex = 1
		self.currentWord = ""
		self.usedWords = {}
		self.lastLetterHistory = {}
		self.gameRunning = true
		self.countdownRunning = false
		for _, p in pairs(self.activePlayers) do
			self.playerHearts[p] = MAX_HEARTS
			self:setJumpEnabled(p, false)
		end
		self:broadcast("gameStart", {
			p1 = self.activePlayers[1].Name,
			p2 = self.activePlayers[2].Name,
			maxHearts = MAX_HEARTS
		})
		task.wait(2)
		self:startTurn()
	end

	function game_inst:checkAndMaybeStart()
		if self.gameRunning or self.countdownRunning then return end
		if #self.seatedPlayers < 2 then return end
		local p1, p2 = self.seatedPlayers[1], self.seatedPlayers[2]
		if not p1 or not p2 or not p1.Parent or not p2.Parent then return end
		self.countdownRunning = true
		local inst = self
		task.spawn(function()
			for i = 5, 1, -1 do
				if inst.gameRunning or inst.seatedPlayers[1] ~= p1 or inst.seatedPlayers[2] ~= p2 then
					inst.countdownRunning = false; return
				end
				inst:broadcast("countdown", {seconds = i})
				task.wait(1)
			end
			inst.countdownRunning = false
			if not inst.gameRunning and #inst.seatedPlayers >= 2
				and inst.seatedPlayers[1] == p1 and inst.seatedPlayers[2] == p2 then
				inst:startGame(p1, p2)
			end
		end)
	end

	function game_inst:onPlayerSat(plr)
		if not table.find(self.seatedPlayers, plr) then
			table.insert(self.seatedPlayers, plr)
		end
		playerToInstance[plr] = self
		self:updatePlayerCount()
		local idx = table.find(self.seatedPlayers, plr)

		if self.gameRunning then
			GameUpdate:FireClient(plr, "spectating", {
				currentWord = self.currentWord,
				activeNames = self:getActiveNames(),
				hearts = self:getHeartsTable(),
				queuePos = math.max(0, idx - 2)
			})
		elseif idx <= 2 then
			if #self.seatedPlayers >= 2 then
				self:checkAndMaybeStart()
			else
				GameUpdate:FireClient(plr, "waitingOpponent", {})
			end
		else
			GameUpdate:FireClient(plr, "spectating", {
				currentWord = "", activeNames = {}, hearts = {}, queuePos = idx - 2
			})
		end
	end

	function game_inst:onPlayerStood(plr)
		local idx = table.find(self.seatedPlayers, plr)
		if idx then table.remove(self.seatedPlayers, idx) end
		playerToInstance[plr] = nil
		self:updatePlayerCount()

		-- Tell the leaving player to dismiss their UI
		if plr and plr.Parent then
			GameUpdate:FireClient(plr, "leftSeat", {})
		end

		if self.gameRunning and table.find(self.activePlayers, plr) then
			self:endGame(plr.Name .. " meninggalkan kursi!")
			return
		end
		if not self.gameRunning then
			if #self.seatedPlayers == 1 then
				GameUpdate:FireClient(self.seatedPlayers[1], "waitingOpponent", {})
			end
			self:checkAndMaybeStart()
		end
	end

	function game_inst:getRequiredPrefix()
		if self.currentWord == "" then return "" end
		local lastChar = string.sub(self.currentWord, -1, -1):lower()
		local history = self.lastLetterHistory
		-- Count how many times this letter appeared as ending letter in the whole game
		local count = 0
		for _, letter in ipairs(history) do
			if letter == lastChar then count += 1 end
		end
		-- If it appeared 4+ times total, use last 2 letters
		if count >= 4 and #self.currentWord >= 2 then
			return string.sub(self.currentWord, -2):lower()
		end
		return lastChar
	end

	function game_inst:handleWord(plr, word)
		if not self.gameRunning then return end
		if self:getCurrentPlayer() ~= plr then return end

		local valid, errMsg = isValidWord(word)
		if not valid then GameUpdate:FireClient(plr, "error", {message = errMsg}); return end

		if self.currentWord ~= "" then
			local prefix = self:getRequiredPrefix()
			local wordStart = string.sub(word, 1, #prefix):lower()
			if wordStart ~= prefix then
				local hint = prefix:upper()
				self:onMistake(plr, "huruf awal salah! Harus dimulai '" .. hint .. "'")
				task.wait(0.3)
				if self.gameRunning then
					if table.find(self.activePlayers, plr) then
						self.currentTurnIndex += 1
						if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
					end
					self:startTurn()
				end
				return
			end
		end

		if self.usedWords[word] then
			self:onMistake(plr, "kata '" .. word .. "' sudah dipakai!")
			task.wait(0.3)
			if self.gameRunning then
				if table.find(self.activePlayers, plr) then
					self.currentTurnIndex += 1
					if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
				end
				self:startTurn()
			end
			return
		end

		-- Track the ending letter for repeat detection
		local endingLetter = string.sub(word, -1, -1):lower()
		table.insert(self.lastLetterHistory, endingLetter)

		self.usedWords[word] = true
		self.currentWord = word
		self.currentTurnIndex += 1
		if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
		self:broadcast("wordAccepted", {playerName = plr.Name, word = word})
		task.wait(0.8)
		self:startTurn()
	end

	-- Connect all seats for this location
	for _, seat in pairs(seats) do
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant then
				local p = Players:GetPlayerFromCharacter(seat.Occupant.Parent)
				if p then game_inst.seatToPlayer[seat] = p; game_inst:onPlayerSat(p) end
			else
				local p = game_inst.seatToPlayer[seat]
				game_inst.seatToPlayer[seat] = nil
				if p then game_inst:onPlayerStood(p) end
			end
		end)
	end

	print("📍 Location '" .. locationName .. "' ready with " .. #seats .. " seats")
	return game_inst
end

-- ============ FIND ALL LOCATIONS ============
-- Groups seats by proximity to tables
-- Billboard hovers above the table, seats nearby are linked to it

local SEAT_TO_TABLE_MAX_DIST = 15  -- max studs between a seat and table to be grouped

-- Maps table instance -> game instance
local modelToInstance = {}
-- Maps seat instance -> game instance (for dynamic seat lookup)
local seatToInstance = {}

local function hasSeatInside(obj)
	if obj:IsA("Seat") then return true end
	if obj:IsA("Model") then
		for _, desc in pairs(obj:GetDescendants()) do
			if desc:IsA("Seat") then return true end
		end
	end
	return false
end

local function findAllTables()
	local tables = {}
	local added = {}
	for _, obj in pairs(workspace:GetDescendants()) do
		local name = obj.Name:lower()
		-- Direct table/meja name matches
		if (name:find("table") or name:find("meja")) and (obj:IsA("BasePart") or obj:IsA("Model")) then
			if not added[obj] then
				table.insert(tables, obj)
				added[obj] = true
			end
		end
		-- Gazebo/Gasebo containers: find the table inside (child that has no seat)
		if (name:find("gazebo") or name:find("gasebo")) and obj:IsA("Model") then
			for _, child in pairs(obj:GetChildren()) do
				if (child:IsA("BasePart") or child:IsA("Model")) and not hasSeatInside(child) then
					if not added[child] then
						table.insert(tables, child)
						added[child] = true
					end
				end
			end
		end
	end
	return tables
end

local function getPosition(obj)
	if obj:IsA("Model") then
		if obj.PrimaryPart then return obj.PrimaryPart.Position end
		-- Find any part to get position
		for _, child in pairs(obj:GetDescendants()) do
			if child:IsA("BasePart") then return child.Position end
		end
		return nil
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
	return nil
end

local function getSeatPosition(seat)
	if seat:IsA("BasePart") then return seat.Position end
	return nil
end

local function setupLocations()
	local tables = findAllTables()
	local allSeats = {}

	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Seat") then
			table.insert(allSeats, obj)
		end
	end

	-- Group each seat to the nearest table within range
	local tableSeats = {}  -- table instance -> {seats}

	for _, seat in pairs(allSeats) do
		local seatPos = getSeatPosition(seat)
		if not seatPos then continue end

		local bestTable = nil
		local bestDist = SEAT_TO_TABLE_MAX_DIST

		for _, tbl in pairs(tables) do
			local tblPos = getPosition(tbl)
			if tblPos then
				local dist = (seatPos - tblPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestTable = tbl
				end
			end
		end

		if bestTable then
			if not tableSeats[bestTable] then tableSeats[bestTable] = {} end
			table.insert(tableSeats[bestTable], seat)
		end
	end

	local count = 0
	for tbl, seats in pairs(tableSeats) do
		local inst = createGameInstance(tbl.Name, seats, tbl)
		modelToInstance[tbl] = inst
		for _, seat in pairs(seats) do
			seatToInstance[seat] = inst
		end
		count += 1
		print("  -> " .. tbl.Name .. " with " .. #seats .. " seats")
	end

	print("Tables found: " .. #tables)
	print("Total game locations: " .. count)
end

-- Also handle dynamically loaded seats
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("Seat") then
		local seatPos = getSeatPosition(obj)
		if not seatPos then return end
		-- Find nearest table
		local bestInst = nil
		local bestDist = SEAT_TO_TABLE_MAX_DIST
		for tbl, inst in pairs(modelToInstance) do
			local tblPos = getPosition(tbl)
			if tblPos then
				local dist = (seatPos - tblPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestInst = inst
				end
			end
		end
		local inst = bestInst
		if inst then
			table.insert(inst.seats, obj)
			obj:GetPropertyChangedSignal("Occupant"):Connect(function()
				if obj.Occupant then
					local p = Players:GetPlayerFromCharacter(obj.Occupant.Parent)
					if p then inst.seatToPlayer[obj] = p; inst:onPlayerSat(p) end
				else
					local p = inst.seatToPlayer[obj]
					inst.seatToPlayer[obj] = nil
					if p then inst:onPlayerStood(p) end
				end
			end)
		end
	end
end)

-- ============ WORD SUBMISSION ============

SendWord.OnServerEvent:Connect(function(plr, word)
	local inst = playerToInstance[plr]
	if not inst then return end
	word = word:lower():gsub("%s+", "")
	inst:handleWord(plr, word)
end)

-- ============ TYPING RELAY ============

TypingUpdate.OnServerEvent:Connect(function(plr, text)
	local inst = playerToInstance[plr]
	if not inst or not inst.gameRunning then return end
	-- Relay to all other players in this game instance
	for _, p in pairs(inst.activePlayers) do
		if p ~= plr and p.Parent then
			TypingUpdate:FireClient(p, plr.Name, text)
		end
	end
	-- Also relay to seated spectators
	for _, p in pairs(inst.seatedPlayers) do
		if not table.find(inst.activePlayers, p) and p.Parent then
			TypingUpdate:FireClient(p, plr.Name, text)
		end
	end
end)

-- ============ DISCONNECT ============

Players.PlayerRemoving:Connect(function(plr)
	local inst = playerToInstance[plr]
	if inst then inst:onPlayerStood(plr) end
end)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid")
		hum.Died:Connect(function()
			task.wait(0.2)
			local inst = playerToInstance[plr]
			if inst and inst.gameRunning and table.find(inst.activePlayers, plr)
				and (inst.playerHearts[plr] or 0) > 0 then
				inst:endGame(plr.Name .. " mati!")
			end
		end)
	end)
end)

-- Start!
setupLocations()
