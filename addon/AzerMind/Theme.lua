-- Shared visual vocabulary. Components must use semantic colors, not RGB literals.
AzerMindTheme = {}
local T = AzerMindTheme
T.grimoire = true
T.artRoot = "Interface\\AddOns\\AzerMind\\Art\\Grimoire\\"
T.skinSpecs = {
	["frame-window"]={width=1024,height=1024,sliceX=192,sliceY=192,edgePrefix="frame-window"},
	["frame-panel"]={width=1024,height=1024,sliceX=192,sliceY=192,edgePrefix="frame-window"},
	["frame-popup"]={width=1024,height=1024,sliceX=192,sliceY=192,edgePrefix="frame-window"},
}
for _,name in ipairs({"button-paper","button-primary","button-secondary","conversation-selection","frame-card","frame-input"}) do
	local prefix=name=="conversation-selection" and "button-primary" or (name=="frame-input" and "frame-card" or name)
	T.skinSpecs[name]={width=512,height=256,sliceX=64,sliceY=64,edgePrefix=prefix}
end
-- Repeat at native size, rather than stretching a whole background on resize.
function T.Material(frame, name, inset, texture)
	inset = inset or 4
	local fill = texture or frame.grimoireMaterial
	if not fill then
		fill = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
		fill:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
		fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
		frame.grimoireMaterial = fill
	end
	fill:SetTexture(T.artRoot .. name .. ".tga", "REPEAT", "REPEAT")
	fill:SetVertexColor(1, 1, 1, 1)
	fill:SetHorizTile(true); fill:SetVertTile(true)
	local function Resize()
		fill:SetTexCoord(0, math.max(1, frame:GetWidth()-inset*2)/256, 0, math.max(1, frame:GetHeight()-inset*2)/256)
	end
	Resize()
	if not fill.grimoireResizeHook then
		frame:HookScript("OnSizeChanged", Resize); fill.grimoireResizeHook = true
	end
	fill.grimoireAsset = name
	return fill
end
function T.PaperFont(region, muted)
	region:SetTextColor(muted and 0.40 or 0.22, muted and 0.32 or 0.145, muted and 0.25 or 0.106)
	region:SetShadowColor(0, 0, 0, 0)
end
function T.PaperText(text)
	local ink = {ffd3b66f="ff765013", ffffd36a="ff765013", ff8fc9df="ff28566c", ff1eff00="ff246021", ff00ccff="ff176078", ffe6cc80="ff765013", ffffffff="ff38251b", ff9d9d9d="ff5b5146", ffff8000="ff934300"}
	return (text:gsub("|c(%x%x%x%x%x%x%x%x)", function(color) return "|c" .. (ink[color:lower()] or color) end))
end
T.colors = {
	window = {0.055, 0.049, 0.039, 1},
	panel = {0.085, 0.075, 0.058, 1},
	field = {0.12, 0.105, 0.080, 1},
	selected = {0.29, 0.07, 0.08, 1},
	border = {0.48, 0.35, 0.19, 1},
	accent = {0.94, 0.80, 0.52, 1},
	gold = {0.90, 0.74, 0.39, 1},
	text = {0.91, 0.87, 0.78, 1},
	muted = {0.65, 0.61, 0.53, 1},
	hover = {0.94, 0.80, 0.52, 0.12},
}
T.spacing = {xs=4, sm=8, md=12, lg=20, xl=28}
T.fonts = {title="GameFontNormalLarge", heading="GameFontNormal", body="GameFontHighlightSmall"}
T.typography = {
	timestamp={file="Fonts\\ARIALN.TTF",size=11},
	senderName={file="Fonts\\FRIZQT__.TTF",size=20},
	toolbarLabel = {file="Fonts\\FRIZQT__.TTF", size=14},
	title = {file="Fonts\\FRIZQT__.TTF", size=18},
	heading = {file="Fonts\\FRIZQT__.TTF", size=15},
	body = {file="Fonts\\ARIALN.TTF", size=14},
	label = {file="Fonts\\FRIZQT__.TTF", size=13},
	conversation = {file="Fonts\\FRIZQT__.TTF", size=14},
	paperBody = {file="Fonts\\FRIZQT__.TTF", size=16},
	paperHeading = {file="Fonts\\FRIZQT__.TTF", size=18},
	brand = {file="Fonts\\FRIZQT__.TTF", size=24},
	mainLabel = {file="Fonts\\FRIZQT__.TTF", size=16},
	mainTitle = {file="Fonts\\FRIZQT__.TTF", size=20},
}
function T.Type(region, role)
	local spec = T.typography[role] or T.typography.body
	region:SetFont(spec.file, spec.size, "")
	if region.SetShadowColor then region:SetShadowColor(0, 0, 0, 0.75); region:SetShadowOffset(1, -1) end
	if region.SetSpacing and (role == "body" or role=="paperBody") then region:SetSpacing(3) end
end
T.roles = {
	user = {label="You", color={0.40,0.28,0.12}, bg={0.17,0.15,0.11,0.65}},
	assistant = {label="AI", color={0.40,0.12,0.20}, bg={0.06,0.15,0.15,0.70}},
	system = {label="System", color={0.38,0.32,0.25}, bg={0.12,0.11,0.09,0.65}},
}
-- Nine independent regions preserve corners while the center and edges expand.
function T.Frame(frame, name, corner, native)
	corner, native = corner or 8, native or 128
	local spec=T.skinSpecs[name]
	local nativeWidth,nativeHeight=spec and spec.width or native,spec and spec.height or native
	local sliceX,sliceY=spec and spec.sliceX or 16,spec and spec.sliceY or 16
	local skin = frame.grimoireFrame
	if not skin then
		skin = {parts={}}; frame.grimoireFrame = skin
		for i=1,9 do skin.parts[i]=frame:CreateTexture(nil, i==5 and "BACKGROUND" or "OVERLAY", nil, 1) end
		local function Layout()
			local c = math.min(skin.corner, math.max(1, frame:GetWidth()/2-1), math.max(1, frame:GetHeight()/2-1))
			local p=skin.parts
			for _,texture in ipairs(p) do texture:ClearAllPoints() end
			for _,v in ipairs({{1,"TOPLEFT"},{3,"TOPRIGHT"},{7,"BOTTOMLEFT"},{9,"BOTTOMRIGHT"}}) do p[v[1]]:SetPoint(v[2],frame,v[2]); p[v[1]]:SetSize(c,c) end
			for _,v in ipairs({{2,"TOPLEFT","TOPRIGHT",1,"TOPRIGHT","TOPLEFT",3},{8,"BOTTOMLEFT","BOTTOMRIGHT",7,"BOTTOMRIGHT","BOTTOMLEFT",9}}) do
				local t=p[v[1]]; t:SetPoint(v[2],p[v[4]],v[3]); t:SetPoint(v[5],p[v[7]],v[6]); t:SetHeight(c)
			end
			p[4]:SetPoint("TOPLEFT",p[1],"BOTTOMLEFT"); p[4]:SetPoint("BOTTOMLEFT",p[7],"TOPLEFT"); p[4]:SetWidth(c)
			p[6]:SetPoint("TOPRIGHT",p[3],"BOTTOMRIGHT"); p[6]:SetPoint("BOTTOMRIGHT",p[9],"TOPRIGHT"); p[6]:SetWidth(c)
			p[5]:SetPoint("TOPLEFT",p[1],"BOTTOMRIGHT"); p[5]:SetPoint("BOTTOMRIGHT",p[9],"TOPLEFT")
			local s=skin.spec
			if s and s.edgePrefix then
				for _,edge in ipairs({{2,"top"},{8,"bottom"},{4,"left"},{6,"right"}}) do
					local t=p[edge[1]]; t:SetTexture(T.artRoot..s.edgePrefix.."-"..edge[2]..".tga","REPEAT","REPEAT")
					if edge[1]==2 or edge[1]==8 then
						t:SetTexCoord(0,math.max(1,frame:GetWidth()-2*c)/(256*c/s.sliceY),0,s.sliceY/256)
					else
						t:SetTexCoord(0,s.sliceX/256,0,math.max(1,frame:GetHeight()-2*c)/(256*c/s.sliceX))
					end
				end
			end
			skin.renderedCorner = c
		end
		skin.layout=Layout; frame:HookScript("OnSizeChanged", Layout)
	end
	skin.name,skin.corner,skin.native,skin.nativeHeight=name,corner,nativeWidth,nativeHeight
	skin.spec=spec
	local uvX={0,sliceX/nativeWidth,1-sliceX/nativeWidth,1}
	local uvY={0,sliceY/nativeHeight,1-sliceY/nativeHeight,1}
	for row=0,2 do for col=0,2 do
		local texture=skin.parts[row*3+col+1]
		texture:SetTexture(T.artRoot..name..".tga")
		texture:SetTexCoord(uvX[col+1],uvX[col+2],uvY[row+1],uvY[row+2])
	end end
	skin.layout()
	return skin
end
function T.Panel(frame, name, corner)
	if frame.SetBackdrop then frame:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground",insets={left=4,right=4,top=4,bottom=4}}) end
	if frame.SetBackdropColor then frame:SetBackdropColor(0.055,0.035,0.02,1) end
	return T.Frame(frame,name or "frame-panel",corner)
end
function T.ButtonVisual(button)
	local enabled=button:IsEnabled()
	local selected=button.selectedState or button.primary
	local skin=T.Frame(button,button.paper and "button-paper" or (selected and not button.subdued and "button-primary" or "button-secondary"),8)
	local value=not enabled and 0.52 or (button.grimoirePressed and 0.72 or 1)
	for _,part in ipairs(skin.parts) do part:SetVertexColor(value,value,value,1) end
	T.Color(button.caption,"SetTextColor",not enabled and "muted" or (selected and "accent" or "text"))
	if button.paper then T.PaperFont(button.caption,not enabled) end
	button.grimoireState=not enabled and "disabled" or (button.grimoirePressed and "pressed" or (button.grimoireHovered and "hover" or "normal"))
end
function T.Focus(frame, focused)
	frame.grimoireFocused=focused
	if frame.grimoireFrame then
		for _,part in ipairs(frame.grimoireFrame.parts) do part:SetVertexColor(focused and 1 or 0.95,focused and 1 or 0.95,focused and 1 or 0.95,1) end
	end
end
function T.ActionIcon(button, name)
	if not button.actionArt then
		button.actionArt=button:CreateTexture(nil,"ARTWORK")
		button.actionArt:SetSize(24,24); button.actionArt:SetPoint("LEFT",button,"LEFT",10,0)
		button.caption:ClearAllPoints(); button.caption:SetPoint("LEFT",button,"LEFT",40,0)
		button.caption:SetWidth(button:GetWidth()-50); button.caption:SetWordWrap(false)
	end
	button.actionArt:SetSize(name=="connect" and 32 or 24,name=="connect" and 32 or 24)
	button.caption:ClearAllPoints(); button.caption:SetPoint("LEFT",button,"LEFT",name=="connect" and 46 or 40,0)
	button.caption:SetWidth(button:GetWidth()-(name=="connect" and 54 or 50))
	button.actionArt:SetTexture(T.artRoot.."icon-"..name..".tga")
	button.actionArt:SetAlpha(name=="connect" and 0 or 1)
	if name=="connect" then
	 local crystal=T.ConnectCrystal(button);crystal:Show()
	 local textWidth=math.min(button:GetWidth()-54,button.caption:GetStringWidth())
	 local left=(button:GetWidth()-24-8-textWidth)/2
	 crystal:ClearAllPoints();crystal:SetPoint("LEFT",button,"LEFT",left,0)
	 button.caption:ClearAllPoints();button.caption:SetPoint("LEFT",button,"LEFT",left+32,0)
	 button.caption:SetWidth(textWidth);button.caption:SetJustifyH("LEFT")
	elseif button.connectCrystal then button.connectCrystal:Hide() end
	T.ButtonVisual(button)
end
function T.Scrollbar(scroll)
	local name=scroll:GetName()
	local bar=scroll.ScrollBar or (name and _G[name.."ScrollBar"])
	if not bar or bar.grimoireSkinned then return end
	bar.grimoireSkinned=true; bar:SetWidth(16)
	-- Reserve a predictable gutter on every client.
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT",scroll,"TOPRIGHT",6,-22)
	bar:SetPoint("BOTTOMLEFT",scroll,"BOTTOMRIGHT",6,22)
	local thumb=bar:GetThumbTexture()
	for _,region in ipairs({bar:GetRegions()}) do if region~=thumb and region.GetTexture then region:Hide() end end
	for _,key in ipairs({"Top","Bottom","Middle","Background"}) do local part=bar[key]; if type(part)=="table" or type(part)=="userdata" then part:Hide() end end
	local trough=CreateFrame("Frame",nil,bar); trough:SetAllPoints(); trough:EnableMouse(false)
	T.Frame(trough,"button-secondary",4);bar.grimoireTrough=trough
	local track=trough:CreateTexture(nil,"ARTWORK");track:SetPoint("TOPLEFT",trough,"TOPLEFT",4,-3);track:SetPoint("BOTTOMRIGHT",trough,"BOTTOMRIGHT",-4,3)
	track:SetColorTexture(0.22,0.14,0.075,1)
	local function Resize() track:SetTexCoord(0,1,0,math.max(1,bar:GetHeight())/32) end
	bar:HookScript("OnSizeChanged",Resize); Resize(); bar.grimoireTrack=track
	if thumb then
		thumb:SetSize(14,32)
		thumb:SetAlpha(1)
		thumb:SetTexture(T.artRoot.."scroll-thumb.tga")
		thumb:SetVertexColor(1,1,1,1)
		local grip=CreateFrame("Frame",nil,bar); grip:SetAllPoints(thumb); grip:EnableMouse(false)
		T.Frame(grip,"button-secondary",3,64); bar.grimoireThumb=grip
		for offset=-2,2,2 do
			local line=grip:CreateTexture(nil,"OVERLAY",nil,7)
			line:SetSize(6,1); line:SetPoint("CENTER",grip,"CENTER",0,offset)
			line:SetColorTexture(0.94,0.80,0.52,1)
		end
	end
	for _,spec in ipairs({{"ScrollUpButton","chevron-up"},{"ScrollDownButton","chevron-down"}}) do
		local b=bar[spec[1]] or scroll[spec[1]] or (name and _G[name.."ScrollBar"..spec[1]])
		if b then
			b:SetSize(18,18)
			b:ClearAllPoints()
			T.Frame(b,"button-secondary",4)
			local up=spec[1]=="ScrollUpButton"
			b:SetPoint(up and "BOTTOM" or "TOP",bar,up and "TOP" or "BOTTOM",0,up and 2 or -2)
			for _,key in ipairs({"Left","Middle","Right"}) do local part=b[key]; if type(part)=="table" or type(part)=="userdata" then part:Hide() end end
			b:SetNormalTexture(T.artRoot.."icon-"..spec[2]..".tga"); b:SetPushedTexture(T.artRoot.."icon-"..spec[2]..".tga")
			b:SetDisabledTexture(T.artRoot.."icon-"..spec[2]..".tga"); b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight","ADD")
		end
	end
end
function T.Color(region, method, token)
	region[method](region, unpack(T.colors[token]))
end
function T.Surface(frame, token)
	if T.grimoire and (token == "window" or token == "panel") then return T.Material(frame, "leather") end
	local fill = frame:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(); T.Color(fill, "SetColorTexture", token)
	if token == "window" or token == "panel" then T.Glow(frame, token == "window" and 0.24 or 0.12) end
	return fill
end

-- Original native-texture treatment: no Forever Quest Tint code or assets required.
-- The solid base stays opaque; only the decorative wash fades to transparent.
function T.Glow(frame, strength)
	if T.grimoire then T.Material(frame, "leather"); return end
	if frame.azermindGlow then return end
	frame.azermindGlow = {}
	local c = T.colors.accent
	local wash = frame:CreateTexture(nil, "BORDER", nil, -6)
	wash:SetColorTexture(1, 1, 1, 1)
	wash:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
	wash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
	if wash.SetGradient and CreateColor then
		wash:SetGradient("VERTICAL", CreateColor(c[1], c[2], c[3], strength), CreateColor(c[1], c[2], c[3], 0))
	else wash:SetColorTexture(c[1], c[2], c[3], strength * 0.25) end
	local function Resize() wash:SetHeight(math.max(1, frame:GetHeight() * 0.65)) end
	Resize(); frame:HookScript("OnSizeChanged", Resize)
	frame.azermindGlow.wash = wash
	-- Nested low-alpha bands create a soft inset rim without hard neon edges.
	for i = 1, 5 do
		local rim = frame:CreateTexture(nil, "BORDER", nil, -5)
		rim:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4 + i, 3 + i)
		rim:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4 - i, 3 + i)
		rim:SetHeight(1)
		rim:SetColorTexture(c[1], c[2], c[3], strength * (6 - i) / 12)
		table.insert(frame.azermindGlow, rim)
	end
end
function T.Label(parent, text, x, y, font)
	local label = parent:CreateFontString(nil, "OVERLAY", font or T.fonts.body)
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); label:SetText(text)
	T.Type(label, font == T.fonts.title and "title" or (font == T.fonts.heading and "heading" or "label"))
	T.Color(label, "SetTextColor", "text")
	return label
end
function T.Selected(button, selected)
	button.selectedState = selected
	if T.grimoire then
		for _,edge in ipairs(button.edges or {}) do edge:Hide() end
		T.ButtonVisual(button); return
	end
	selected=selected or button.primary
	T.Color(button.fill, "SetColorTexture", selected and "selected" or "field")
	T.Color(button.caption, "SetTextColor", selected and "accent" or "text")
	for _, edge in ipairs(button.edges) do T.Color(edge, "SetColorTexture", selected and "accent" or "border") end
end
function T.Button(parent, text, width, height, action, align, plain)
	local b
	if plain or T.grimoire then
		b = CreateFrame("Button", nil, parent)
		b:SetFontString(b:CreateFontString(nil, "OVERLAY", T.fonts.heading))
	else
		b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	end
	b:SetSize(width, height or 26); b:SetText(text); b:SetScript("OnClick", action)
	-- Keep the native red button artwork for compact controls. Tall composer
	-- controls use a template-free button so the artwork cannot stretch.
	if plain or T.grimoire then
		b:SetNormalTexture(""); b:SetPushedTexture(""); b:SetDisabledTexture(""); b:SetHighlightTexture("")
	end
	b.fill = T.Surface(b, "field")
	b.primary = plain and true or false
	b.caption = b:GetFontString(); b.caption:ClearAllPoints()
	b.caption:SetDrawLayer("OVERLAY",7)
	T.Type(b.caption, "label")
	if align == "LEFT" then b.caption:SetPoint("LEFT", b, "LEFT", 12, 0); b.caption:SetWidth(width - 32); b.caption:SetJustifyH("LEFT")
	else b.caption:SetPoint("CENTER", b, "CENTER") end
	b.edges = {}
	for _, edge in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
		local line = b:CreateTexture(nil, "BORDER")
		if edge == "TOP" or edge == "BOTTOM" then line:SetHeight(1); line:SetPoint(edge .. "LEFT", b, edge .. "LEFT"); line:SetPoint(edge .. "RIGHT", b, edge .. "RIGHT")
		else line:SetWidth(1); line:SetPoint("TOP" .. edge, b, "TOP" .. edge); line:SetPoint("BOTTOM" .. edge, b, "BOTTOM" .. edge) end
		table.insert(b.edges, line)
	end
	local hover = b:CreateTexture(nil, "HIGHLIGHT"); hover:SetAllPoints(); T.Color(hover, "SetColorTexture", "hover")
	b:HookScript("OnDisable", function(self) if T.grimoire then T.ButtonVisual(self) else T.Color(self.caption, "SetTextColor", "muted") end end)
	b:HookScript("OnEnable", function(self) T.Selected(self, self.selectedState or false) end)
	if T.grimoire then
		b:HookScript("OnMouseDown",function(self) self.grimoirePressed=true; T.ButtonVisual(self) end)
		b:HookScript("OnMouseUp",function(self) self.grimoirePressed=false; T.ButtonVisual(self) end)
		b:HookScript("OnEnter",function(self) self.grimoireHovered=true; T.ButtonVisual(self) end)
		b:HookScript("OnLeave",function(self) self.grimoireHovered=false; self.grimoirePressed=false; T.ButtonVisual(self) end)
	end
	T.Selected(b, false)
	T.Tooltip(b,function() return b:GetText() end)
	return b
end

-- Text stays meaningful when values change; tooltips expose truncated values.
function T.Tooltip(frame, title, description)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(type(title) == "function" and title() or title)
		if description then GameTooltip:AddLine(type(description) == "function" and description() or description, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Small semantic icons made from native textures, with no external assets.
function T.Icon(parent, name, x, y)
	if T.grimoire and name~="location" and name~="search" and name~="guides" then
		local icon=CreateFrame("Frame",nil,parent); icon:SetSize(20,20)
		icon:SetPoint("TOPLEFT",parent,"TOPLEFT",x or 0,y or 0)
		icon.art=icon:CreateTexture(nil,"ARTWORK"); icon.art:SetAllPoints()
		icon.art:SetTexture(T.artRoot.."icon-"..name..".tga")
		return icon
	end
	local shapes = {
		location={{2,0,10,2},{0,2,2,7},{12,2,2,7},{2,9,2,3},{10,9,2,3},{4,12,2,2},{8,12,2,2},{6,14,2,2},{6,4,2,3}},
		items={{2,4,12,11},{5,1,6,2},{4,2,2,3},{10,2,2,3}},
		quests={{2,1,12,2},{3,3,2,11},{5,13,10,2},{13,3,2,10},{7,5,4,1},{7,8,4,1}},
		guides={{1,2,1,12},{14,2,1,12},{2,2,5,1},{9,2,5,1},{7,3,2,12},{2,13,5,1},{9,13,5,1}},
		character={{5,0,6,6},{3,8,10,3},{1,11,14,4}},
		instances={{2,2,12,2},{2,4,3,12},{11,4,3,12},{5,4,6,2}},
		search={{2,1,8,2},{0,3,2,6},{10,3,2,6},{2,9,8,2},{10,10,2,2},{12,12,2,2},{14,14,2,2}},
		delete={{1,3,14,2},{5,0,6,2},{2,5,2,10},{12,5,2,10},{4,14,8,2},{6,6,1,6},{9,6,1,6}},
	}
	local icon=CreateFrame("Frame",nil,parent); icon:SetSize(16,16)
	icon:SetPoint("TOPLEFT",parent,"TOPLEFT",x or 0,y or 0)
	for _,stroke in ipairs(shapes[name] or shapes.location) do
		local line=icon:CreateTexture(nil,"ARTWORK")
		line:SetColorTexture(unpack(T.colors.gold)); line:SetSize(stroke[3],stroke[4])
		line:SetPoint("TOPLEFT",icon,"TOPLEFT",stroke[1],-stroke[2])
	end
	return icon
end

function T.SelectorAppearance(button, iconName)
	button.caption:ClearAllPoints()
	button.caption:SetPoint("LEFT",button,"LEFT",iconName and 30 or 12,0)
	button.caption:SetWidth(button:GetWidth()-(iconName and 56 or 42))
	button.caption:SetJustifyH("LEFT"); button.caption:SetWordWrap(false)
	if iconName then button.icon=T.Icon(button,iconName,8,-6) end
	button.arrow=T.Label(button,"v",button:GetWidth()-18,-7)
end

function T.IconLabel(button, name)
	button.icon=T.Icon(button,name,0,0)
	button.icon:ClearAllPoints(); button.icon:SetSize(24,24)
	button.icon:SetPoint("LEFT",button,"LEFT",10,0)
	if button.icon.art then
	 local optical={items=26,quests=24,instances=24,character=25}
	 local size=optical[name] or 24; button.icon.opticalSize=size
	 button.icon.art:ClearAllPoints();button.icon.art:SetSize(size,size)
	 button.icon.art:SetPoint("CENTER",button.icon,"CENTER",0,name=="items" and 0.5 or 0)
	end
	button.caption:ClearAllPoints(); button.caption:SetPoint("LEFT",button,"LEFT",40,0)
	local function FitCaption() button.caption:SetWidth(math.max(1,button:GetWidth()-50)) end
	FitCaption(); button:HookScript("OnSizeChanged",FitCaption)
	button.caption:SetWordWrap(false); button.caption:SetJustifyH("LEFT")
end

function T.SearchField(parent, name, width, label)
	local input=CreateFrame("EditBox",name,parent,"InputBoxTemplate")
	input:SetSize(width,28); input:SetAutoFocus(false); input:SetMaxLetters(120); T.Type(input,"body")
	input.label=T.Label(input,label,0,22)
	input:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
	return input
end

function T.Selector(parent, label, width, options, selected, onSelect)
	local b
	b = T.Button(parent, "", width, 28, function()
		local choices = type(options) == "function" and options() or options
		T.ShowChoiceMenu(b, choices, b.value, function(option)
			b:SetValue(option.key, option.label)
			onSelect(option)
		end, "Search " .. label:lower())
	end, "LEFT")
	T.SelectorAppearance(b)
	function b:SetValue(value, caption)
		self.value = value
		self:SetText(label .. ": " .. tostring(caption or value))
	end
	b:SetValue(selected)
	T.Tooltip(b, function() return b:GetText() end, "Choose an option from the list.")
	return b
end

function T.Toggle(parent, label, width, selected, onChange)
	local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	b:SetSize(24, 24)
	b:SetHitRectInsets(0,-(width-24),0,0)
	b.caption = T.Label(b, label, 28, -5)
	b.caption:SetWidth(width - 28); b.caption:SetJustifyH("LEFT")
	b:SetScript("OnClick", function(self)
		self:SetValue(self:GetChecked()); onChange(self.value)
	end)
	function b:SetValue(value)
		self.value = value and true or false
		self:SetChecked(self.value)
	end
	b.caption:SetWordWrap(false); b:SetValue(selected)
	return b
end

local choiceMenu
function T.CloseChoiceMenu()
	if choiceMenu then choiceMenu:Hide(); choiceMenu.search:ClearFocus() end
end

-- Shared draft-insertion vocabulary and visual emphasis.
function T.Primary(button)
	button.primary=true
	T.Color(button.fill, "SetColorTexture", "selected")
	for _, edge in ipairs(button.edges) do T.Color(edge, "SetColorTexture", "accent") end
end

-- Ordinary windows participate in native click-to-front ordering as one render group.
-- Do not raise from timers or touch foreign addons (or the bridge transport strip).
function T.Window(frame,strata)
 if frame.azermindWindowManaged then return end
 frame.azermindWindowManaged=true
 frame:SetFrameStrata(strata or "MEDIUM")
 frame:SetToplevel(true)
 if type(frame.SetFlattensRenderLayers)=="function" then frame:SetFlattensRenderLayers(true) end
 frame:HookScript("OnShow",function(self) self:Raise() end)
 frame:HookScript("OnMouseDown",function(self) self:Raise() end)
end

function T.FitDialog(frame)
	T.Window(frame,frame:GetFrameStrata())
	T.RegisterOpacity(frame)
	if frame.SetIgnoreParentAlpha then frame:SetIgnoreParentAlpha(true) end
	local function Fit()
		local width,height=UIParent:GetWidth(),UIParent:GetHeight()
		if width and height and width>0 and height>0 then
			frame:SetScale(math.min(1,(width-32)/frame:GetWidth(),(height-32)/frame:GetHeight()))
		end
	end
	frame:HookScript("OnShow",Fit)
	UIParent:HookScript("OnSizeChanged",function() if frame:IsShown() then Fit() end end)
	Fit()
end

function T.ProtectChanges(frame, isDirty, discard)
	StaticPopupDialogs["AZERMIND_DISCARD_UI_CHANGES"] = StaticPopupDialogs["AZERMIND_DISCARD_UI_CHANGES"] or {
		text="Discard unsaved settings?", button1="Discard", button2="Keep editing",
		timeout=0, whileDead=true, hideOnEscape=true,
		OnAccept=function(_,data) if data then data.discard() end end,
	}
	frame:HookScript("OnHide",function(self)
		-- Parent/window hiding preserves the draft; only an explicit close asks.
		if self.azermindDiscarding or self:IsShown() or not AzerMindFrame:IsShown() or not isDirty() then return end
		self:Show()
		StaticPopup_Show("AZERMIND_DISCARD_UI_CHANGES",nil,nil,{discard=function()
			self.azermindDiscarding=true; discard(); self:Hide(); self.azermindDiscarding=nil
		end})
	end)
end

-- Reconcile selections against the latest source without losing hidden matches.
function T.ReconcileSelection(selected, entries, key)
	local valid, removed = {}, 0
	for _, entry in ipairs(entries) do valid[entry[key]] = true end
	for id in pairs(selected) do
		if not valid[id] then selected[id] = nil; removed = removed + 1 end
	end
	return removed
end

function T.SourceSelection(panel, source)
	panel.selections = panel.selections or {}
	if panel.selectionSource then panel.selections[panel.selectionSource] = panel.selected end
	panel.selected = panel.selections[source] or {}
	panel.selections[source] = panel.selected
	panel.selectionSource = source
end

-- Searchable shared choices; at most nine rows exist regardless of option count.
function T.ShowChoiceMenu(anchor,options,selected,onSelect,searchLabel)
	if choiceMenu and choiceMenu:IsShown() and choiceMenu.owner==anchor then T.CloseChoiceMenu(); return end
	if not choiceMenu then
		local m=CreateFrame("Frame","AzerMindChoiceMenu",UIParent)
		choiceMenu=m; m:SetSize(304,294); m:SetClampedToScreen(true); m:EnableMouse(true)
		m:SetFrameStrata("TOOLTIP"); m:SetFrameLevel(220); T.Surface(m,"window")
		table.insert(UISpecialFrames,"AzerMindChoiceMenu")
		local search=CreateFrame("EditBox",nil,m,"InputBoxTemplate")
		search:SetSize(270,26); search:SetPoint("TOPLEFT",18,-12); search:SetAutoFocus(false); T.Type(search,"body")
		search:SetScript("OnEscapePressed",function() m:Hide() end)
		m.searchLabel=T.Label(m,"Search options",14,-43)
		local scroll=CreateFrame("ScrollFrame","AzerMindChoiceScroll",m,"UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT",8,-65); scroll:SetPoint("BOTTOMRIGHT",-30,12)
		if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
		local content=CreateFrame("Frame",nil,scroll); content:SetSize(264,1); scroll:SetScrollChild(content)
		m.rows={}; m.search=search
		m.empty=T.Label(m,"No matching options",14,-78)
		m:SetScript("OnHide",function() search:ClearFocus() end)
		local function Render()
			if m.rendering then return end; m.rendering=true
			local filter=(search:GetText() or ""):lower(); local visible={}
			for _,option in ipairs(m.options or {}) do if option.label:lower():find(filter,1,true) then visible[#visible+1]=option end end
			m.visible=visible; m.activeIndex=math.max(1,math.min(m.activeIndex or 1,#visible))
			local first=math.floor(scroll:GetVerticalScroll()/27)+1; local used=0
			for i=first,math.min(#visible,first+8) do
				used=used+1; local row=m.rows[used]
				if not row then
					row=T.Button(content,"",264,25,function() end,"LEFT"); m.rows[used]=row
					row.keyboardFocus=T.Surface(row,"hover")
					row.caption:SetWordWrap(false)
					row:SetScript("OnClick",function(self) local choose=m.onSelect; m:Hide(); choose(self.option) end)
				end
				local option=visible[i]; row.option=option
				row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*27)
				row:SetText(option.label..(option.count and (" ("..option.count..")") or "")); T.Selected(row,option.key==m.selected); row.keyboardFocus:SetShown(i==m.activeIndex); row:Show()
			end
			for i=used+1,#m.rows do m.rows[i]:Hide() end
			m.empty:SetShown(#visible==0)
			content:SetHeight(math.max(1,#visible*27)); m.rendering=false
		end
		search:SetScript("OnTextChanged",function() m.activeIndex=1; scroll:SetVerticalScroll(0); Render() end)
		search:SetAltArrowKeyMode(false)
		search:SetScript("OnArrowPressed",function(_,key)
			if key~="UP" and key~="DOWN" then return end
			m.activeIndex=math.max(1,math.min(#(m.visible or {}),(m.activeIndex or 1)+(key=="DOWN" and 1 or -1)))
			local top=(m.activeIndex-1)*27
			local current=scroll:GetVerticalScroll()
			if top<current then scroll:SetVerticalScroll(top)
			elseif top+27>current+scroll:GetHeight() then scroll:SetVerticalScroll(top+27-scroll:GetHeight()) end
			Render()
		end)
		search:SetScript("OnEnterPressed",function()
			local option=m.visible and m.visible[m.activeIndex or 1]
			if option then local choose=m.onSelect; m:Hide(); choose(option) end
		end)
		scroll:HookScript("OnVerticalScroll",Render)
		m.Refresh=function() search:SetText(""); scroll:SetVerticalScroll(0); Render() end
		m:RegisterEvent("GLOBAL_MOUSE_DOWN")
		m:SetScript("OnEvent",function(self)
			if not self:IsShown() then return end
			if MouseIsOver and self.owner and MouseIsOver(self.owner) then return end
			local x,y=GetCursorPosition()
			local function Inside(frame)
				if not frame then return false end
				local left,right,bottom,top=frame:GetLeft(),frame:GetRight(),frame:GetBottom(),frame:GetTop()
				if not left or not right or not bottom or not top then return false end
				local scale=frame:GetEffectiveScale() or 1
				return x>=left*scale and x<=right*scale and y>=bottom*scale and y<=top*scale
			end
			-- Mouse-down precedes the button's OnClick. Keep the menu open over
			-- its owner so OnClick can toggle it closed rather than reopen it.
			-- Bounds also cover clients where MouseIsOver is absent/unreliable.
			if Inside(self.owner) or Inside(self) then return end
			self:Hide()
		end)
	end
	local m=choiceMenu; m.searchLabel:SetText(searchLabel or "Search options"); m.options=options; m.selected=selected; m.onSelect=onSelect
	m:SetFrameLevel(anchor:GetFrameLevel()+20)
	m.owner=anchor
	m:SetScript("OnUpdate",function(self) if self.owner and not self.owner:IsVisible() then self:Hide() end end)
	m:ClearAllPoints(); m:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,-4); m:Show(); m.Refresh(); m.search:SetFocus()
end

-- Reusable title flourishes; the text always owns a separate bounded region.
function T.TitleOrnaments(band,title)
 band.ornaments={}
 for _,left in ipairs({true,false}) do
  local rail=band:CreateTexture(nil,"ARTWORK")
  rail:SetHeight(1); rail:SetColorTexture(0.72,0.53,0.27,0.9)
  rail:SetPoint(left and "LEFT" or "RIGHT",band,left and "LEFT" or "RIGHT",left and 8 or -8,0)
  rail:SetPoint(left and "RIGHT" or "LEFT",title,left and "LEFT" or "RIGHT",left and -16 or 16,0)
  local jewel=band:CreateTexture(nil,"ARTWORK"); jewel:SetSize(4,4)
  jewel:SetColorTexture(0.86,0.69,0.36,1)
  jewel:SetPoint("CENTER",title,left and "LEFT" or "RIGHT",left and -10 or 10,0)
  jewel:SetRotation(math.pi/4)
  band.ornaments[#band.ornaments+1]=rail; band.ornaments[#band.ornaments+1]=jewel
 end
end

-- Stitch segments are pooled and laid out only when the leather panel resizes.
function T.Stitches(frame,inset,horizontalOnly)
 if frame.grimoireStitches then return frame.grimoireStitches end
 local seam={parts={},channels={}}; frame.grimoireStitches=seam
 for _,side in ipairs(horizontalOnly and {"TOP","BOTTOM"} or {"TOP","BOTTOM","LEFT","RIGHT"}) do
  for band=0,1 do
   local t=frame:CreateTexture(nil,"BACKGROUND",nil,2)
   t:SetColorTexture(band==0 and 0.025 or 0.52,band==0 and 0.015 or 0.32,band==0 and 0.01 or 0.15,band==0 and 0.85 or 0.32)
   local d=inset+band
   if side=="TOP" or side=="BOTTOM" then
    t:SetHeight(1);t:SetPoint(side.."LEFT",frame,side.."LEFT",inset,side=="TOP" and -d or d)
    t:SetPoint(side.."RIGHT",frame,side.."RIGHT",-inset,side=="TOP" and -d or d)
   else
    t:SetWidth(1);t:SetPoint("TOP"..side,frame,"TOP"..side,side=="LEFT" and d or -d,-inset)
    t:SetPoint("BOTTOM"..side,frame,"BOTTOM"..side,side=="LEFT" and d or -d,inset)
   end
   seam.channels[#seam.channels+1]=t
  end
 end
 local function Layout()
  local count=0
  local function Thread(x,y,vertical)
   for shade=0,1 do
    count=count+1; local part=seam.parts[count]
    if not part then part=frame:CreateTexture(nil,"BORDER");seam.parts[count]=part end
    part:ClearAllPoints();part:SetPoint("TOPLEFT",frame,"TOPLEFT",x+shade,-y-shade)
    part:SetSize(vertical and (shade==0 and 2 or 1) or (shade==0 and 5 or 3),vertical and (shade==0 and 5 or 3) or (shade==0 and 2 or 1))
    part:SetColorTexture(shade==0 and 0.03 or 0.65,shade==0 and 0.018 or 0.43,shade==0 and 0.01 or 0.23,shade==0 and 0.75 or 0.7)
    part:SetRotation(math.pi/6);part:Show()
   end
  end
  for x=inset+6,frame:GetWidth()-inset-6,12 do Thread(x,inset,false);Thread(x,frame:GetHeight()-inset,false) end
  if not horizontalOnly then
   for y=inset+6,frame:GetHeight()-inset-6,12 do Thread(inset,y,true);Thread(frame:GetWidth()-inset,y,true) end
  end
  for i=count+1,#seam.parts do seam.parts[i]:Hide() end
 end
 frame:HookScript("OnSizeChanged",Layout);Layout();return seam
end

T.opacityRoots=setmetatable({},{__mode="k"})
function T.RegisterOpacity(frame)
 T.opacityRoots[frame]=true
 if frame.SetIgnoreParentAlpha then frame:SetIgnoreParentAlpha(true) end
 frame:SetAlpha(T.opacity or 1)
end
function T.ApplyOpacity(value)
 T.opacity=value
 for frame in pairs(T.opacityRoots) do frame:SetAlpha(value) end
end

-- Use image regions directly on the button: no nested glyph frames in scroll children.
function T.InkGlyph(button,kind)
 local icon=button:CreateTexture(nil,"OVERLAY",nil,7)
 icon:SetSize(24,24);icon:SetPoint("CENTER",button,"CENTER",0,0)
 icon:SetTexture(T.artRoot.."icon-"..kind..".tga")
 icon.glyphKind=kind;icon:Show()
 return icon
end

function T.PaperBevel(frame)
 if frame.paperBevel then return end
 frame.paperBevel={}
 for _,spec in ipairs({{7,0.30,0.18,0.08,0.42},{9,0.96,0.88,0.69,0.65},{11,0.45,0.29,0.13,0.25}}) do
  local inset=spec[1]
  for _,side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
   local t=frame:CreateTexture(nil,"BORDER")
   t:SetColorTexture(spec[2],spec[3],spec[4],spec[5])
   if side=="TOP" or side=="BOTTOM" then
    t:SetHeight(1);t:SetPoint(side.."LEFT",frame,side.."LEFT",inset,side=="TOP" and -inset or inset)
    t:SetPoint(side.."RIGHT",frame,side.."RIGHT",-inset,side=="TOP" and -inset or inset)
   else
    t:SetWidth(1);t:SetPoint("TOP"..side,frame,"TOP"..side,side=="LEFT" and inset or -inset,-inset)
    t:SetPoint("BOTTOM"..side,frame,"BOTTOM"..side,side=="LEFT" and inset or -inset,inset)
   end
   frame.paperBevel[#frame.paperBevel+1]=t
  end
 end
end
function T.MessageOutline(frame)
 frame.innerOutline={}
 for _,side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
  local t=frame:CreateTexture(nil,"BORDER");t:SetColorTexture(0.48,0.35,0.19,0.16)
  if side=="TOP" or side=="BOTTOM" then
   t:SetHeight(1);t:SetPoint(side.."LEFT",frame,side.."LEFT",6,side=="TOP" and -3 or 3)
   t:SetPoint(side.."RIGHT",frame,side.."RIGHT",-6,side=="TOP" and -3 or 3)
  else
   t:SetWidth(1);t:SetPoint("TOP"..side,frame,"TOP"..side,side=="LEFT" and 6 or -6,-3)
   t:SetPoint("BOTTOM"..side,frame,"BOTTOM"..side,side=="LEFT" and 6 or -6,3)
  end
  frame.innerOutline[#frame.innerOutline+1]=t
 end
end

-- Faceted vertical crystal, authored as bounded UI geometry at native size.
function T.ConnectCrystal(button)
 if button.connectCrystal then return button.connectCrystal end
 local gem=CreateFrame("Frame",nil,button);gem:SetSize(24,36);gem:EnableMouse(false)
 for y=0,35 do
  local half=math.max(1,math.floor(11*(1-math.abs((y-17.5)/18))))
  for facet=0,2 do
   local t=gem:CreateTexture(nil,"ARTWORK")
   local left=facet==0 and 11-half or (facet==1 and 12-half or 12)
   t:SetPoint("TOPLEFT",gem,"TOPLEFT",left,-y)
   t:SetSize(facet==0 and half*2+2 or half,1)
   if facet==0 then t:SetColorTexture(0.24,0.12,0.37,1)
   elseif facet==1 then t:SetColorTexture(0.76,0.50,0.98,1)
   else t:SetColorTexture(0.38,0.16,0.64,1) end
  end
 end
 button.connectCrystal=gem;return gem
end
