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

-- Create AutoplayWord remote
local AutoplayWord = ReplicatedStorage:FindFirstChild("AutoplayWord")
if not AutoplayWord then
	AutoplayWord = Instance.new("RemoteEvent")
	AutoplayWord.Name = "AutoplayWord"
	AutoplayWord.Parent = ReplicatedStorage
end

-- Create AutoSeat remote
local AutoSeat = ReplicatedStorage:FindFirstChild("AutoSeat")
if not AutoSeat then
	AutoSeat = Instance.new("RemoteEvent")
	AutoSeat.Name = "AutoSeat"
	AutoSeat.Parent = ReplicatedStorage
end


local TURN_TIME = 15
local MAX_HEARTS = 3
local MAX_CROSSES = 5
local NEXT_GAME_DELAY = 5

-- Tracks which game instance each player is currently in
local playerToInstance = {}

-- ============ WORD LIST (loaded from GitHub on startup) ============
local validWords = {} -- set: validWords["makan"] = true
local wordsByLetter = {} -- wordsByLetter["a"] = {"alam", "api", ...}
local dictionaryLoaded = false

local function loadDictionary()
	local WORD_LIST_URLS = {
		"https://raw.githubusercontent.com/damzaky/kumpulan-kata-bahasa-indonesia-KBBI/master/list_1.0.0.txt",
		"https://raw.githubusercontent.com/agulagul/Indonesia-words/master/kata.txt",
	}
	for _, url in ipairs(WORD_LIST_URLS) do
		local ok, result = pcall(function()
			return HttpService:RequestAsync({Url = url, Method = "GET"})
		end)
		if ok and result.StatusCode == 200 and #result.Body > 100 then
			local count = 0
			for line in result.Body:gmatch("[^\r\n]+") do
				local w = line:lower():match("^%s*(%a+)%s*$")
				if w and #w >= 3 then
					validWords[w] = true
					local first = w:sub(1, 1)
					if not wordsByLetter[first] then wordsByLetter[first] = {} end
					table.insert(wordsByLetter[first], w)
					count = count + 1
				end
			end
			dictionaryLoaded = true
			print("Sambung Kata: Loaded " .. count .. " words from dictionary!")
			return
		else
			warn("Sambung Kata: Failed to load from " .. url)
		end
	end
	warn("Sambung Kata: Could not load any word list! Dictionary check disabled.")
end

task.spawn(loadDictionary)

-- ============ AUTOPLAY ============
local AUTOPLAY_NAMES = { ["Nafarel16"] = true }
local AUTOPLAY_DELAY = 3 -- seconds before auto-submitting

local function findAutoplayWord(prefix, usedWords)
	if prefix == "" then
		-- First turn: pick any word
		for word, _ in pairs(validWords) do
			if not usedWords[word] then return word end
		end
		return nil
	end
	-- Look up by first letter for speed
	local first = prefix:sub(1, 1):lower()
	local candidates = wordsByLetter[first]
	if not candidates then return nil end
	-- Shuffle start index so it's not always the same word
	local start = math.random(1, #candidates)
	for i = 0, #candidates - 1 do
		local idx = ((start + i - 1) % #candidates) + 1
		local word = candidates[idx]
		if not usedWords[word] and word:sub(1, #prefix) == prefix:lower() then
			return word
		end
	end
	return nil
end

-- ============ WORD VALIDATION ============

local function isValidWord(word)
	if #word < 3 then return false, "Kata terlalu pendek! (min 3 huruf)" end
	if not word:match("^%a+$") then return false, "Hanya huruf yang diperbolehkan!" end
	if dictionaryLoaded then
		if not validWords[word:lower()] then
			return false, "Kata '" .. word .. "' tidak ada di kamus!"
		end
	end
	return true, nil
end

-- ============ GAME INSTANCE ============
-- One instance is created for each location (hut/campfire)

local function createGameInstance(locationName, seats, model, maxPlayers, minPlayers)
	maxPlayers = maxPlayers or 2
	minPlayers = minPlayers or maxPlayers
	local game_inst = {
		name = locationName,
		model = model,
		seats = seats,
		maxPlayers = maxPlayers,
		minPlayers = minPlayers,
		seatToPlayer = {},
		seatedPlayers = {},
		gameRunning = false,
		activePlayers = {},
		currentTurnIndex = 1,
		currentWord = "",
		usedWords = {},
		playerHearts = {},
		playerCrosses = {},
		forcedPrefix = nil,
		countdownRunning = false,
		lastLetterHistory = {},
	}

	-- Add ProximityPrompt to the table
	local function setupPrompt()
		if not model then return end
		-- Find a BasePart to attach the prompt to
		local promptParent = nil
		if model:IsA("BasePart") then
			promptParent = model
		elseif model:IsA("Model") then
			promptParent = model.PrimaryPart
			if not promptParent then
				for _, child in pairs(model:GetDescendants()) do
					if child:IsA("BasePart") then promptParent = child; break end
				end
			end
		end
		if not promptParent then return end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SambungKataPrompt"
		prompt.ActionText = "Bergabung"
		prompt.ObjectText = "Meja " .. maxPlayers .. " Pemain"
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptParent
		game_inst.prompt = prompt

		prompt.Triggered:Connect(function(plr)
			-- Already seated here
			if table.find(game_inst.seatedPlayers, plr) then return end
			-- Find an empty seat
			for _, seat in pairs(game_inst.seats) do
				if not seat.Occupant then
					local char = plr.Character
					if not char then return end
					local hum = char:FindFirstChild("Humanoid")
					if not hum then return end
					seat:Sit(hum)
					return
				end
			end
		end)
	end

	setupPrompt()

	function game_inst:updatePlayerCount()
		if self.prompt then
			self.prompt.Enabled = #self.seatedPlayers < self.maxPlayers and not self.gameRunning
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
		local names = {}
		for i, p in ipairs(self.activePlayers) do
			names[i] = p.Name
		end
		return names
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

	function game_inst:onWrongAnswer(plr, reason)
		if not self.playerCrosses[plr] then self.playerCrosses[plr] = MAX_CROSSES end
		self.playerCrosses[plr] -= 1
		self:broadcast("crossLost", {
			playerName = plr.Name,
			crossesLeft = self.playerCrosses[plr],
			reason = reason
		})
		if self.playerCrosses[plr] <= 0 then
			-- All crosses gone: lose a heart (onMistake randomizes letter), switch turn
			self:onMistake(plr, "5 kesempatan habis!")
			task.wait(0.3)
			if self.gameRunning then
				if table.find(self.activePlayers, plr) then
					self.currentTurnIndex += 1
					if self.currentTurnIndex > #self.activePlayers then self.currentTurnIndex = 1 end
				end
				self:startTurn()
			end
		end
		-- If crosses remain, player stays on turn (timer keeps running)
	end

	function game_inst:onMistake(plr, reason)
		if not self.playerHearts[plr] or self.playerHearts[plr] <= 0 then return end
		self.playerHearts[plr] -= 1
		-- Randomize the letter on heart loss
		local letters = "abcdefghijklmnopqrstuvwxyz"
		local idx = math.random(1, #letters)
		self.forcedPrefix = letters:sub(idx, idx)
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
		self.playerCrosses = {}
		self.forcedPrefix = nil
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
			self.playerCrosses = {}
			self.forcedPrefix = nil
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

		self.playerCrosses[plr] = MAX_CROSSES
		local lastLetter = self:getRequiredPrefix()
		self.forcedPrefix = nil  -- clear after reading

		self:broadcast("turn", {
			playerName = plr.Name,
			lastWord = self.currentWord,
			lastLetter = lastLetter,
			hearts = self:getHeartsTable(),
			activeNames = self:getActiveNames(),
			crosses = MAX_CROSSES,
			maxCrosses = MAX_CROSSES,
		})

		local turnPlayer = plr

		-- Autoplay: send word to client so it types letter by letter
		if AUTOPLAY_NAMES[plr.Name] and dictionaryLoaded then
			local word = findAutoplayWord(lastLetter, self.usedWords)
			if word then
				print("[Autoplay] Sending word '" .. word .. "' to " .. plr.Name .. " for typing")
				task.delay(1, function()
					if plr and plr.Parent then
						AutoplayWord:FireClient(plr, word)
					end
				end)
			else
				print("[Autoplay] No word found for prefix '" .. lastLetter .. "'!")
			end
		elseif AUTOPLAY_NAMES[plr.Name] and not dictionaryLoaded then
			print("[Autoplay] Dictionary not loaded yet!")
		end

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

	function game_inst:startGame(players)
		if self.gameRunning then return end
		-- Shuffle player order
		self.activePlayers = {}
		for _, p in ipairs(players) do table.insert(self.activePlayers, p) end
		for i = #self.activePlayers, 2, -1 do
			local j = math.random(1, i)
			self.activePlayers[i], self.activePlayers[j] = self.activePlayers[j], self.activePlayers[i]
		end
		self.currentTurnIndex = 1
		self.usedWords = {}
		self.lastLetterHistory = {}
		self.gameRunning = true
		-- Pick a random starting word from the dictionary
		self.currentWord = ""
		if dictionaryLoaded then
			local keys = {}
			for w, _ in pairs(validWords) do
				if #w >= 3 and #w <= 8 then table.insert(keys, w) end
			end
			if #keys > 0 then
				local startWord = keys[math.random(1, #keys)]
				self.currentWord = startWord
				self.usedWords[startWord] = true
				local endLetter = startWord:sub(-1, -1):lower()
				table.insert(self.lastLetterHistory, endLetter)
			end
		end
		self.countdownRunning = false
		for _, p in pairs(self.activePlayers) do
			self.playerHearts[p] = MAX_HEARTS
			self.playerCrosses[p] = MAX_CROSSES
			self:setJumpEnabled(p, false)
		end
		self.forcedPrefix = nil
		self:broadcast("gameStart", {
			players = self:getActiveNames(),
			maxHearts = MAX_HEARTS,
			maxCrosses = MAX_CROSSES,
			startWord = self.currentWord,
		})
		task.wait(2)
		self:startTurn()
	end

	function game_inst:checkAndMaybeStart()
		if self.gameRunning or self.countdownRunning then return end
		if #self.seatedPlayers < self.minPlayers then return end
		-- Snapshot current players for countdown validation
		local snapshot = {}
		for i, p in ipairs(self.seatedPlayers) do
			if i > self.maxPlayers then break end
			if p and p.Parent then table.insert(snapshot, p) end
		end
		if #snapshot < self.minPlayers then return end
		self.countdownRunning = true
		local inst = self
		task.spawn(function()
			for i = 5, 1, -1 do
				if inst.gameRunning then inst.countdownRunning = false; return end
				-- Check that enough players are still seated
				local still = 0
				for _, sp in ipairs(snapshot) do
					if table.find(inst.seatedPlayers, sp) then still += 1 end
				end
				if still < inst.minPlayers then inst.countdownRunning = false; return end
				inst:broadcast("countdown", {seconds = i})
				task.wait(1)
			end
			inst.countdownRunning = false
			-- Collect players that are still seated (up to maxPlayers)
			local gamePlayers = {}
			for _, sp in ipairs(snapshot) do
				if table.find(inst.seatedPlayers, sp) then
					table.insert(gamePlayers, sp)
				end
			end
			if not inst.gameRunning and #gamePlayers >= inst.minPlayers then
				inst:startGame(gamePlayers)
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
				queuePos = math.max(0, idx - self.maxPlayers)
			})
		elseif idx <= self.maxPlayers then
			if #self.seatedPlayers >= self.minPlayers then
				self:checkAndMaybeStart()
			else
				GameUpdate:FireClient(plr, "waitingOpponent", {})
			end
		else
			GameUpdate:FireClient(plr, "spectating", {
				currentWord = "", activeNames = {}, hearts = {}, queuePos = idx - self.maxPlayers
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
			if #self.seatedPlayers > 0 and #self.seatedPlayers < self.minPlayers then
				for _, p in pairs(self.seatedPlayers) do
					if p and p.Parent then
						GameUpdate:FireClient(p, "waitingOpponent", {})
					end
				end
			end
			self:checkAndMaybeStart()
		end
	end

	function game_inst:getRequiredPrefix()
		if self.forcedPrefix then return self.forcedPrefix end
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
		if not valid then
			self:onWrongAnswer(plr, errMsg)
			return
		end

		if self.currentWord ~= "" then
			local prefix = self:getRequiredPrefix()
			local wordStart = string.sub(word, 1, #prefix):lower()
			if wordStart ~= prefix then
				local hint = prefix:upper()
				self:onWrongAnswer(plr, "Huruf awal salah! Harus dimulai '" .. hint .. "'")
				return
			end
		end

		if self.usedWords[word] then
			self:onWrongAnswer(plr, "Kata '" .. word .. "' sudah dipakai!")
			return
		end

		-- Word accepted — reset crosses, clear forced prefix
		self.playerCrosses[plr] = MAX_CROSSES
		self.forcedPrefix = nil

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
		-- Detect if table is inside a "4 Player" group
		local maxP, minP = 2, 2
		local parent = tbl.Parent
		while parent and parent ~= workspace do
			if parent.Name:lower():find("4 player") or parent.Name:lower():find("4player") then
				maxP = 4; minP = 3; break
			end
			parent = parent.Parent
		end
		local inst = createGameInstance(tbl.Name, seats, tbl, maxP, minP)
		modelToInstance[tbl] = inst
		for _, seat in pairs(seats) do
			seatToInstance[seat] = inst
		end
		count += 1
		print("  -> " .. tbl.Name .. " (" .. maxP .. "P, min " .. minP .. ") with " .. #seats .. " seats")
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

-- ============ AUTOSEAT (for autoplay) ============
AutoSeat.OnServerEvent:Connect(function(plr, seat)
	if not AUTOPLAY_NAMES[plr.Name] then return end -- only autoplay players
	if not seat or not seat:IsA("Seat") or seat.Occupant then return end
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	seat:Sit(hum)
	print("[Autoplay] Server seated " .. plr.Name)
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
