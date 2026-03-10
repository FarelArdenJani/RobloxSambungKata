-- Word preview bar (mobile only — PC uses letter tiles as feedback)
local wordPreviewBar = nil
local wordPreviewLbl = nil
if IS_MOBILE then
	wordPreviewBar=create("Frame",{
		Size=UDim2.new(1,0,0,42),Position=UDim2.new(0.5,0,1,-10),AnchorPoint=Vector2.new(0.5,0),
		BackgroundColor3=C.previewBg,ZIndex=12,Visible=false,Parent=gamePanel})
	create("UICorner",{CornerRadius=UDim.new(0,10),Parent=wordPreviewBar})
	wordPreviewLbl=create("TextLabel",{Size=UDim2.new(1,-10,1,0),Position=UDim2.new(0.5,0,0.5,0),
		AnchorPoint=Vector2.new(0.5,0.5),BackgroundTransparency=1,Font=F.typing,Text="",TextSize=22,
		TextColor3=C.darkText,TextXAlignment=Enum.TextXAlignment.Center,TextStrokeTransparency=1,ZIndex=13,Parent=wordPreviewBar})
end
