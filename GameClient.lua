-- GameClient - Sambung Kata (paste into StarterPlayerScripts as LocalScript)
-- Clean White UI | Rounded Panels | Mobile Friendly | Custom In-Game Keyboard

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local SendWord = ReplicatedStorage:WaitForChild("SendWord")
local GameUpdate = ReplicatedStorage:WaitForChild("GameUpdate")
local TimerUpdate = ReplicatedStorage:WaitForChild("TimerUpdate")
local TypingUpdate = ReplicatedStorage:WaitForChild("TypingUpdate", 10)

-- ============ COLORS ============

local C = {
	white      = Color3.fromRGB(255, 255, 255),
	panelBg    = Color3.fromRGB(255, 255, 255),
	darkText   = Color3.fromRGB(50, 50, 50),
	medText    = Color3.fromRGB(100, 100, 100),
	lightText  = Color3.fromRGB(170, 170, 170),
	tileBg     = Color3.fromRGB(240, 240, 240),
	tileText   = Color3.fromRGB(30, 30, 30),
	red        = Color3.fromRGB(220, 60, 60),
	redLight   = Color3.fromRGB(255, 120, 120),
	redDark    = Color3.fromRGB(150, 30, 30),
	heartRed   = Color3.fromRGB(220, 50, 60),
	green      = Color3.fromRGB(60, 190, 80),
	greenDark  = Color3.fromRGB(45, 150, 60),
	gold       = Color3.fromRGB(255, 200, 50),
	goldDim    = Color3.fromRGB(200, 160, 40),
	inputBg    = Color3.fromRGB(245, 245, 245),
	inputBorder= Color3.fromRGB(210, 210, 210),
	overlay    = Color3.fromRGB(0, 0, 0),
	shadow     = Color3.fromRGB(0, 0, 0),
	keyBg      = Color3.fromRGB(255, 255, 255),
	keyPress   = Color3.fromRGB(200, 200, 200),
	keyboardBg = Color3.fromRGB(180, 180, 190),
}

-- Fonts
local F = {
	title   = Enum.Font.FredokaOne,
	big     = Enum.Font.GothamBlack,
	name    = Enum.Font.GothamBold,
	letter  = Enum.Font.LuckiestGuy,
	status  = Enum.Font.GothamBold,
	typing  = Enum.Font.GothamBold,
	sub     = Enum.Font.GothamMedium,
	chain   = Enum.Font.Gotham,
	heart   = Enum.Font.GothamBold,
	timer   = Enum.Font.GothamBold,
	key     = Enum.Font.GothamBold,
}

-- ============ HELPERS ============

local function create(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props) do if k ~= "Parent" then inst[k] = v end end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function tw(obj, props, dur, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(dur or 0.25, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play(); return t
end

local function twLoop(obj, props, dur, style)
	local t = TweenService:Create(obj, TweenInfo.new(dur or 1, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), props)
	t:Play(); return t
end

-- ============ SCREEN GUI ============

local gui = create("ScreenGui", {
	Name = "SambungKataUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	Parent = playerGui
})

-- ============ RED VIGNETTE (urgency overlay) ============

local redVignette = create("ImageLabel", {
	Name = "RedVignette",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Image = "rbxassetid://1526405635",
	ImageColor3 = Color3.fromRGB(180, 0, 0),
	ImageTransparency = 1,
	ScaleType = Enum.ScaleType.Stretch,
	ZIndex = 99,
	Visible = false,
	Parent = gui
})

-- ============ CAMERA SYSTEM ============

local cameraActive = false
local cameraConn = nil
local cameraTarget = nil

local function getHeadCFrame(plrName)
	local p = Players:FindFirstChild(plrName)
	if not p then return nil end
	local char = p.Character
	if not char then return nil end
	local head = char:FindFirstChild("Head")
	if not head then return nil end
	return head.CFrame
end

local function startCameraZoom(targetName)
	cameraTarget = targetName
	if cameraActive then return end
	cameraActive = true
	camera.CameraType = Enum.CameraType.Scriptable
	if cameraConn then cameraConn:Disconnect() end
	cameraConn = RunService.RenderStepped:Connect(function()
		if not cameraActive or not cameraTarget then return end
		local hcf = getHeadCFrame(cameraTarget)
		if not hcf then return end
		local targetPos = hcf.Position + hcf.LookVector * 4.5 + Vector3.new(0, 1.2, 0)
		local lookAt = hcf.Position + Vector3.new(0, 0.3, 0)
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(targetPos, lookAt), 0.07)
	end)
end

local function stopCameraZoom()
	cameraActive = false
	cameraTarget = nil
	if cameraConn then cameraConn:Disconnect(); cameraConn = nil end
	camera.CameraType = Enum.CameraType.Custom
end

-- ============ SCREEN FLASH ============

local flashFrame = create("Frame", {
	Name = "Flash",
	Size = UDim2.new(1,0,1,0),
	BackgroundColor3 = C.white,
	BackgroundTransparency = 1,
	ZIndex = 100,
	Parent = gui
})

local function screenFlash(color, intensity, dur)
	flashFrame.BackgroundColor3 = color or C.white
	flashFrame.BackgroundTransparency = intensity or 0.7
	tw(flashFrame, {BackgroundTransparency = 1}, dur or 0.5)
end

-- ============ SCREEN SHAKE ============

local function screenShake(intensity, dur)
	if not cameraActive then return end
	task.spawn(function()
		local t = 0
		while t < (dur or 0.3) do
			local ox = (math.random() - 0.5) * intensity * 0.1
			local oy = (math.random() - 0.5) * intensity * 0.1
			camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0)
			task.wait(0.03)
			t += 0.03
		end
	end)
end

-- ============ PUNCH ANIMATION ============

local function findArmMotor(char)
	local rua = char:FindFirstChild("RightUpperArm")
	if rua then
		local motor = rua:FindFirstChild("RightShoulder")
		if motor and motor:IsA("Motor6D") then return motor, "R15" end
	end
	local torso = char:FindFirstChild("Torso")
	if torso then
		local motor = torso:FindFirstChild("Right Shoulder")
		if motor and motor:IsA("Motor6D") then return motor, "R6" end
	end
	return nil, nil
end

local function findTorsoMotor(char)
	local ut = char:FindFirstChild("UpperTorso")
	if ut then
		local motor = ut:FindFirstChild("Waist")
		if motor and motor:IsA("Motor6D") then return motor end
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		local motor = root:FindFirstChild("RootJoint")
		if motor and motor:IsA("Motor6D") then return motor end
	end
	return nil
end

local function playPunchAnimation(attackerName, victimName, heartsLeft)
	local attackerPlayer = Players:FindFirstChild(attackerName)
	local victimPlayer = Players:FindFirstChild(victimName)
	if not attackerPlayer or not victimPlayer then return end
	local attackerChar = attackerPlayer.Character
	local victimChar = victimPlayer.Character
	if not attackerChar or not victimChar then return end
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")
	if not victimRoot or not attackerRoot then return end

	local brutal = heartsLeft <= 0 and 3 or (heartsLeft <= 1 and 2 or 1)

	local armMotor, rigType = findArmMotor(attackerChar)
	if armMotor then
		local origC0 = armMotor.C0
		local windUp = origC0 * CFrame.Angles(math.rad(60), 0, math.rad(20))
		tw(armMotor, {C0 = windUp}, 0.1)
		task.delay(0.12, function()
			local punchForward = origC0 * CFrame.Angles(math.rad(-100 - brutal * 10), 0, math.rad(-10))
			tw(armMotor, {C0 = punchForward}, 0.06, Enum.EasingStyle.Quad)
			task.delay(0.4, function()
				tw(armMotor, {C0 = origC0}, 0.3, Enum.EasingStyle.Quad)
			end)
		end)
	end

	local attackerTorso = findTorsoMotor(attackerChar)
	if attackerTorso then
		local origTorsoC0 = attackerTorso.C0
		task.delay(0.1, function()
			tw(attackerTorso, {C0 = origTorsoC0 * CFrame.Angles(math.rad(-20 - brutal * 5), 0, 0)}, 0.08)
			task.delay(0.35, function()
				tw(attackerTorso, {C0 = origTorsoC0}, 0.3)
			end)
		end)
	end

	task.delay(0.2, function()
		if not victimRoot or not victimRoot.Parent then return end

		local victimTorso = findTorsoMotor(victimChar)
		if victimTorso then
			local origVC0 = victimTorso.C0
			local flinchAngle = 15 + brutal * 10
			tw(victimTorso, {C0 = origVC0 * CFrame.Angles(math.rad(flinchAngle), math.rad(math.random(-5, 5) * brutal), 0)}, 0.08)
			task.delay(0.3 + brutal * 0.1, function()
				tw(victimTorso, {C0 = origVC0}, 0.4)
			end)
		end

		local victimHead = victimChar:FindFirstChild("Head")
		if victimHead then
			local neck = victimHead:FindFirstChild("Neck") or (victimChar:FindFirstChild("UpperTorso") and victimChar.UpperTorso:FindFirstChild("Neck"))
			if not neck then
				local t = victimChar:FindFirstChild("Torso")
				if t then neck = t:FindFirstChild("Neck") end
			end
			if neck and neck:IsA("Motor6D") then
				local origNeck = neck.C0
				tw(neck, {C0 = origNeck * CFrame.Angles(math.rad(20 * brutal), math.rad(math.random(-15, 15) * brutal), 0)}, 0.06)
				task.delay(0.15, function()
					tw(neck, {C0 = origNeck * CFrame.Angles(math.rad(-10), math.rad(math.random(-10, 10)), 0)}, 0.1)
					task.delay(0.2, function()
						tw(neck, {C0 = origNeck}, 0.3)
					end)
				end)
			end
		end

		local impact = Instance.new("Part")
		impact.Size = Vector3.new(2, 2, 2) * brutal
		impact.Shape = Enum.PartType.Ball
		impact.Position = victimRoot.Position + Vector3.new(0, 2, 0)
		impact.Anchored = true; impact.CanCollide = false
		impact.Material = Enum.Material.Neon
		impact.Color = brutal >= 3 and Color3.fromRGB(255,20,20) or (brutal >= 2 and Color3.fromRGB(255,80,40) or Color3.fromRGB(255,180,80))
		impact.Transparency = 0.2; impact.Parent = workspace
		tw(impact, {Size = Vector3.new(6,6,6)*brutal, Transparency = 1}, 0.5, Enum.EasingStyle.Quint)
		task.delay(0.6, function() impact:Destroy() end)

		for i = 1, brutal do
			task.delay((i-1)*0.08, function()
				local ring = Instance.new("Part")
				ring.Size = Vector3.new(0.1,1,1); ring.Anchored = true; ring.CanCollide = false
				ring.Material = Enum.Material.Neon; ring.Color = Color3.fromRGB(255,60,60)
				ring.Transparency = 0.3; ring.Shape = Enum.PartType.Cylinder
				ring.CFrame = CFrame.new(victimRoot.Position + Vector3.new(0,1,0)) * CFrame.Angles(0,0,math.rad(90))
				ring.Parent = workspace
				local rs = brutal*5+i*4
				tw(ring, {Size=Vector3.new(0.05,rs,rs), Transparency=1}, 0.6, Enum.EasingStyle.Quint)
				task.delay(0.7, function() ring:Destroy() end)
			end)
		end

		for i = 1, brutal*3 do
			local debris = Instance.new("Part")
			debris.Size = Vector3.new(0.3,0.3,0.3)*math.random(5,15)/10
			debris.Position = victimRoot.Position + Vector3.new(math.random(-1,1),2,math.random(-1,1))
			debris.Anchored = false; debris.CanCollide = false; debris.Material = Enum.Material.Neon
			debris.Color = i%2==0 and Color3.fromRGB(255,50,50) or Color3.fromRGB(255,200,50)
			debris.Parent = workspace
			debris.Velocity = Vector3.new(math.random(-30,30)*brutal, math.random(20,50)*brutal, math.random(-30,30)*brutal)
			tw(debris, {Transparency=1}, 0.8+math.random()*0.5)
			task.delay(1.5, function() debris:Destroy() end)
		end

		screenShake(brutal*6, brutal*0.2)
		screenFlash(C.red, 0.4+(3-brutal)*0.15, 0.3+brutal*0.15)
		redVignette.Visible = true
		tw(redVignette, {ImageTransparency=0.15}, 0.08)
		task.delay(0.25, function()
			tw(redVignette, {ImageTransparency=1}, 0.5)
			task.delay(0.5, function() redVignette.Visible = false end)
		end)
	end)
end

-- ============ FLOATING TEXT ============

local function spawnText(text, pos, color, size, dur, yDrift, font)
	local lbl = create("TextLabel", {
		Size = UDim2.new(0, 600, 0, 60),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = font or F.big,
		Text = text,
		TextSize = size or 24,
		TextColor3 = color or C.darkText,
		TextStrokeColor3 = C.white,
		TextStrokeTransparency = 0.3,
		ZIndex = 50,
		Parent = gui
	})
	lbl.TextTransparency = 0.3
	tw(lbl, {TextTransparency = 0}, 0.15)
	task.delay(0.15, function()
		tw(lbl, {
			Position = pos + UDim2.new(0, 0, 0, yDrift or -90),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}, dur or 1.8)
	end)
	task.delay((dur or 1.8) + 0.3, function() lbl:Destroy() end)
	return lbl
end

-- ============ HEART BREAK PARTICLES ============

local function spawnHeartBreak(px, py)
	for i = 1, 12 do
		local sz = math.random(16, 30)
		local h = create("TextLabel", {
			Size = UDim2.new(0, sz, 0, sz),
			Position = UDim2.new(px, 0, py, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = F.heart,
			Text = "\u{2764}",
			TextSize = sz,
			TextColor3 = C.heartRed,
			TextStrokeTransparency = 1,
			Rotation = math.random(-45, 45),
			ZIndex = 90,
			Parent = gui
		})
		local dx = math.random(-180, 180)
		local dy = math.random(-140, 60)
		tw(h, {
			Position = UDim2.new(px, dx, py, dy),
			TextTransparency = 1,
			Rotation = math.random(-220, 220),
			TextSize = math.random(4, 8),
		}, math.random(80, 140) / 100, Enum.EasingStyle.Quint)
		task.delay(1.5, function() h:Destroy() end)
	end
end

-- ============ STATE ============

local TURN_TIME = 15
local isMyTurn = false
local gameActive = false
local wordHistory = {}
local activeNames = {}
local typingBuffer = ""
local inputActive = false
local currentTurnPlayer = ""

-- ============ MOBILE DETECTION ============

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local UI_SCALE = IS_MOBILE and 1 or 1.35

-- ============ MAIN GAME PANEL ============

local gamePanel = create("Frame", {
	Name = "GamePanel",
	Size = UDim2.new(0, 340 * UI_SCALE, 0, 300 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 10,
	Parent = gui
})

local turnBanner = create("Frame", {
	Size = UDim2.new(1, 10, 0, 44 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 4 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = C.green,
	BackgroundTransparency = 0.15,
	ZIndex = 11,
	Parent = gamePanel
})
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = turnBanner})

local playerNameLbl = create("TextLabel", {
	Size = UDim2.new(1, -16, 1, 0),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = F.big,
	Text = "",
	TextSize = 22 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0,
	ZIndex = 12,
	Parent = turnBanner
})

local tilesFrame = create("Frame", {
	Size = UDim2.new(1, -30, 0, 50 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 44 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	ZIndex = 11,
	Parent = gamePanel
})

local letterTiles = {}

local function updateLetterTiles(word)
	for _, tile in pairs(letterTiles) do tile:Destroy() end
	letterTiles = {}
	if word == "" then return end

	local letters = {}
	for i = 1, #word do letters[i] = word:sub(i, i):upper() end

	local maxTile = 42 * UI_SCALE
	local gap = 6 * UI_SCALE
	local containerW = 310 * UI_SCALE
	local tileSize = math.min(maxTile, math.floor((containerW - (#letters - 1) * gap) / #letters))
	local totalWidth = #letters * tileSize + (#letters - 1) * gap
	local startX = (containerW - totalWidth) / 2

	for i, letter in ipairs(letters) do
		local tile = create("Frame", {
			Size = UDim2.new(0, tileSize, 0, tileSize),
			Position = UDim2.new(0, startX + (i-1) * (tileSize + gap), 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = C.tileBg,
			ZIndex = 12,
			Parent = tilesFrame
		})
		create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = tile})
		create("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = F.letter,
			Text = letter,
			TextSize = math.min(24, tileSize - 8),
			TextColor3 = C.tileText,
			TextStrokeTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 13,
			Parent = tile
		})
		letterTiles[i] = tile
		tile.Size = UDim2.new(0, 0, 0, 0)
		tw(tile, {Size = UDim2.new(0, tileSize, 0, tileSize)}, 0.2 + i * 0.03, Enum.EasingStyle.Back)
	end
end

local hintLbl = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 24 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 102 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = F.sub,
	Text = "",
	TextSize = 14 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.4,
	ZIndex = 11,
	Parent = gamePanel
})

local letterBadge = create("Frame", {
	Size = UDim2.new(0, 36 * UI_SCALE, 0, 36 * UI_SCALE),
	Position = UDim2.new(0.5, 60 * UI_SCALE, 0, 99 * UI_SCALE),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundColor3 = C.tileBg,
	ZIndex = 12,
	Visible = false,
	Parent = gamePanel
})
create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = letterBadge})

local letterBadgeLbl = create("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = F.letter,
	Text = "",
	TextSize = 20 * UI_SCALE,
	TextColor3 = C.tileText,
	TextStrokeTransparency = 1,
	ZIndex = 13,
	Parent = letterBadge
})

local heartsLbl = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 30 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 137 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = F.heart,
	Text = "",
	TextSize = 24 * UI_SCALE,
	TextColor3 = C.heartRed,
	TextStrokeTransparency = 1,
	ZIndex = 11,
	Parent = gamePanel
})

local timerLbl = create("TextLabel", {
	Size = UDim2.new(0, 80 * UI_SCALE, 0, 28 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 172 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = F.timer,
	Text = "",
	TextSize = 20 * UI_SCALE,
	TextColor3 = C.green,
	TextStrokeTransparency = 1,
	ZIndex = 11,
	Parent = gamePanel
})

local timerBarBg = create("Frame", {
	Size = UDim2.new(0.7, 0, 0, 4 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 202 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = C.tileBg,
	ZIndex = 11,
	Parent = gamePanel
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = timerBarBg})

local timerBar = create("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = C.green,
	ZIndex = 12,
	Parent = timerBarBg
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = timerBar})

local statusLbl = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 22 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0, 212 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = F.status,
	Text = "",
	TextSize = 14 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.4,
	ZIndex = 11,
	Parent = gamePanel
})

local chainLbl = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 18 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 1, -8 * UI_SCALE),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundTransparency = 1,
	Font = F.chain,
	Text = "",
	TextSize = 11 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.4,
	ZIndex = 11,
	Parent = gamePanel
})

-- ============ INPUT BAR (PC only) ============

local inputBar = create("Frame", {
	Name = "InputBar",
	Size = UDim2.new(1, -110, 0, 46),
	Position = UDim2.new(0, 10, 1, -10),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = C.inputBg,
	Visible = false,
	ZIndex = 15,
	Parent = gui
})
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = inputBar})
create("UIStroke", {Color = C.inputBorder, Thickness = 1, Parent = inputBar})

-- PC invisible TextBox to capture keyboard input
local typingBox = create("TextBox", {
	Size = IS_MOBILE and UDim2.new(0, 1, 0, 1) or UDim2.new(1, -16, 1, -8),
	Position = IS_MOBILE and UDim2.new(0, -200, 0, -200) or UDim2.new(0, 14, 0.5, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundTransparency = 1,
	Font = F.typing,
	Text = "",
	PlaceholderText = IS_MOBILE and "" or "Ketik kata...",
	PlaceholderColor3 = C.lightText,
	TextSize = IS_MOBILE and 1 or 18,
	TextColor3 = IS_MOBILE and Color3.new(1,1,1) or C.darkText,
	TextTransparency = IS_MOBILE and 1 or 0,
	TextStrokeTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	MultiLine = false,
	ZIndex = 16,
	Parent = IS_MOBILE and gui or inputBar
})

-- PC green submit button
local submitBtn = create("TextButton", {
	Size = UDim2.new(0, 82, 0, 46),
	Position = UDim2.new(1, -10, 1, -10),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = C.green,
	Font = F.status,
	Text = "Masuk",
	TextSize = 16,
	TextColor3 = C.white,
	TextStrokeTransparency = 1,
	AutoButtonColor = true,
	Visible = false,
	ZIndex = 20,
	Parent = gui
})
create("UICorner", {CornerRadius = UDim.new(0, 12), Parent = submitBtn})

-- ============ CUSTOM MOBILE KEYBOARD ============
-- Only built if on mobile; on PC this whole section is skipped

local mobileKeyboard = nil    -- the keyboard Frame
local mobileWordDisplay = nil -- word being typed shown above keyboard
local mobileTyping = ""       -- internal buffer for mobile keyboard

local KEY_ROWS = {
	{"Q","W","E","R","T","Y","U","I","O","P"},
	{"A","S","D","F","G","H","J","K","L"},
	{"Z","X","C","V","B","N","M"},
}

local function buildMobileKeyboard()
	if not IS_MOBILE then return end

	-- Keyboard backdrop
	local kbPanel = create("Frame", {
		Name = "MobileKeyboard",
		Size = UDim2.new(1, 0, 0, 220),
		Position = UDim2.new(0, 0, 1, 0),  -- starts off screen
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = C.keyboardBg,
		ZIndex = 25,
		Visible = false,
		Parent = gui
	})
	create("UICorner", {CornerRadius = UDim.new(0, 0), Parent = kbPanel})

	-- Word preview strip above keyboard
	local wordPreviewBar = create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(210, 210, 218),
		ZIndex = 26,
		Parent = kbPanel
	})

	local wordPreviewLbl = create("TextLabel", {
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Font = F.typing,
		Text = "",
		TextSize = 22,
		TextColor3 = C.darkText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		ZIndex = 27,
		Parent = wordPreviewBar
	})

	-- Backspace button on preview bar
	local bkspBtn = create("TextButton", {
		Size = UDim2.new(0, 80, 0, 34),
		Position = UDim2.new(1, -88, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(240, 100, 80),
		Font = F.key,
		Text = "⌫",
		TextSize = 20,
		TextColor3 = C.white,
		AutoButtonColor = true,
		ZIndex = 27,
		Parent = wordPreviewBar
	})
	create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = bkspBtn})

	-- Key rows container
	local rowsHolder = create("Frame", {
		Size = UDim2.new(1, -8, 0, 168),
		Position = UDim2.new(0.5, 0, 0, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 26,
		Parent = kbPanel
	})

	local ROW_H = 48
	local GAP = 5

	for rowIdx, rowKeys in ipairs(KEY_ROWS) do
		local numKeys = #rowKeys
		local rowFrame = create("Frame", {
			Size = UDim2.new(1, 0, 0, ROW_H),
			Position = UDim2.new(0, 0, 0, (rowIdx - 1) * (ROW_H + GAP)),
			BackgroundTransparency = 1,
			ZIndex = 26,
			Parent = rowsHolder
		})

		local keyW = math.floor((rowsHolder.AbsoluteSize.X - (numKeys - 1) * GAP) / numKeys)
		-- Use scale so it sizes dynamically
		local keyWScale = (1 / numKeys) - (GAP * (numKeys - 1)) / (numKeys * rowsHolder.AbsoluteSize.X + 0.0001)

		-- Extra offset for centering shorter rows
		local totalKeysW = numKeys * 40 + (numKeys - 1) * GAP
		local offsetX = 0
		if rowIdx == 2 then offsetX = 10 end
		if rowIdx == 3 then offsetX = 20 end

		for keyIdx, letter in ipairs(rowKeys) do
			local keyBtn = create("TextButton", {
				Size = UDim2.new(0, 40, 0, ROW_H - 6),
				Position = UDim2.new(0, offsetX + (keyIdx - 1) * (40 + GAP), 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = C.keyBg,
				Font = F.key,
				Text = letter,
				TextSize = 18,
				TextColor3 = C.darkText,
				AutoButtonColor = false,
				ZIndex = 27,
				Parent = rowFrame
			})
			create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = keyBtn})
			create("UIStroke", {Color = Color3.fromRGB(180,180,190), Thickness = 1, Parent = keyBtn})

			-- Press effect + letter input
			keyBtn.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Touch then return end
				tw(keyBtn, {BackgroundColor3 = C.keyPress, Size = UDim2.new(0, 38, 0, ROW_H - 10)}, 0.05)
			end)
			keyBtn.InputEnded:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Touch then return end
				tw(keyBtn, {BackgroundColor3 = C.keyBg, Size = UDim2.new(0, 40, 0, ROW_H - 6)}, 0.1)
			end)
			keyBtn.MouseButton1Click:Connect(function()
				if not inputActive then return end
				mobileTyping = mobileTyping .. letter:lower()
				wordPreviewLbl.Text = mobileTyping:upper()
				typingBuffer = mobileTyping
				pendingWord = mobileTyping
				updateLetterTiles(mobileTyping)
				if TypingUpdate then TypingUpdate:FireServer(mobileTyping) end
			end)
		end
	end

	-- Bottom row: SUBMIT button (full width)
	local submitRowFrame = create("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		Position = UDim2.new(0, 0, 0, 3 * (ROW_H + GAP) + 4),
		BackgroundTransparency = 1,
		ZIndex = 26,
		Parent = rowsHolder
	})

	local kbSubmitBtn = create("TextButton", {
		Size = UDim2.new(1, -8, 0, ROW_H - 6),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.green,
		Font = F.status,
		Text = "MASUK ✓",
		TextSize = 20,
		TextColor3 = C.white,
		AutoButtonColor = true,
		ZIndex = 27,
		Parent = submitRowFrame
	})
	create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = kbSubmitBtn})

	kbSubmitBtn.MouseButton1Click:Connect(function()
		if not inputActive then return end
		if #mobileTyping > 0 then
			doSubmit()
		end
	end)

	bkspBtn.MouseButton1Click:Connect(function()
		if not inputActive then return end
		if #mobileTyping > 0 then
			mobileTyping = mobileTyping:sub(1, #mobileTyping - 1)
			wordPreviewLbl.Text = mobileTyping:upper()
			typingBuffer = mobileTyping
			pendingWord = mobileTyping
			updateLetterTiles(mobileTyping)
			if TypingUpdate then TypingUpdate:FireServer(mobileTyping) end
		end
	end)

	mobileKeyboard = kbPanel
	mobileWordDisplay = wordPreviewLbl
end

buildMobileKeyboard()

local function showMobileKeyboard()
	if not IS_MOBILE or not mobileKeyboard then return end
	mobileKeyboard.Visible = true
	mobileKeyboard.Position = UDim2.new(0, 0, 1, 0)
	tw(mobileKeyboard, {Position = UDim2.new(0, 0, 1, -220)}, 0.25, Enum.EasingStyle.Quint)
end

local function hideMobileKeyboard()
	if not IS_MOBILE or not mobileKeyboard then return end
	tw(mobileKeyboard, {Position = UDim2.new(0, 0, 1, 0)}, 0.2, Enum.EasingStyle.Quad)
	task.delay(0.22, function() mobileKeyboard.Visible = false end)
end

-- ============ PLAYER INFO (top corners) ============

local p1NameLbl = create("TextLabel", {
	Size = UDim2.new(0, 200 * UI_SCALE, 0, 22 * UI_SCALE),
	Position = UDim2.new(0.03, 0, 0.05, 0),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundTransparency = 1,
	Font = F.name,
	Text = "",
	TextSize = 16 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.3,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	ZIndex = 10,
	Parent = gui
})

local p1HeartsLbl = create("TextLabel", {
	Size = UDim2.new(0, 200 * UI_SCALE, 0, 22 * UI_SCALE),
	Position = UDim2.new(0.03, 0, 0.05, 24 * UI_SCALE),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundTransparency = 1,
	Font = F.heart,
	Text = "",
	TextSize = 18 * UI_SCALE,
	TextColor3 = C.heartRed,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.4,
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	ZIndex = 10,
	Parent = gui
})

local p2NameLbl = create("TextLabel", {
	Size = UDim2.new(0, 200 * UI_SCALE, 0, 22 * UI_SCALE),
	Position = UDim2.new(0.97, 0, 0.05, 0),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Font = F.name,
	Text = "",
	TextSize = 16 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.3,
	TextXAlignment = Enum.TextXAlignment.Right,
	Visible = false,
	ZIndex = 10,
	Parent = gui
})

local p2HeartsLbl = create("TextLabel", {
	Size = UDim2.new(0, 200 * UI_SCALE, 0, 22 * UI_SCALE),
	Position = UDim2.new(0.97, 0, 0.05, 24 * UI_SCALE),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundTransparency = 1,
	Font = F.heart,
	Text = "",
	TextSize = 18 * UI_SCALE,
	TextColor3 = C.heartRed,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.4,
	TextXAlignment = Enum.TextXAlignment.Right,
	Visible = false,
	ZIndex = 10,
	Parent = gui
})

-- ============ UI FUNCTIONS ============

local function showGameUI()
	gameActive = true
	gamePanel.Visible = true
	p1NameLbl.Visible = true; p1HeartsLbl.Visible = true
	p2NameLbl.Visible = true; p2HeartsLbl.Visible = true
	p1NameLbl.TextTransparency = 1; p2NameLbl.TextTransparency = 1
	p1HeartsLbl.TextTransparency = 1; p2HeartsLbl.TextTransparency = 1
	tw(p1NameLbl, {TextTransparency = 0}, 0.5)
	tw(p2NameLbl, {TextTransparency = 0}, 0.5)
	tw(p1HeartsLbl, {TextTransparency = 0}, 0.6)
	tw(p2HeartsLbl, {TextTransparency = 0}, 0.6)
end

local pendingWord = ""

local function hideGameUI()
	gameActive = false
	inputActive = false
	typingBuffer = ""
	pendingWord = ""
	gamePanel.Visible = false
	inputBar.Visible = false
	submitBtn.Visible = false
	hideMobileKeyboard()
	p1NameLbl.Visible = false; p1HeartsLbl.Visible = false
	p2NameLbl.Visible = false; p2HeartsLbl.Visible = false
	redVignette.Visible = false
	redVignette.ImageTransparency = 1
end

local function heartsStr(count, max)
	max = max or 3
	local s = ""
	for i = 1, max do
		s = s .. (i <= count and "\u{2764}" or "\u{25CB}")
		if i < max then s = s .. "  " end
	end
	return s
end

local function updatePlayers(hearts, names)
	if names then activeNames = names end
	local n1 = activeNames[1] or ""
	local n2 = activeNames[2] or ""
	p1NameLbl.Text = n1
	p2NameLbl.Text = n2
	if hearts then
		p1HeartsLbl.Text = hearts[n1] and heartsStr(hearts[n1]) or ""
		p2HeartsLbl.Text = hearts[n2] and heartsStr(hearts[n2]) or ""
		local showFor = currentTurnPlayer ~= "" and currentTurnPlayer or player.Name
		heartsLbl.Text = hearts[showFor] and heartsStr(hearts[showFor]) or ""
	end
end

local function highlightTurn(pName)
	local isP1 = activeNames[1] == pName
	local isP2 = activeNames[2] == pName
	local myTurn = pName == player.Name

	tw(p1NameLbl, {TextColor3 = isP1 and C.white or C.lightText, TextSize = (isP1 and 18 or 14) * UI_SCALE}, 0.3)
	tw(p2NameLbl, {TextColor3 = isP2 and C.white or C.lightText, TextSize = (isP2 and 18 or 14) * UI_SCALE}, 0.3)
	tw(p1HeartsLbl, {TextTransparency = isP1 and 0 or 0.5}, 0.3)
	tw(p2HeartsLbl, {TextTransparency = isP2 and 0 or 0.5}, 0.3)

	if myTurn then
		playerNameLbl.Text = "GILIRANMU!"
		tw(turnBanner, {BackgroundColor3 = C.green, BackgroundTransparency = 0.1}, 0.3)
	else
		playerNameLbl.Text = "Giliran " .. pName
		tw(turnBanner, {BackgroundColor3 = C.red, BackgroundTransparency = 0.15}, 0.3)
	end

	turnBanner.Size = UDim2.new(1, 10, 0, 44 * UI_SCALE)
	tw(turnBanner, {Size = UDim2.new(1, 20, 0, 48 * UI_SCALE)}, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.15, function()
		tw(turnBanner, {Size = UDim2.new(1, 10, 0, 44 * UI_SCALE)}, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
end

local function updateChain()
	local d = {}
	for i = math.max(1, #wordHistory - 5), #wordHistory do
		d[#d+1] = wordHistory[i]:upper()
	end
	chainLbl.Text = table.concat(d, "  \u{2023}  ")
end

local function resetAll()
	hideGameUI()
	wordHistory = {}
	activeNames = {}
	currentTurnPlayer = ""
	hintLbl.Text = ""
	letterBadgeLbl.Text = ""
	letterBadge.Visible = false
	timerLbl.Text = ""
	statusLbl.Text = ""
	chainLbl.Text = ""
	typingBox.Text = ""
	heartsLbl.Text = ""
	playerNameLbl.Text = ""
	p1NameLbl.Text = ""; p2NameLbl.Text = ""
	p1HeartsLbl.Text = ""; p2HeartsLbl.Text = ""
	mobileTyping = ""
	if mobileWordDisplay then mobileWordDisplay.Text = "" end
	updateLetterTiles("")
end

-- ============ TYPING INPUT ============

local lastTextLen = 0
local isSubmitting = false
local ignoreTextChange = false

local function doSubmit()
	if isSubmitting then return end
	local w = pendingWord:gsub("%s+", "")
	if w == "" then return end
	if not inputActive then return end
	isSubmitting = true
	screenFlash(C.white, 0.85, 0.2)
	typingBuffer = ""
	pendingWord = ""
	mobileTyping = ""
	lastTextLen = 0
	if mobileWordDisplay then mobileWordDisplay.Text = "" end
	ignoreTextChange = true
	typingBox.Text = ""
	ignoreTextChange = false
	updateLetterTiles("")
	if not IS_MOBILE then typingBox:ReleaseFocus() end
	SendWord:FireServer(w)
	task.delay(0.5, function()
		isSubmitting = false
		if not IS_MOBILE and inputActive then
			typingBox:CaptureFocus()
		end
	end)
end

local function setInputActive(active)
	inputActive = active
	isMyTurn = active
	if active then
		typingBuffer = ""
		pendingWord = ""
		mobileTyping = ""
		lastTextLen = 0
		isSubmitting = false
		typingBox.Text = ""
		if mobileWordDisplay then mobileWordDisplay.Text = "" end
		updateLetterTiles("")

		if IS_MOBILE then
			-- Show custom keyboard, never open device keyboard
			showMobileKeyboard()
			inputBar.Visible = false
			submitBtn.Visible = false
		else
			-- PC: show input bar, capture focus to invisible TextBox
			inputBar.Visible = true
			submitBtn.Visible = true
			task.delay(0.1, function()
				if inputActive then typingBox:CaptureFocus() end
			end)
		end
	else
		inputBar.Visible = false
		submitBtn.Visible = false
		hideMobileKeyboard()
		if not IS_MOBILE then typingBox:ReleaseFocus() end
		typingBox.Text = ""
		typingBuffer = ""
		pendingWord = ""
		mobileTyping = ""
		lastTextLen = 0
	end
end

-- PC: track TextBox changes (desktop only, mobile uses button callbacks)
typingBox:GetPropertyChangedSignal("Text"):Connect(function()
	if IS_MOBILE then return end
	if ignoreTextChange then return end
	if not inputActive then return end
	local raw = typingBox.Text
	local cleaned = raw:gsub("[^%a]", "")
	if cleaned ~= raw then
		ignoreTextChange = true
		typingBox.Text = cleaned
		ignoreTextChange = false
	end
	typingBuffer = cleaned:lower()
	pendingWord = typingBuffer
	lastTextLen = #typingBuffer
	updateLetterTiles(typingBuffer)
	if inputActive and TypingUpdate then
		TypingUpdate:FireServer(typingBuffer)
	end
end)

-- PC: Enter key submits
typingBox.FocusLost:Connect(function(enterPressed)
	if IS_MOBILE then return end
	if enterPressed and inputActive and #pendingWord > 0 then
		doSubmit()
	end
	if not IS_MOBILE and inputActive and not isSubmitting then
		task.delay(0.1, function()
			if inputActive then typingBox:CaptureFocus() end
		end)
	end
end)

-- PC submit button
submitBtn.MouseButton1Click:Connect(function()
	if not inputActive then return end
	if #pendingWord > 0 then
		doSubmit()
	else
		typingBox:CaptureFocus()
	end
end)

-- PC: tap input bar to open keyboard
inputBar.InputBegan:Connect(function(input)
	if IS_MOBILE then return end
	if not inputActive then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		typingBox:CaptureFocus()
	end
end)

-- ============ WAITING SCREEN ============

local waitOverlay = create("Frame", {
	Name = "WaitOverlay",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = C.overlay,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 30,
	Parent = gui
})

local waitPanel = create("Frame", {
	Name = "WaitPanel",
	Size = UDim2.new(0, 300 * UI_SCALE, 0, 180 * UI_SCALE),
	Position = UDim2.new(0.5, 0, 0.4, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 31,
	Parent = gui
})

local waitTitle = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 40),
	Position = UDim2.new(0.5, 0, 0, 24),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = F.title,
	Text = "SAMBUNG KATA",
	TextSize = 28 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeTransparency = 1,
	ZIndex = 32,
	Parent = waitPanel
})

local waitLine = create("Frame", {
	Size = UDim2.new(0, 0, 0, 2),
	Position = UDim2.new(0.5, 0, 0, 72),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = C.inputBorder,
	Visible = false,
	ZIndex = 32,
	Parent = waitPanel
})
create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = waitLine})

local waitLbl = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0.5, 0, 0, 86),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	Font = F.sub,
	Text = "",
	TextSize = 14 * UI_SCALE,
	TextColor3 = C.white,
	TextStrokeColor3 = C.shadow,
	TextStrokeTransparency = 0.4,
	ZIndex = 32,
	Parent = waitPanel
})

local waitDots = {}
for i = 1, 3 do
	waitDots[i] = create("Frame", {
		Size = UDim2.new(0, 8, 0, 8),
		Position = UDim2.new(0.5, -24 + (i-1) * 24, 0, 125),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.white,
		Visible = false,
		ZIndex = 32,
		Parent = waitPanel
	})
	create("UICorner", {CornerRadius = UDim.new(1, 0), Parent = waitDots[i]})
end

local waitAnimRunning = false

local function showWait(text)
	waitOverlay.Visible = true
	waitOverlay.BackgroundTransparency = 1
	tw(waitOverlay, {BackgroundTransparency = 0.5}, 0.6)
	waitPanel.Visible = true
	waitTitle.TextTransparency = 1
	tw(waitTitle, {TextTransparency = 0}, 0.5, Enum.EasingStyle.Quint)
	waitLine.Visible = true
	waitLine.Size = UDim2.new(0, 0, 0, 2)
	tw(waitLine, {Size = UDim2.new(0, 180, 0, 2)}, 0.8, Enum.EasingStyle.Quint)
	waitLbl.TextTransparency = 1
	task.delay(0.3, function() tw(waitLbl, {TextTransparency = 0}, 0.4) end)
	for _, d in pairs(waitDots) do d.Visible = true end
	waitAnimRunning = true
	waitLbl.Text = text or "Menunggu lawan"

	task.spawn(function()
		while waitAnimRunning do
			for i = 1, 3 do
				if not waitAnimRunning then return end
				tw(waitDots[i], {Size=UDim2.new(0,12,0,12), Position=UDim2.new(0.5,-24+(i-1)*24,0,119), BackgroundColor3=C.white}, 0.2)
				task.wait(0.12)
				tw(waitDots[i], {Size=UDim2.new(0,8,0,8), Position=UDim2.new(0.5,-24+(i-1)*24,0,125), BackgroundColor3=C.lightText}, 0.3, Enum.EasingStyle.Bounce)
			end
			task.wait(0.6)
		end
	end)
end

local function hideWait()
	waitAnimRunning = false
	tw(waitOverlay, {BackgroundTransparency = 1}, 0.3)
	tw(waitTitle, {TextTransparency = 1}, 0.2)
	tw(waitLbl, {TextTransparency = 1}, 0.2)
	tw(waitLine, {Size = UDim2.new(0, 0, 0, 2)}, 0.3)
	for _, d in pairs(waitDots) do tw(d, {BackgroundTransparency = 1}, 0.2) end
	task.delay(0.35, function()
		waitOverlay.Visible = false
		waitPanel.Visible = false
		waitLine.Visible = false
		for _, d in pairs(waitDots) do d.Visible = false; d.BackgroundTransparency = 0 end
	end)
end

-- ============ GAME EVENTS ============

GameUpdate.OnClientEvent:Connect(function(msg, data)

	if msg == "waitingOpponent" then
		hideGameUI()
		showWait("Menunggu lawan...")

	elseif msg == "spectating" then
		hideGameUI()
		local txt = data.queuePos and data.queuePos > 0
			and ("Menonton  \u{2022}  antrian #" .. data.queuePos) or "Menonton"
		showWait(txt)

	elseif msg == "countdown" then
		hideWait()
		spawnText(tostring(data.seconds), UDim2.new(0.5, 0, 0.4, 0), C.white, 72, 1, -50, F.title)
		screenFlash(C.white, 0.85, 0.3)

	elseif msg == "gameStart" then
		hideWait(); resetAll()
		showGameUI()
		wordHistory = {}
		updatePlayers({[data.p1] = 3, [data.p2] = 3}, {data.p1, data.p2})
		spawnText("MULAI!", UDim2.new(0.5, 0, 0.4, 0), C.white, 52, 2.5, -70, F.title)
		screenFlash(C.white, 0.7, 0.7)

	elseif msg == "turn" then
		currentTurnPlayer = data.playerName
		local myTurn = data.playerName == player.Name

		if data.lastLetter ~= "" then
			local prefix = data.lastLetter:upper()
			hintLbl.Text = "Hurufnya adalah:"
			letterBadgeLbl.Text = prefix
			letterBadge.Visible = true
			typingBox.PlaceholderText = "Ketik kata huruf " .. prefix .. "..."
		else
			hintLbl.Text = "Kata bebas!"
			letterBadge.Visible = false
			typingBox.PlaceholderText = "Ketik kata..."
		end

		startCameraZoom(data.playerName)
		timerBar.Size = UDim2.new(1, 0, 1, 0)
		timerBar.BackgroundColor3 = C.green

		if myTurn then
			statusLbl.Text = "GILIRANMU!"
			statusLbl.TextColor3 = C.green
			updateLetterTiles("")
			setInputActive(true)
		else
			statusLbl.Text = "Giliran " .. data.playerName
			statusLbl.TextColor3 = C.lightText
			updateLetterTiles("")
			setInputActive(false)
		end

		updatePlayers(data.hearts, data.activeNames)
		highlightTurn(data.playerName)

	elseif msg == "wordAccepted" then
		wordHistory[#wordHistory+1] = data.word
		updateChain()
		updateLetterTiles(data.word)
		spawnText(data.word:upper(), UDim2.new(0.5, 0, 0.65, 0), C.green, 28, 1.5, -120, F.big)
		screenFlash(C.green, 0.9, 0.2)
		for _, tile in pairs(letterTiles) do
			tw(tile, {BackgroundColor3 = Color3.fromRGB(200, 255, 200)}, 0.1)
			task.delay(0.3, function() tw(tile, {BackgroundColor3 = C.tileBg}, 0.3) end)
		end

	elseif msg == "heartLost" then
		local isP1 = activeNames[1] == data.playerName
		local side = isP1 and 0.12 or 0.88
		spawnText("-1 \u{2764}", UDim2.new(side, 0, 0.1, 0), C.red, 32, 1.5, -70, F.big)
		spawnText(data.reason or "", UDim2.new(0.5, 0, 0.55, 0), C.red, 14, 2.2, -60, F.status)
		if isP1 then p1HeartsLbl.Text = heartsStr(data.heartsLeft)
		else p2HeartsLbl.Text = heartsStr(data.heartsLeft) end
		if data.playerName == currentTurnPlayer then
			heartsLbl.Text = heartsStr(data.heartsLeft)
		end
		spawnHeartBreak(side, 0.07)
		screenFlash(C.red, 0.7, 0.4)
		if data.attackerName then
			startCameraZoom(data.playerName)
			playPunchAnimation(data.attackerName, data.playerName, data.heartsLeft)
		end

	elseif msg == "eliminated" or msg == "winner" then
		local winnerName = msg == "winner" and data.playerName or nil
		local loserName = msg == "eliminated" and data.playerName or nil
		local iWon = winnerName == player.Name
		local iLost = loserName == player.Name
		if not winnerName then
			winnerName = activeNames[1] == loserName and activeNames[2] or activeNames[1]
		end
		if not loserName then
			loserName = activeNames[1] == winnerName and activeNames[2] or activeNames[1]
		end

		setInputActive(false)

		if iWon then
			startCameraZoom(winnerName)
			spawnText("MENANG!", UDim2.new(0.5, 0, 0.32, 0), C.gold, 52, 4.5, -30, F.title)
			screenFlash(C.gold, 0.4, 1.2)
			task.spawn(function()
				for i = 1, 40 do
					local px = math.random(5, 95) / 100
					local confetti = create("Frame", {
						Size = UDim2.new(0, math.random(4, 10), 0, math.random(8, 16)),
						Position = UDim2.new(px, 0, -0.02, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = i%3==0 and C.gold or (i%3==1 and C.white or C.green),
						Rotation = math.random(0, 360),
						ZIndex = 55,
						Parent = gui
					})
					create("UICorner", {CornerRadius = UDim.new(0, 3), Parent = confetti})
					local drift = math.random(-40, 40)
					local fallDur = math.random(25, 45) / 10
					tw(confetti, {Position=UDim2.new(px+drift/1000,drift,1.1,0), Rotation=math.random(-720,720), BackgroundTransparency=0.3}, fallDur, Enum.EasingStyle.Linear)
					task.delay(fallDur + 0.5, function() confetti:Destroy() end)
					task.wait(0.05)
				end
			end)
			task.delay(0.5, function() screenFlash(C.white, 0.7, 0.8) end)

		elseif iLost then
			startCameraZoom(loserName)
			spawnText("KALAH!", UDim2.new(0.5, 0, 0.32, 0), C.red, 52, 4.5, -30, F.title)
			screenFlash(C.red, 0.3, 1.0)
			local lChar = Players:FindFirstChild(loserName)
			if lChar and lChar.Character then
				local hum = lChar.Character:FindFirstChild("Humanoid")
				if hum then hum.Sit = false end
			end
			local isP1 = activeNames[1] == loserName
			if isP1 then p1HeartsLbl.Text = heartsStr(0)
			else p2HeartsLbl.Text = heartsStr(0) end
		end

		task.delay(5, function() stopCameraZoom(); resetAll() end)

	elseif msg == "noWinner" then
		spawnText("SERI", UDim2.new(0.5, 0, 0.35, 0), C.medText, 44, 3.5, -50, F.title)
		screenFlash(C.white, 0.7, 0.6)
		setInputActive(false)
		task.delay(3.5, function() stopCameraZoom(); resetAll() end)

	elseif msg == "gameEnded" then
		spawnText(data.reason or "GAME OVER", UDim2.new(0.5, 0, 0.35, 0), C.red, 32, 3, -50, F.title)
		screenFlash(C.red, 0.7, 0.6)
		setInputActive(false)
		task.delay(2.5, function() stopCameraZoom(); resetAll() end)

	elseif msg == "leftSeat" then
		stopCameraZoom(); hideWait(); resetAll()

	elseif msg == "error" then
		spawnText(data.message, UDim2.new(0.5, 0, 0.6, 0), C.red, 16, 2.5, -50, F.status)
		screenFlash(C.red, 0.9, 0.2)
		for _, tile in pairs(letterTiles) do
			tw(tile, {BackgroundColor3 = Color3.fromRGB(255, 200, 200)}, 0.1)
			task.delay(0.4, function() tw(tile, {BackgroundColor3 = C.tileBg}, 0.3) end)
		end
	end
end)

-- ============ TIMER ============

TimerUpdate.OnClientEvent:Connect(function(sec)
	timerLbl.Text = "\u{23F1} " .. string.format("%.1f", sec)

	local frac = math.clamp(sec / TURN_TIME, 0, 1)
	tw(timerBar, {Size = UDim2.new(frac, 0, 1, 0)}, 0.8, Enum.EasingStyle.Linear)

	if sec <= 5 then
		tw(timerLbl, {TextColor3 = C.red}, 0.15)
		tw(timerBar, {BackgroundColor3 = C.red}, 0.15)

		if isMyTurn then
			redVignette.Visible = true
			local intensity = sec <= 2 and 0.25 or (sec <= 3 and 0.4 or 0.55)
			tw(redVignette, {ImageTransparency = intensity}, 0.15)
			task.delay(0.4, function()
				tw(redVignette, {ImageTransparency = intensity + 0.15}, 0.4)
			end)

			if sec <= 3 then
				screenFlash(C.red, 0.92, 0.15)
				tw(timerLbl, {TextSize = 24 * UI_SCALE}, 0.06)
				task.delay(0.06, function() tw(timerLbl, {TextSize = 20 * UI_SCALE}, 0.1) end)
				screenShake(3, 0.15)
			end
		end
	else
		tw(timerLbl, {TextColor3 = C.green}, 0.15)
		tw(timerBar, {BackgroundColor3 = C.green}, 0.15)
		if redVignette.Visible then
			tw(redVignette, {ImageTransparency = 1}, 0.3)
			task.delay(0.3, function() redVignette.Visible = false end)
		end
	end
end)

-- ============ OPPONENT TYPING ============

if TypingUpdate then TypingUpdate.OnClientEvent:Connect(function(playerName, text)
	if not gameActive then return end
	if playerName ~= player.Name then
		updateLetterTiles(text)
	end
end) end

-- ============ PLAYER COUNT BILLBOARDS ============

local clientBillboards = {}

local function setupClientBillboards()
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj.Name == "CountAnchor" and obj:IsA("BasePart") then
			if not clientBillboards[obj] then
				local bbName = "PlayerCountClient_" .. player.UserId
				local bb = obj:FindFirstChild(bbName)
				if not bb then
					bb = Instance.new("BillboardGui")
					bb.Name = bbName
					bb.Size = UDim2.new(0, 90, 0, 45)
					bb.StudsOffset = Vector3.new(0, 1, 0)
					bb.AlwaysOnTop = true
					bb.MaxDistance = 80
					bb.Adornee = obj
					bb.Parent = obj
				end
				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.new(1, 0, 1, 0)
				lbl.BackgroundTransparency = 1
				lbl.Font = Enum.Font.GothamBold
				lbl.Text = "0/2"
				lbl.TextSize = IS_MOBILE and 24 or 40
				lbl.TextColor3 = Color3.fromRGB(0, 255, 128)
				lbl.TextStrokeColor3 = Color3.fromRGB(0, 40, 20)
				lbl.TextStrokeTransparency = 0.2
				lbl.Parent = bb
				clientBillboards[obj] = lbl
			end
		end
	end
end

setupClientBillboards()

workspace.DescendantAdded:Connect(function(obj)
	if obj.Name == "CountAnchor" and obj:IsA("BasePart") then
		task.delay(0.1, setupClientBillboards)
	end
end)

task.spawn(function()
	while true do
		for anchor, lbl in pairs(clientBillboards) do
			if anchor and anchor.Parent then
				local serverBB = anchor:FindFirstChild("PlayerCount")
				if serverBB then
					local count = serverBB:GetAttribute("playerCount") or 0
					lbl.Text = count .. "/2"
					if count == 0 then
						lbl.TextColor3 = Color3.fromRGB(100, 100, 100)
					elseif count == 1 then
						lbl.TextColor3 = Color3.fromRGB(255, 200, 50)
					else
						lbl.TextColor3 = Color3.fromRGB(0, 255, 128)
					end
				end
			end
		end
		task.wait(0.1)
	end
end)

-- ============ CLEANUP ============

player.CharacterAdded:Connect(function()
	setInputActive(false)
end)

print("Sambung Kata UI loaded! (Custom mobile keyboard enabled)")
