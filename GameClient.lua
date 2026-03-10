-- GameClient - Sambung Kata
-- PC: physical keyboard (UserInputService, no TextBox UI)
-- Mobile: custom on-screen keyboard

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")
local camera     = workspace.CurrentCamera

local SendWord    = ReplicatedStorage:WaitForChild("SendWord")
local GameUpdate  = ReplicatedStorage:WaitForChild("GameUpdate")
local TimerUpdate = ReplicatedStorage:WaitForChild("TimerUpdate")
local TypingUpdate = ReplicatedStorage:WaitForChild("TypingUpdate", 10)

-- ============ COLORS ============
local C = {
	white      = Color3.fromRGB(255,255,255),
	darkText   = Color3.fromRGB(50,50,50),
	medText    = Color3.fromRGB(100,100,100),
	lightText  = Color3.fromRGB(170,170,170),
	tileBg     = Color3.fromRGB(240,240,240),
	tileText   = Color3.fromRGB(30,30,30),
	red        = Color3.fromRGB(220,60,60),
	heartRed   = Color3.fromRGB(220,50,60),
	green      = Color3.fromRGB(60,190,80),
	gold       = Color3.fromRGB(255,200,50),
	inputBorder= Color3.fromRGB(210,210,210),
	overlay    = Color3.fromRGB(0,0,0),
	shadow     = Color3.fromRGB(0,0,0),
	keyBg      = Color3.fromRGB(255,255,255),
	keyPress   = Color3.fromRGB(200,200,200),
	keyboardBg = Color3.fromRGB(180,180,190),
	previewBg  = Color3.fromRGB(210,210,218),
}
-- ============ FONTS ============
local F = {
	title  = Enum.Font.FredokaOne,
	big    = Enum.Font.GothamBlack,
	name   = Enum.Font.GothamBold,
	letter = Enum.Font.LuckiestGuy,
	status = Enum.Font.GothamBold,
	typing = Enum.Font.GothamBold,
	sub    = Enum.Font.GothamMedium,
	chain  = Enum.Font.Gotham,
	heart  = Enum.Font.GothamBold,
	timer  = Enum.Font.GothamBold,
	key    = Enum.Font.GothamBold,
}

-- ============ HELPERS ============
local function create(class, props)
	local inst = Instance.new(class)
	for k,v in pairs(props) do if k ~= "Parent" then inst[k] = v end end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function tw(obj, props, dur, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(dur or 0.25, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play(); return t
end

-- ============ PLATFORM ============
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local UI_SCALE  = IS_MOBILE and 1 or 1.35

-- ============ SCREEN GUI ============
local gui = create("ScreenGui", {
	Name = "SambungKataUI", ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true, AutoLocalize = false,
	Parent = playerGui,
})
-- ============ RED VIGNETTE ============
local redVignette = create("ImageLabel", {
	Size=UDim2.new(1,0,1,0), BackgroundTransparency=1,
	Image="rbxassetid://1526405635", ImageColor3=Color3.fromRGB(180,0,0),
	ImageTransparency=1, ScaleType=Enum.ScaleType.Stretch,
	ZIndex=99, Visible=false, Parent=gui,
})

-- ============ CAMERA ============
local cameraActive, cameraConn, cameraTarget = false, nil, nil
local function getHeadCFrame(name)
	local p = Players:FindFirstChild(name); if not p then return nil end
	local h = p.Character and p.Character:FindFirstChild("Head")
	return h and h.CFrame or nil
end
local function startCameraZoom(name)
	cameraTarget = name; if cameraActive then return end
	cameraActive = true; camera.CameraType = Enum.CameraType.Scriptable
	if cameraConn then cameraConn:Disconnect() end
	cameraConn = RunService.RenderStepped:Connect(function()
		if not cameraActive or not cameraTarget then return end
		local hcf = getHeadCFrame(cameraTarget); if not hcf then return end
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(
			hcf.Position + hcf.LookVector*4.5 + Vector3.new(0,1.2,0),
			hcf.Position + Vector3.new(0,0.3,0)), 0.07)
	end)
end
local function stopCameraZoom()
	cameraActive=false; cameraTarget=nil
	if cameraConn then cameraConn:Disconnect(); cameraConn=nil end
	camera.CameraType = Enum.CameraType.Custom
end

-- ============ SCREEN FLASH / SHAKE ============
local flashFrame = create("Frame", {Size=UDim2.new(1,0,1,0), BackgroundColor3=C.white, BackgroundTransparency=1, ZIndex=100, Parent=gui})
local function screenFlash(col, intensity, dur)
	flashFrame.BackgroundColor3 = col or C.white
	flashFrame.BackgroundTransparency = intensity or 0.7
	tw(flashFrame, {BackgroundTransparency=1}, dur or 0.5)
end
local function screenShake(intensity, dur)
	if not cameraActive then return end
	task.spawn(function()
		local t = 0
		while t < (dur or 0.3) do
			camera.CFrame = camera.CFrame * CFrame.new((math.random()-.5)*intensity*.1, (math.random()-.5)*intensity*.1, 0)
			task.wait(0.03); t += 0.03
		end
	end)
end
-- ============ PUNCH ANIMATION ============
local function findMotor(char, ...)
	for _, names in ipairs({...}) do
		local p = char:FindFirstChild(names[1])
		if p then local m = p:FindFirstChild(names[2]); if m and m:IsA("Motor6D") then return m end end
	end
end
local function playPunchAnimation(attackerName, victimName, heartsLeft)
	local ap=Players:FindFirstChild(attackerName); local vp=Players:FindFirstChild(victimName)
	if not ap or not vp then return end
	local ac=ap.Character; local vc=vp.Character; if not ac or not vc then return end
	local vr=vc:FindFirstChild("HumanoidRootPart"); if not vr then return end
	local brutal=heartsLeft<=0 and 3 or (heartsLeft<=1 and 2 or 1)
	local arm=findMotor(ac,{"RightUpperArm","RightShoulder"},{"Torso","Right Shoulder"})
	if arm then
		local o=arm.C0; tw(arm,{C0=o*CFrame.Angles(math.rad(60),0,math.rad(20))},0.1)
		task.delay(0.12,function()
			tw(arm,{C0=o*CFrame.Angles(math.rad(-100-brutal*10),0,math.rad(-10))},0.06,Enum.EasingStyle.Quad)
			task.delay(0.4,function() tw(arm,{C0=o},0.3,Enum.EasingStyle.Quad) end)
		end)
	end
	local at=findMotor(ac,{"UpperTorso","Waist"},{"HumanoidRootPart","RootJoint"})
	if at then local o=at.C0; task.delay(0.1,function()
		tw(at,{C0=o*CFrame.Angles(math.rad(-20-brutal*5),0,0)},0.08)
		task.delay(0.35,function() tw(at,{C0=o},0.3) end)
	end) end
	task.delay(0.2,function()
		if not vr or not vr.Parent then return end
		local vt=findMotor(vc,{"UpperTorso","Waist"},{"HumanoidRootPart","RootJoint"})
		if vt then local o=vt.C0; tw(vt,{C0=o*CFrame.Angles(math.rad(15+brutal*10),math.rad(math.random(-5,5)*brutal),0)},0.08); task.delay(0.3+brutal*.1,function() tw(vt,{C0=o},0.4) end) end
		local vh=vc:FindFirstChild("Head")
		if vh then
			local neck=vh:FindFirstChild("Neck") or (vc:FindFirstChild("UpperTorso") and vc.UpperTorso:FindFirstChild("Neck"))
			if not neck then local tor=vc:FindFirstChild("Torso"); if tor then neck=tor:FindFirstChild("Neck") end end
			if neck and neck:IsA("Motor6D") then local o=neck.C0
				tw(neck,{C0=o*CFrame.Angles(math.rad(20*brutal),math.rad(math.random(-15,15)*brutal),0)},0.06)
				task.delay(0.15,function() tw(neck,{C0=o*CFrame.Angles(math.rad(-10),math.rad(math.random(-10,10)),0)},0.1); task.delay(0.2,function() tw(neck,{C0=o},0.3) end) end)
			end
		end
		local impact=Instance.new("Part"); impact.Size=Vector3.new(2,2,2)*brutal; impact.Shape=Enum.PartType.Ball
		impact.Position=vr.Position+Vector3.new(0,2,0); impact.Anchored=true; impact.CanCollide=false
		impact.Material=Enum.Material.Neon; impact.Color=brutal>=3 and Color3.fromRGB(255,20,20) or (brutal>=2 and Color3.fromRGB(255,80,40) or Color3.fromRGB(255,180,80))
		impact.Transparency=0.2; impact.Parent=workspace
		tw(impact,{Size=Vector3.new(6,6,6)*brutal,Transparency=1},0.5,Enum.EasingStyle.Quint)
		task.delay(0.6,function() impact:Destroy() end)
		for i=1,brutal do task.delay((i-1)*.08,function()
			local ring=Instance.new("Part"); ring.Size=Vector3.new(.1,1,1); ring.Anchored=true; ring.CanCollide=false
			ring.Material=Enum.Material.Neon; ring.Color=Color3.fromRGB(255,60,60); ring.Transparency=0.3; ring.Shape=Enum.PartType.Cylinder
			ring.CFrame=CFrame.new(vr.Position+Vector3.new(0,1,0))*CFrame.Angles(0,0,math.rad(90)); ring.Parent=workspace
			local rs=brutal*5+i*4; tw(ring,{Size=Vector3.new(.05,rs,rs),Transparency=1},.6,Enum.EasingStyle.Quint)
			task.delay(.7,function() ring:Destroy() end)
		end) end
		for i=1,brutal*3 do
			local d=Instance.new("Part"); d.Size=Vector3.new(.3,.3,.3)*math.random(5,15)/10
			d.Position=vr.Position+Vector3.new(math.random(-1,1),2,math.random(-1,1)); d.Anchored=false; d.CanCollide=false
			d.Material=Enum.Material.Neon; d.Color=i%2==0 and Color3.fromRGB(255,50,50) or Color3.fromRGB(255,200,50); d.Parent=workspace
			d.Velocity=Vector3.new(math.random(-30,30)*brutal,math.random(20,50)*brutal,math.random(-30,30)*brutal)
			tw(d,{Transparency=1},.8+math.random()*.5); task.delay(1.5,function() d:Destroy() end)
		end
		screenShake(brutal*6,brutal*.2); screenFlash(C.red,.4+(3-brutal)*.15,.3+brutal*.15)
		redVignette.Visible=true; tw(redVignette,{ImageTransparency=0.15},.08)
		task.delay(.25,function() tw(redVignette,{ImageTransparency=1},.5); task.delay(.5,function() redVignette.Visible=false end) end)
	end)
end
-- ============ FLOATING TEXT / HEARTS ============
local function spawnText(text, pos, color, size, dur, yDrift, font)
	local lbl=create("TextLabel",{Size=UDim2.new(0,600,0,60),Position=pos,AnchorPoint=Vector2.new(.5,.5),
		BackgroundTransparency=1,Font=font or F.big,Text=text,TextSize=size or 24,
		TextColor3=color or C.darkText,TextStrokeColor3=C.white,TextStrokeTransparency=0.3,ZIndex=50,Parent=gui})
	lbl.TextTransparency=0.3; tw(lbl,{TextTransparency=0},.15)
	task.delay(.15,function() tw(lbl,{Position=pos+UDim2.new(0,0,0,yDrift or -90),TextTransparency=1,TextStrokeTransparency=1},dur or 1.8) end)
	task.delay((dur or 1.8)+.3,function() lbl:Destroy() end)
end
local function spawnHeartBreak(px, py)
	for i=1,12 do
		local sz=math.random(16,30)
		local h=create("TextLabel",{Size=UDim2.new(0,sz,0,sz),Position=UDim2.new(px,0,py,0),AnchorPoint=Vector2.new(.5,.5),
			BackgroundTransparency=1,Font=F.heart,Text="\u{2764}",TextSize=sz,TextColor3=C.heartRed,
			TextStrokeTransparency=1,Rotation=math.random(-45,45),ZIndex=90,Parent=gui})
		tw(h,{Position=UDim2.new(px,math.random(-180,180),py,math.random(-140,60)),TextTransparency=1,
			Rotation=math.random(-220,220),TextSize=math.random(4,8)},math.random(80,140)/100,Enum.EasingStyle.Quint)
		task.delay(1.5,function() h:Destroy() end)
	end
end

-- ============ PROMPT VISIBILITY ============
local function setPromptsVisible(visible)
	for _,obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("ProximityPrompt") and obj.Name=="SambungKataPrompt" then
			obj.Enabled = visible
		end
	end
end

-- ============ STATE ============
local TURN_TIME = 15
local MAX_CROSSES = 5
local currentCrosses = MAX_CROSSES
local isMyTurn = false
local gameActive = false
local wordHistory = {}
local activeNames = {}
local inputActive = false
local currentTurnPlayer = ""
local pendingWord = ""
local currentPrefix = "" -- locked first letter(s) that cannot be erased
local isSubmitting = false

-- ============ MAIN GAME PANEL ============
local gamePanel=create("Frame",{Name="GamePanel",Size=UDim2.new(0,340*UI_SCALE,0,240*UI_SCALE),
	Position=UDim2.new(0.5,0,0.38,0),AnchorPoint=Vector2.new(0.5,0.5),
	BackgroundTransparency=1,Visible=false,ZIndex=10,Parent=gui})

-- Row 1: Current word in bordered box
local wordBox=create("Frame",{Size=UDim2.new(0,180*UI_SCALE,0,32*UI_SCALE),Position=UDim2.new(0.5,0,0,4*UI_SCALE),
	AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(20,20,20),BackgroundTransparency=0.4,ZIndex=11,Parent=gamePanel})
create("UICorner",{CornerRadius=UDim.new(0,8),Parent=wordBox})
create("UIStroke",{Color=C.white,Thickness=2,Transparency=0.3,Parent=wordBox})
local wordBoxLbl=create("TextLabel",{Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),
	BackgroundTransparency=1,Font=F.big,Text="",TextSize=20*UI_SCALE,TextColor3=C.white,
	TextStrokeTransparency=1,ZIndex=12,Parent=wordBox})

-- Row 2: Letter tiles
local tilesFrame=create("Frame",{Size=UDim2.new(1,-30,0,40*UI_SCALE),Position=UDim2.new(0.5,0,0,42*UI_SCALE),
	AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,ZIndex=11,Parent=gamePanel})

local letterTiles={}
local function updateLetterTiles(word)
	for _,t in pairs(letterTiles) do t:Destroy() end; letterTiles={}
	-- Update word box text
	wordBoxLbl.Text=word:upper()
	if word=="" then return end
	local letters={}; for i=1,#word do letters[i]=word:sub(i,i):upper() end
	local maxTile=38*UI_SCALE; local gap=5*UI_SCALE; local containerW=310*UI_SCALE
	local tileSize=math.min(maxTile,math.floor((containerW-(#letters-1)*gap)/#letters))
	local startX=(containerW-(#letters*tileSize+(#letters-1)*gap))/2
	for i,letter in ipairs(letters) do
		local tile=create("Frame",{Size=UDim2.new(0,tileSize,0,tileSize),
			Position=UDim2.new(0,startX+(i-1)*(tileSize+gap),0.5,0),AnchorPoint=Vector2.new(0,0.5),
			BackgroundColor3=C.tileBg,ZIndex=12,Parent=tilesFrame})
		create("UICorner",{CornerRadius=UDim.new(0,8),Parent=tile})
		create("TextLabel",{Size=UDim2.new(1,0,1,0),Position=UDim2.new(0.5,0,0.5,0),AnchorPoint=Vector2.new(0.5,0.5),
			BackgroundTransparency=1,Font=F.letter,Text=letter,TextSize=math.min(22,tileSize-6),
			TextColor3=C.tileText,TextStrokeTransparency=1,ZIndex=13,Parent=tile})
		letterTiles[i]=tile; tile.Size=UDim2.new(0,0,0,0)
		tw(tile,{Size=UDim2.new(0,tileSize,0,tileSize)},0.2+i*0.03,Enum.EasingStyle.Back)
	end
end


-- Row 3: Crosses (circle icons) + Hearts below (centered)
local CROSS_SIZE = 24*UI_SCALE
local CROSS_GAP = 6*UI_SCALE
local crossesFrame=create("Frame",{Size=UDim2.new(0,MAX_CROSSES*(CROSS_SIZE+CROSS_GAP)-CROSS_GAP,0,CROSS_SIZE),
	Position=UDim2.new(0.5,0,0,90*UI_SCALE),AnchorPoint=Vector2.new(0.5,0),
	BackgroundTransparency=1,ZIndex=11,Parent=gamePanel})
local crossIcons={}
for i=1,MAX_CROSSES do
	local circle=create("Frame",{Size=UDim2.new(0,CROSS_SIZE,0,CROSS_SIZE),
		Position=UDim2.new(0,(i-1)*(CROSS_SIZE+CROSS_GAP),0.5,0),AnchorPoint=Vector2.new(0,0.5),
		BackgroundColor3=Color3.fromRGB(50,50,55),ZIndex=12,Parent=crossesFrame})
	create("UICorner",{CornerRadius=UDim.new(1,0),Parent=circle})
	create("UIStroke",{Color=Color3.fromRGB(20,20,25),Thickness=2,Parent=circle})
	local xLbl=create("TextLabel",{Size=UDim2.new(1,0,1,0),Position=UDim2.new(0.5,0,0.5,0),
		AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Font=F.big,
		Text="X",TextSize=14*UI_SCALE,TextColor3=Color3.fromRGB(255,68,68),
		TextStrokeTransparency=1,ZIndex=13,Parent=circle})
	crossIcons[i]={circle=circle, lbl=xLbl}
end
local heartsLbl=create("TextLabel",{Size=UDim2.new(0,200*UI_SCALE,0,20*UI_SCALE),
	Position=UDim2.new(0.5,0,0,118*UI_SCALE),AnchorPoint=Vector2.new(0.5,0),
	BackgroundTransparency=1,Font=F.heart,Text="",TextSize=18*UI_SCALE,
	TextColor3=C.heartRed,TextStrokeTransparency=1,ZIndex=11,Parent=gamePanel})

local function updateCrosses(count)
	currentCrosses=count
	for i=1,MAX_CROSSES do
		if i<=count then
			crossIcons[i].circle.BackgroundColor3=Color3.fromRGB(50,50,55)
			crossIcons[i].lbl.TextColor3=Color3.fromRGB(255,68,68)
			crossIcons[i].lbl.TextTransparency=0
		else
			crossIcons[i].circle.BackgroundColor3=Color3.fromRGB(30,30,35)
			crossIcons[i].lbl.TextColor3=Color3.fromRGB(60,60,60)
			crossIcons[i].lbl.TextTransparency=0.5
		end
	end
end

-- Row 4: Timer
local timerLbl=create("TextLabel",{Size=UDim2.new(0,120*UI_SCALE,0,30*UI_SCALE),Position=UDim2.new(0.5,0,0,142*UI_SCALE),
	AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,Font=F.big,Text="",TextSize=26*UI_SCALE,
	TextColor3=C.green,TextStrokeColor3=Color3.fromRGB(0,0,0),TextStrokeTransparency=0.3,ZIndex=11,Parent=gamePanel})
local timerBarBg=create("Frame",{Size=UDim2.new(0.7,0,0,6*UI_SCALE),Position=UDim2.new(0.5,0,0,174*UI_SCALE),
	AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=Color3.fromRGB(40,40,45),ZIndex=11,Parent=gamePanel})
create("UICorner",{CornerRadius=UDim.new(1,0),Parent=timerBarBg})
create("UIStroke",{Color=Color3.fromRGB(20,20,25),Thickness=1,Parent=timerBarBg})
local timerBar=create("Frame",{Size=UDim2.new(1,0,1,0),BackgroundColor3=C.green,ZIndex=12,Parent=timerBarBg})
create("UICorner",{CornerRadius=UDim.new(1,0),Parent=timerBar})
local chainLbl=create("TextLabel",{Size=UDim2.new(1,-20,0,18*UI_SCALE),Position=UDim2.new(0.5,0,1,-8*UI_SCALE),
	AnchorPoint=Vector2.new(0.5,1),BackgroundTransparency=1,Font=F.chain,Text="",TextSize=11*UI_SCALE,
	TextColor3=C.white,TextStrokeColor3=C.shadow,TextStrokeTransparency=0.4,ZIndex=11,Parent=gamePanel})

-- Player info (dynamic corners — supports 2-4 players)
-- Positions: [1]=top-left, [2]=top-right, [3]=bottom-left, [4]=bottom-right
local playerSlotPositions = {
	{pos=UDim2.new(0.03,0,0.05,0), anchor=Vector2.new(0,0), align=Enum.TextXAlignment.Left},
	{pos=UDim2.new(0.97,0,0.05,0), anchor=Vector2.new(1,0), align=Enum.TextXAlignment.Right},
	{pos=UDim2.new(0.03,0,0.88,0), anchor=Vector2.new(0,1), align=Enum.TextXAlignment.Left},
	{pos=UDim2.new(0.97,0,0.88,0), anchor=Vector2.new(1,1), align=Enum.TextXAlignment.Right},
}
local playerSlots = {} -- {nameLbl, heartsLbl}
for i=1,4 do
	local sp=playerSlotPositions[i]
	local yOff= (i<=2) and 0 or -24*UI_SCALE
	local nameLbl=create("TextLabel",{Size=UDim2.new(0,200*UI_SCALE,0,22*UI_SCALE),
		Position=sp.pos,AnchorPoint=sp.anchor,
		BackgroundTransparency=1,Font=F.name,Text="",TextSize=16*UI_SCALE,
		TextColor3=C.white,TextStrokeColor3=C.shadow,TextStrokeTransparency=0.3,
		TextXAlignment=sp.align,Visible=false,ZIndex=10,Parent=gui})
	local heartsLbl=create("TextLabel",{Size=UDim2.new(0,200*UI_SCALE,0,22*UI_SCALE),
		Position=sp.pos+UDim2.new(0,0,0,(i<=2 and 24 or -24)*UI_SCALE),AnchorPoint=sp.anchor,
		BackgroundTransparency=1,Font=F.heart,Text="",TextSize=18*UI_SCALE,
		TextColor3=C.heartRed,TextStrokeColor3=C.shadow,TextStrokeTransparency=0.4,
		TextXAlignment=sp.align,Visible=false,ZIndex=10,Parent=gui})
	playerSlots[i]={nameLbl=nameLbl,heartsLbl=heartsLbl}
end

-- ============ MOBILE KEYBOARD ============
local mobileKeyboard = nil
local KEY_ROWS = {{"Q","W","E","R","T","Y","U","I","O","P"},{"A","S","D","F","G","H","J","K","L"},{"Z","X","C","V","B","N","M"}}

-- forward declare so MASUK button can reference doSubmit before it is defined below
local doSubmit

local KB_H = 122  -- total keyboard height (3 key rows + masuk row)
local function buildMobileKeyboard()
	if not IS_MOBILE then return end
	local PAD = 2
	local ROW_H = 28
	local GAP = 2

	local kbPanel=create("Frame",{Name="MobileKeyboard",Size=UDim2.new(1,0,0,KB_H),
		Position=UDim2.new(0,0,1,KB_H),AnchorPoint=Vector2.new(0,1),
		BackgroundTransparency=1,ZIndex=25,Visible=false,Parent=gui})

	local keysStartY = PAD

	-- Helper to create a letter key
	local function makeKey(parent, letter, sizeUdim, posUdim)
		local kb=create("TextButton",{Size=sizeUdim,Position=posUdim,
			AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=C.keyBg,Font=F.key,
			Text=letter,TextSize=16,TextColor3=C.darkText,
			AutoButtonColor=false,ZIndex=27,Parent=parent})
		create("UICorner",{CornerRadius=UDim.new(0,4),Parent=kb})
		kb.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then tw(kb,{BackgroundColor3=C.keyPress},0.05) end end)
		kb.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then tw(kb,{BackgroundColor3=C.keyBg},0.12) end end)
		kb.MouseButton1Click:Connect(function()
			if not inputActive then return end
			pendingWord=pendingWord..letter:lower()
			updateLetterTiles(pendingWord)

			if TypingUpdate then TypingUpdate:FireServer(pendingWord) end
		end)
		return kb
	end

	-- Row 1 (QWERTYUIOP): 10 keys, edge to edge
	do
		local rowKeys = KEY_ROWS[1]
		local numKeys = #rowKeys
		local rowFrame=create("Frame",{Size=UDim2.new(1,-4,0,ROW_H),
			Position=UDim2.new(0.5,0,0,keysStartY),
			AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,ZIndex=26,Parent=kbPanel})
		for keyIdx,letter in ipairs(rowKeys) do
			makeKey(rowFrame, letter,
				UDim2.new(1/numKeys,-GAP,1,-2),
				UDim2.new((keyIdx-1)/numKeys,GAP/2,0.5,0))
		end
	end

	-- Row 2 (ASDFGHJKL): 9 keys, slightly inset
	do
		local rowKeys = KEY_ROWS[2]
		local numKeys = #rowKeys
		local insetPx = 16
		local rowFrame=create("Frame",{Size=UDim2.new(1,-4,0,ROW_H),
			Position=UDim2.new(0.5,0,0,keysStartY+(ROW_H+GAP)),
			AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,ZIndex=26,Parent=kbPanel})
		for keyIdx,letter in ipairs(rowKeys) do
			makeKey(rowFrame, letter,
				UDim2.new(1/numKeys,-GAP-(insetPx*2)/numKeys,1,-2),
				UDim2.new((keyIdx-1)/numKeys,insetPx+GAP/2,0.5,0))
		end
	end

	-- Row 3 (ZXCVBNM + backspace): letters centered, backspace on right
	do
		local rowKeys = KEY_ROWS[3]
		local numKeys = #rowKeys
		local rowFrame=create("Frame",{Size=UDim2.new(1,-4,0,ROW_H),
			Position=UDim2.new(0.5,0,0,keysStartY+2*(ROW_H+GAP)),
			AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,ZIndex=26,Parent=kbPanel})
		local bsFrac = 0.13  -- backspace width fraction
		local letterArea = 1 - bsFrac - 0.01  -- leave tiny gap before backspace
		local insetPx = 20
		local keyW = letterArea / numKeys
		for keyIdx,letter in ipairs(rowKeys) do
			makeKey(rowFrame, letter,
				UDim2.new(keyW,-GAP-(insetPx*2)/numKeys,1,-2),
				UDim2.new((keyIdx-1)*keyW,insetPx+GAP/2,0.5,0))
		end
		-- Backspace button (red)
		local bsBtn=create("TextButton",{
			Size=UDim2.new(bsFrac,-GAP,1,-2),
			Position=UDim2.new(1-bsFrac,-GAP/2,0.5,0),
			AnchorPoint=Vector2.new(0,0.5),BackgroundColor3=Color3.fromRGB(210,55,55),Font=F.key,
			Text="\u{232B}",TextSize=18,TextColor3=C.white,
			AutoButtonColor=false,ZIndex=27,Parent=rowFrame})
		create("UICorner",{CornerRadius=UDim.new(0,4),Parent=bsBtn})
		bsBtn.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then tw(bsBtn,{BackgroundColor3=Color3.fromRGB(170,40,40)},0.05) end end)
		bsBtn.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then tw(bsBtn,{BackgroundColor3=Color3.fromRGB(210,55,55)},0.12) end end)
		bsBtn.MouseButton1Click:Connect(function()
			if not inputActive or #pendingWord<=#currentPrefix then return end
			pendingWord=pendingWord:sub(1,-2)
			updateLetterTiles(pendingWord)

			if TypingUpdate then TypingUpdate:FireServer(pendingWord) end
		end)
	end

	-- Row 4: Masuk button (full width, green)
	local row4Y = keysStartY + 3*(ROW_H+GAP)
	local masukBtn=create("TextButton",{Size=UDim2.new(1,-8,0,ROW_H),
		Position=UDim2.new(0.5,0,0,row4Y),AnchorPoint=Vector2.new(0.5,0),
		BackgroundColor3=C.green,Font=F.status,
		Text="Masuk",TextSize=16,TextColor3=C.white,AutoButtonColor=false,ZIndex=27,Parent=kbPanel})
	create("UICorner",{CornerRadius=UDim.new(0,4),Parent=masukBtn})
	masukBtn.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then tw(masukBtn,{BackgroundColor3=Color3.fromRGB(40,160,60)},0.05) end end)
	masukBtn.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.Touch then tw(masukBtn,{BackgroundColor3=C.green},0.12) end end)
	masukBtn.MouseButton1Click:Connect(function()
		if inputActive and #pendingWord>0 and doSubmit then doSubmit() end
	end)

	mobileKeyboard=kbPanel
end


local function showMobileKeyboard()
	if not mobileKeyboard then return end
	mobileKeyboard.Visible=true; mobileKeyboard.Position=UDim2.new(0,0,1,KB_H)
	tw(mobileKeyboard,{Position=UDim2.new(0,0,1,0)},0.25,Enum.EasingStyle.Quint)
end
local function hideMobileKeyboard()
	if not mobileKeyboard then return end
	tw(mobileKeyboard,{Position=UDim2.new(0,0,1,KB_H)},0.2,Enum.EasingStyle.Quad)
	task.delay(0.22,function() mobileKeyboard.Visible=false end)
end
buildMobileKeyboard()

-- ============ SUBMIT / INPUT ============
doSubmit = function()
	if isSubmitting then return end
	local w = pendingWord:gsub("%s+","")
	if w=="" or #w<=#currentPrefix or not inputActive then return end
	isSubmitting = true
	screenFlash(C.white, 0.85, 0.2)
	SendWord:FireServer(w)
	pendingWord = currentPrefix
	updateLetterTiles(pendingWord)
	task.delay(0.5, function() isSubmitting = false end)
end

local function setInputActive(active)
	inputActive = active; isMyTurn = active
	if active then
		pendingWord = currentPrefix; isSubmitting = false
		updateLetterTiles(pendingWord)

		if IS_MOBILE then showMobileKeyboard() end
	else
		if IS_MOBILE then hideMobileKeyboard() end
		pendingWord = ""

	end
end

-- ============ PC KEYBOARD INPUT (physical keys, no UI) ============
if not IS_MOBILE then
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not inputActive then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter then
			if #pendingWord > 0 then doSubmit() end
		elseif kc == Enum.KeyCode.Backspace then
			if #pendingWord > #currentPrefix then
				pendingWord = pendingWord:sub(1, #pendingWord-1)
				updateLetterTiles(pendingWord)
				if TypingUpdate then TypingUpdate:FireServer(pendingWord) end
			end
		else
			local name = kc.Name
			if #name == 1 and name:match("^%u$") then
				pendingWord = pendingWord .. name:lower()
				updateLetterTiles(pendingWord)
				if TypingUpdate then TypingUpdate:FireServer(pendingWord) end
			end
		end
	end)
end

-- ============ UI HELPERS ============
local function heartsStr(count, max)
	max=max or 3; local s=""
	for i=1,max do s=s..(i<=count and "\u{2764}" or "\u{25CB}"); if i<max then s=s.."  " end end
	return s
end
local function showGameUI()
	gameActive=true; gamePanel.Visible=true
	for i,slot in ipairs(playerSlots) do
		if i <= #activeNames then
			slot.nameLbl.Visible=true; slot.heartsLbl.Visible=true
			slot.nameLbl.TextTransparency=1; slot.heartsLbl.TextTransparency=1
			tw(slot.nameLbl,{TextTransparency=0},0.5)
			tw(slot.heartsLbl,{TextTransparency=0},0.6)
		end
	end
end
local function hideGameUI()
	gameActive=false; inputActive=false; pendingWord=""
	gamePanel.Visible=false
	if IS_MOBILE then hideMobileKeyboard() end
	for _,slot in ipairs(playerSlots) do
		slot.nameLbl.Visible=false; slot.heartsLbl.Visible=false
	end
	redVignette.Visible=false; redVignette.ImageTransparency=1
end
local function updatePlayers(hearts, names)
	if names then activeNames=names end
	for i,slot in ipairs(playerSlots) do
		local n=activeNames[i]
		if n then
			slot.nameLbl.Text=n
			if hearts and hearts[n] then slot.heartsLbl.Text=heartsStr(hearts[n]) else slot.heartsLbl.Text="" end
		else
			slot.nameLbl.Text=""; slot.heartsLbl.Text=""
			slot.nameLbl.Visible=false; slot.heartsLbl.Visible=false
		end
	end
	if hearts then
		local sf=currentTurnPlayer~="" and currentTurnPlayer or player.Name
		heartsLbl.Text=hearts[sf] and heartsStr(hearts[sf]) or ""
	end
end
local function highlightTurn(pName)
	local myTurn=pName==player.Name
	for i,slot in ipairs(playerSlots) do
		local isThis=activeNames[i]==pName
		tw(slot.nameLbl,{TextColor3=isThis and C.white or C.lightText,TextSize=(isThis and 18 or 14)*UI_SCALE},0.3)
		tw(slot.heartsLbl,{TextTransparency=isThis and 0 or 0.5},0.3)
	end
end
local function updateChain()
	local d={}; for i=math.max(1,#wordHistory-5),#wordHistory do d[#d+1]=wordHistory[i]:upper() end
	chainLbl.Text=table.concat(d,"  \u{2023}  ")
end
local function resetAll()
	hideGameUI(); wordHistory={}; activeNames={}; currentTurnPlayer=""
	timerLbl.Text=""; chainLbl.Text=""
	heartsLbl.Text=""; pendingWord=""; currentPrefix=""
	wordBoxLbl.Text=""
	updateCrosses(MAX_CROSSES)
	for _,slot in ipairs(playerSlots) do
		slot.nameLbl.Text=""; slot.heartsLbl.Text=""
		slot.nameLbl.Visible=false; slot.heartsLbl.Visible=false
	end
	updateLetterTiles("")
end
-- ============ WAITING SCREEN ============
local waitOverlay=create("Frame",{Size=UDim2.new(1,0,1,0),BackgroundColor3=C.overlay,BackgroundTransparency=1,Visible=false,ZIndex=30,Parent=gui})
local waitPanel=create("Frame",{Size=UDim2.new(0,340*UI_SCALE,0,240*UI_SCALE),Position=UDim2.new(0.5,0,0.42,0),
	AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=Color3.fromRGB(20,20,25),BackgroundTransparency=0.2,
	Visible=false,ZIndex=31,Parent=gui})
create("UICorner",{CornerRadius=UDim.new(0,16),Parent=waitPanel})
create("UIStroke",{Color=Color3.fromRGB(80,80,100),Thickness=2,Transparency=0.5,Parent=waitPanel})

-- Logo / Title
local waitTitle=create("TextLabel",{Size=UDim2.new(1,-20,0,50),Position=UDim2.new(0.5,0,0,20),
	AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,Font=F.title,
	Text="SAMBUNG KATA",TextSize=36*UI_SCALE,TextColor3=C.white,
	TextStrokeColor3=Color3.fromRGB(0,0,0),TextStrokeTransparency=0.3,ZIndex=32,Parent=waitPanel})

-- Decorative line under title
local waitLine=create("Frame",{Size=UDim2.new(0,0,0,3),Position=UDim2.new(0.5,0,0,78),
	AnchorPoint=Vector2.new(0.5,0),BackgroundColor3=C.green,Visible=false,ZIndex=32,Parent=waitPanel})
create("UICorner",{CornerRadius=UDim.new(1,0),Parent=waitLine})

-- Status text (bigger, bolder)
local waitLbl=create("TextLabel",{Size=UDim2.new(1,-30,0,30),Position=UDim2.new(0.5,0,0,100),
	AnchorPoint=Vector2.new(0.5,0),BackgroundTransparency=1,Font=F.name,Text="",
	TextSize=20*UI_SCALE,TextColor3=Color3.fromRGB(220,220,230),
	TextStrokeColor3=C.shadow,TextStrokeTransparency=0.3,ZIndex=32,Parent=waitPanel})

-- Loading dots (bigger)
local waitDots={}
for i=1,3 do
	waitDots[i]=create("Frame",{Size=UDim2.new(0,10,0,10),Position=UDim2.new(0.5,-30+(i-1)*30,0,155),
		AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=C.green,Visible=false,ZIndex=32,Parent=waitPanel})
	create("UICorner",{CornerRadius=UDim.new(1,0),Parent=waitDots[i]})
end

-- Subtle hint at bottom
local waitHint=create("TextLabel",{Size=UDim2.new(1,-30,0,20),Position=UDim2.new(0.5,0,1,-20),
	AnchorPoint=Vector2.new(0.5,1),BackgroundTransparency=1,Font=F.chain,
	Text="Siapkan kata terbaikmu!",TextSize=12*UI_SCALE,
	TextColor3=Color3.fromRGB(140,140,160),TextStrokeTransparency=1,ZIndex=32,Parent=waitPanel})

local waitAnimRunning=false
local function showWait(text)
	waitOverlay.Visible=true; waitOverlay.BackgroundTransparency=1; tw(waitOverlay,{BackgroundTransparency=0.5},0.6)
	waitPanel.Visible=true; waitPanel.Size=UDim2.new(0,300*UI_SCALE,0,210*UI_SCALE)
	tw(waitPanel,{Size=UDim2.new(0,340*UI_SCALE,0,240*UI_SCALE)},0.4,Enum.EasingStyle.Back)
	waitTitle.TextTransparency=1; tw(waitTitle,{TextTransparency=0},0.5,Enum.EasingStyle.Quint)
	waitLine.Visible=true; waitLine.Size=UDim2.new(0,0,0,3); tw(waitLine,{Size=UDim2.new(0,200,0,3)},0.8,Enum.EasingStyle.Quint)
	waitLbl.TextTransparency=1; task.delay(0.3,function() tw(waitLbl,{TextTransparency=0},0.4) end)
	waitHint.TextTransparency=1; task.delay(0.6,function() tw(waitHint,{TextTransparency=0},0.5) end)
	for _,d in pairs(waitDots) do d.Visible=true; d.BackgroundTransparency=0 end
	waitAnimRunning=true; waitLbl.Text=text or "Menunggu lawan"
	task.spawn(function()
		while waitAnimRunning do
			for i=1,3 do
				if not waitAnimRunning then return end
				tw(waitDots[i],{Size=UDim2.new(0,14,0,14),Position=UDim2.new(0.5,-30+(i-1)*30,0,148),BackgroundColor3=C.green},0.2)
				task.wait(0.12)
				tw(waitDots[i],{Size=UDim2.new(0,10,0,10),Position=UDim2.new(0.5,-30+(i-1)*30,0,155),BackgroundColor3=Color3.fromRGB(100,100,120)},0.3,Enum.EasingStyle.Bounce)
			end
			task.wait(0.6)
		end
	end)
end
local function hideWait()
	waitAnimRunning=false
	tw(waitPanel,{Size=UDim2.new(0,300*UI_SCALE,0,210*UI_SCALE)},0.2,Enum.EasingStyle.Quad)
	tw(waitOverlay,{BackgroundTransparency=1},0.3); tw(waitTitle,{TextTransparency=1},0.2)
	tw(waitLbl,{TextTransparency=1},0.2); tw(waitLine,{Size=UDim2.new(0,0,0,3)},0.3)
	tw(waitHint,{TextTransparency=1},0.2)
	for _,d in pairs(waitDots) do tw(d,{BackgroundTransparency=1},0.2) end
	task.delay(0.35,function()
		waitOverlay.Visible=false; waitPanel.Visible=false; waitLine.Visible=false
		for _,d in pairs(waitDots) do d.Visible=false; d.BackgroundTransparency=0 end
	end)
end
-- ============ GAME EVENTS ============
GameUpdate.OnClientEvent:Connect(function(msg, data)
	if msg=="waitingOpponent" then hideGameUI(); setPromptsVisible(false); showWait("Menunggu lawan...")
	elseif msg=="spectating" then
		hideGameUI(); setPromptsVisible(false); showWait(data.queuePos and data.queuePos>0 and ("Menonton  \u{2022}  antrian #"..data.queuePos) or "Menonton")
	elseif msg=="countdown" then
		setPromptsVisible(false); hideWait(); spawnText(tostring(data.seconds),UDim2.new(0.5,0,0.4,0),C.white,100,1.2,-60,F.title); screenFlash(C.white,0.85,0.3)
	elseif msg=="gameStart" then
		setPromptsVisible(false); hideWait(); resetAll()
		local initHearts={}
		for _,n in ipairs(data.players) do initHearts[n]=data.maxHearts or 3 end
		activeNames=data.players
		MAX_CROSSES=data.maxCrosses or 5
		updateCrosses(MAX_CROSSES)
		showGameUI(); wordHistory={}
		updatePlayers(initHearts, data.players)
		spawnText("MULAI!",UDim2.new(0.5,0,0.4,0),C.white,52,2.5,-70,F.title); screenFlash(C.white,0.7,0.7)
	elseif msg=="turn" then
		currentTurnPlayer=data.playerName; local myTurn=data.playerName==player.Name
		if data.lastLetter~="" then
			currentPrefix=data.lastLetter:lower()
		else currentPrefix="" end
		updateCrosses(data.crosses or MAX_CROSSES)
		startCameraZoom(data.playerName); timerBar.Size=UDim2.new(1,0,1,0); timerBar.BackgroundColor3=C.green
		if myTurn then
			setInputActive(true)
		else
			updateLetterTiles(""); setInputActive(false)
		end
		updatePlayers(data.hearts,data.activeNames); highlightTurn(data.playerName)
	elseif msg=="crossLost" then
		updateCrosses(data.crossesLeft)
		spawnText(data.reason or "",UDim2.new(0.5,0,0.55,0),C.red,14,2.0,-60,F.status)
		screenFlash(C.red,0.92,0.15)
		for _,tile in pairs(letterTiles) do tw(tile,{BackgroundColor3=Color3.fromRGB(255,200,200)},0.1); task.delay(0.4,function() tw(tile,{BackgroundColor3=C.tileBg},0.3) end) end
		-- Clear input so player can retype (stays on their turn), keep prefix
		pendingWord=currentPrefix
		updateLetterTiles(pendingWord)

	elseif msg=="wordAccepted" then
		wordHistory[#wordHistory+1]=data.word; updateChain(); updateLetterTiles(data.word)
		spawnText(data.word:upper(),UDim2.new(0.5,0,0.65,0),C.green,28,1.5,-120,F.big); screenFlash(C.green,0.9,0.2)
		for _,tile in pairs(letterTiles) do tw(tile,{BackgroundColor3=Color3.fromRGB(200,255,200)},0.1); task.delay(0.3,function() tw(tile,{BackgroundColor3=C.tileBg},0.3) end) end
	elseif msg=="heartLost" then
		local slotIdx=1
		for i,n in ipairs(activeNames) do if n==data.playerName then slotIdx=i; break end end
		local sides={0.12,0.88,0.12,0.88}
		local side=sides[slotIdx] or 0.5
		spawnText("-1 \u{2764}",UDim2.new(side,0,0.1,0),C.red,32,1.5,-70,F.big)
		spawnText(data.reason or "",UDim2.new(0.5,0,0.55,0),C.red,14,2.2,-60,F.status)
		if playerSlots[slotIdx] then playerSlots[slotIdx].heartsLbl.Text=heartsStr(data.heartsLeft) end
		if data.playerName==currentTurnPlayer then heartsLbl.Text=heartsStr(data.heartsLeft) end
		spawnHeartBreak(side,0.07); screenFlash(C.red,0.7,0.4)
		if data.attackerName then startCameraZoom(data.playerName); playPunchAnimation(data.attackerName,data.playerName,data.heartsLeft) end
	elseif msg=="eliminated" or msg=="winner" then
		local winnerName=msg=="winner" and data.playerName or nil
		local loserName=msg=="eliminated" and data.playerName or nil
		local iWon=winnerName==player.Name; local iLost=loserName==player.Name
		setInputActive(false)
		if iWon then
			startCameraZoom(winnerName); spawnText("MENANG!",UDim2.new(0.5,0,0.32,0),C.gold,52,4.5,-30,F.title); screenFlash(C.gold,0.4,1.2)
			task.spawn(function()
				for i=1,40 do
					local px=math.random(5,95)/100
					local cf=create("Frame",{Size=UDim2.new(0,math.random(4,10),0,math.random(8,16)),Position=UDim2.new(px,0,-0.02,0),AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=i%3==0 and C.gold or (i%3==1 and C.white or C.green),Rotation=math.random(0,360),ZIndex=55,Parent=gui})
					create("UICorner",{CornerRadius=UDim.new(0,3),Parent=cf})
					local drift=math.random(-40,40); local fd=math.random(25,45)/10
					tw(cf,{Position=UDim2.new(px+drift/1000,drift,1.1,0),Rotation=math.random(-720,720),BackgroundTransparency=0.3},fd,Enum.EasingStyle.Linear)
					task.delay(fd+0.5,function() cf:Destroy() end); task.wait(0.05)
				end
			end)
			task.delay(0.5,function() screenFlash(C.white,0.7,0.8) end)
		elseif iLost then
			startCameraZoom(loserName); spawnText("KALAH!",UDim2.new(0.5,0,0.32,0),C.red,52,4.5,-30,F.title); screenFlash(C.red,0.3,1.0)
			local lc=Players:FindFirstChild(loserName); if lc and lc.Character then local h=lc.Character:FindFirstChild("Humanoid"); if h then h.Sit=false end end
			for i,n in ipairs(activeNames) do
				if n==loserName and playerSlots[i] then playerSlots[i].heartsLbl.Text=heartsStr(0); break end
			end
		end
		task.delay(5,function() stopCameraZoom(); resetAll(); setPromptsVisible(true) end)
	elseif msg=="noWinner" then
		spawnText("SERI",UDim2.new(0.5,0,0.35,0),C.medText,44,3.5,-50,F.title); screenFlash(C.white,0.7,0.6)
		setInputActive(false); task.delay(3.5,function() stopCameraZoom(); resetAll(); setPromptsVisible(true) end)
	elseif msg=="gameEnded" then
		spawnText(data.reason or "GAME OVER",UDim2.new(0.5,0,0.35,0),C.red,32,3,-50,F.title); screenFlash(C.red,0.7,0.6)
		setInputActive(false); task.delay(2.5,function() stopCameraZoom(); resetAll(); setPromptsVisible(true) end)
	elseif msg=="leftSeat" then stopCameraZoom(); hideWait(); resetAll(); setPromptsVisible(true)
	elseif msg=="error" then
		spawnText(data.message,UDim2.new(0.5,0,0.6,0),C.red,16,2.5,-50,F.status); screenFlash(C.red,0.9,0.2)
		for _,tile in pairs(letterTiles) do tw(tile,{BackgroundColor3=Color3.fromRGB(255,200,200)},0.1); task.delay(0.4,function() tw(tile,{BackgroundColor3=C.tileBg},0.3) end) end
	end
end)
-- ============ TIMER ============
TimerUpdate.OnClientEvent:Connect(function(sec)
	local secs=math.floor(sec)
	local frac=math.floor((sec-secs)*10)
	timerLbl.Text=string.format("%d.%d", secs, frac)
	tw(timerBar,{Size=UDim2.new(math.clamp(sec/TURN_TIME,0,1),0,1,0)},0.8,Enum.EasingStyle.Linear)
	if sec<=5 then
		tw(timerLbl,{TextColor3=C.red},0.15); tw(timerBar,{BackgroundColor3=C.red},0.15)
		if isMyTurn then
			redVignette.Visible=true
			local intensity=sec<=2 and 0.25 or (sec<=3 and 0.4 or 0.55)
			tw(redVignette,{ImageTransparency=intensity},0.15)
			task.delay(0.4,function() tw(redVignette,{ImageTransparency=intensity+0.15},0.4) end)
			if sec<=3 then
				screenFlash(C.red,0.92,0.15)
				tw(timerLbl,{TextSize=32*UI_SCALE},0.06); task.delay(0.06,function() tw(timerLbl,{TextSize=26*UI_SCALE},0.1) end)
				screenShake(3,0.15)
			end
		end
	else
		tw(timerLbl,{TextColor3=C.green},0.15); tw(timerBar,{BackgroundColor3=C.green},0.15)
		if redVignette.Visible then tw(redVignette,{ImageTransparency=1},0.3); task.delay(0.3,function() redVignette.Visible=false end) end
	end
end)

-- ============ OPPONENT TYPING ============
if TypingUpdate then TypingUpdate.OnClientEvent:Connect(function(playerName, text)
	if not gameActive then return end
	if playerName~=player.Name then updateLetterTiles(text) end
end) end



-- ============ CLEANUP ============
player.CharacterAdded:Connect(function() setInputActive(false) end)

print("Sambung Kata UI loaded! PC=keyboard, Mobile=custom on-screen keyboard")
