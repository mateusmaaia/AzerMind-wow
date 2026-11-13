-- General settings shell. AI options are scoped to defaults or one conversation.
local panel
local Theme = AzerMindTheme
local function Label(parent, text, x, y, template)
	return Theme.Label(parent, text, x, y, template)
end
local function Button(parent, text, width, x, y, action)
	local b = Theme.Button(parent, text, width, 26, action)
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	return b
end
local function Solid(frame, token)
	return Theme.Surface(frame, token)
end

-- A selected tab stays bright; disabled-looking buttons do not indicate scope.
local function Flat(parent, text, width, x, y, action)
	local b = Theme.Button(parent, text, width, 28, action, "LEFT")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	return b
end

function AzerMind.CodexPrompt(id)
	local chat = AzerMind.SettingsState(id)
	if not chat then return end
	if not panel then
		local p = CreateFrame("Frame", "AzerMindGeneralSettings", AzerMindFrame, "BackdropTemplate")
		panel = p
		Theme.ProtectChanges(p,function() return p.dirty end,function() p.dirty=false end)
		p:SetSize(640, 460); p:SetPoint("CENTER", AzerMindFrame, "CENTER")
		p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(AzerMindFrame:GetFrameLevel() + 100)
		p:SetAlpha(1); if p.SetIgnoreParentAlpha then p:SetIgnoreParentAlpha(true) end
		p:EnableMouse(true); Solid(p, "window"); Theme.FitDialog(p)
		Label(p, "Settings", 22, -20, "GameFontNormalLarge")
        Label(p,"UI revision 2026-11-11.2",180,-22)
		local side = CreateFrame("Frame", nil, p); side:SetSize(146, 332); side:SetPoint("TOPLEFT", 12, -76)
		Solid(side, "panel")
		Theme.Selected(Flat(side, "AI Config", 126, 10, -12, function() end), true)
		local function Navigate(action)
			if p.dirty or p.pending then p.message="Save or cancel changes before switching settings."; p.Refresh(); return end
			p:Hide(); action()
            local child=AzerMindGuideSettings and AzerMindGuideSettings:IsShown() and AzerMindGuideSettings or AzerMindContextSettings and AzerMindContextSettings:IsShown() and AzerMindContextSettings or AzerMindNotificationSettings and AzerMindNotificationSettings:IsShown() and AzerMindNotificationSettings or AzerMindKeySettings
            if child then
                if not child.parentBackHook then
                    child:HookScript("OnHide",function(self) if self.returnSettings and not self:IsShown() then self.returnSettings=false; panel:Show() end end)
                    Button(child,"Back",80,20,-child:GetHeight()+40,function() child:Hide() end)
                    child.parentBackHook=true
                end
                child.returnSettings=true
            end
		end
		Flat(side, "Guide references", 126, 10, -48, function() Navigate(AzerMind.ShowGuideSettings) end)
		Flat(side, "Character", 126, 10, -84, function() Navigate(AzerMind.ShowContextSettings) end)
        Flat(side,"Notifications",126,10,-120,function() Navigate(AzerMind.ShowNotificationSettings) end)
        Flat(side,"Key bindings",126,10,-156,function() Navigate(AzerMind.ShowKeySettings) end)
		Label(p, "AI Config", 180, -80, "GameFontNormalLarge")
		Label(p, "Applies to", 180, -105)
		p.scope = "conversation"
		local Refresh, Load
		local function Changed() p.dirty = true; p.message = "Unsaved changes"; Refresh() end
		local defaultsButton = Flat(p, "Conversation defaults", 210, 180, -128, function()
			if p.dirty or p.pending then p.message = "Save or cancel your changes before switching scope."; Refresh(); return end
			p.scope = "default"; Load()
		end)
		local conversationButton = Flat(p, "This conversation", 210, 398, -128, function()
			if p.dirty or p.pending then p.message = "Save or cancel your changes before switching scope."; Refresh(); return end
			p.scope = "conversation"; Load()
		end)
		p.scopeHelp = Label(p, "", 180, -166); p.scopeHelp:SetWidth(428); p.scopeHelp:SetJustifyH("LEFT")
		p.inheritButton = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
		p.inheritButton:SetSize(24, 24); p.inheritButton:SetPoint("TOPLEFT", 180, -197)
		p.inheritButton:SetScript("OnClick", function() if not p.pending then p.inherit = not p.inherit; Changed() end end)
		p.inheritLabel = Label(p, "Use default settings", 210, -203)
		p.agentLabel = Label(p, "Agent", 180, -240)
		p.modelLabel = Label(p, "Model", 180, -284)
		p.reasonLabel = Label(p, "Reasoning effort", 180, -328)
        local dropdown={Hide=function() Theme.CloseChoiceMenu() end}
        local function Select(button, values, key)
            if p.pending or (p.scope=="conversation" and p.inherit) then return end
            local choices={}; for _,value in ipairs(values) do choices[#choices+1]={key=value[1],label=value[2]} end
            Theme.ShowChoiceMenu(button,choices,p[key],function(option)
                if option.key=="__custom" then
                    p.customModel:SetText(p.modelValue); p.customModel:Show(); p.customModel:SetFocus(); return
                end
                p[key]=option.key
                if key=="modelValue" then p.reasoningValue="" end
                if key=="agentValue" then
                    local chat=AzerMind.SettingsState(p.chatId)
                    local saved=AzerMind.ChatAISettings(chat,p.agentValue)
                    if p.scope=="default" then local _,_,_,_,_,meta=AzerMind.SettingsState(p.chatId,p.agentValue); saved=meta end
                    p.modelValue=saved.model or ""; p.reasoningValue=saved.reasoning or ""
                end
                Changed()
            end,key=="modelValue" and "Search models" or "Search options")
        end
		p.agent = Flat(p, "", 428, 180, -256, function()
			local _, _, _, agents = AzerMind.SettingsState(p.chatId, p.agentValue)
			local values = {}; for _, agent in ipairs(agents) do table.insert(values, {agent, agent}) end
			Select(p.agent, values, "agentValue")
		end)
		p.model = Flat(p, "", 428, 180, -300, function()
			local _, _, models = AzerMind.SettingsState(p.chatId, p.agentValue)
			local values = {{"", "Automatic (CLI configuration)"}}
            for _,m in ipairs(models) do table.insert(values,{m.model,(m.name or m.model)..(m.name and m.name~=m.model and (" ["..m.model.."]") or "")}) end
            table.insert(values,{"__custom","Advanced: custom model ID..."})
			Select(p.model, values, "modelValue")
		end)
		p.customModel = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
		p.customModel:SetSize(420, 28); p.customModel:SetPoint("TOPLEFT", 184, -300)
		p.customModel:SetAutoFocus(false); p.customModel:SetMaxLetters(200); p.customModel:Hide()
		p.customModel:SetFrameLevel(p:GetFrameLevel() + 25)
		p.customModel:SetScript("OnTextChanged", function() if p.customModel:IsShown() then Changed() end end)
		p.customModel:SetScript("OnEnterPressed", function(self)
			p.modelValue = self:GetText():match("^%s*(.-)%s*$"); p.reasoningValue = ""
			self:ClearFocus(); self:Hide(); Changed()
		end)
		p.customModel:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:Hide() end)
		p.reasoning = Flat(p, "", 428, 180, -344, function()
            local efforts=AzerMind.ModelEfforts(p.agentValue,p.modelValue)
			local descriptions = {none="Disabled",minimal="Minimal",low="Low - faster", medium="Medium - balanced", high="High - deeper analysis", xhigh="Extra high", max="Maximum", ultra="Ultra"}
			local values = {{"", "Default (CLI configuration)"}}
			for _, effort in ipairs(efforts) do table.insert(values, {effort, descriptions[effort] or effort}) end
			Select(p.reasoning, values, "reasoningValue")
		end)
		for _, field in ipairs({p.agent, p.model, p.reasoning}) do Theme.SelectorAppearance(field) end
        p.catalogInfo=Label(p,"",180,-52); p.catalogInfo:SetWidth(294); p.catalogInfo:SetJustifyH("LEFT"); p.catalogInfo:SetWordWrap(false)
        p.refreshModels=Button(p,"Refresh models",126,482,-44,function()
            local _,message=AzerMind.RefreshModelChoices(); p.message=message; Refresh()
        end)
        Theme.Tooltip(p.refreshModels,"Refresh model choices",function() return p.catalogInfo:GetText()..". Refreshes choices without changing your saved settings." end)
        Theme.Tooltip(p.model,function() return "Model: "..(p.effectiveModel~="" and p.effectiveModel or "Automatic") end)
        p.reasonHelp=Label(p,"",180,-338); p.reasonHelp:SetWidth(428); p.reasonHelp:SetJustifyH("LEFT")
		p.status = Label(p, "", 180, -385); p.status:SetWidth(430); p.status:SetJustifyH("LEFT")
		p.save = Button(p, "Save changes", 138, 480, -422, function()
			if p.customModel:IsShown() then
				p.modelValue = p.customModel:GetText():match("^%s*(.-)%s*$"); p.reasoningValue = ""; p.dirty = true
			end
			if p.pending or not p.dirty then return end
			local ok, message = AzerMind.SaveAISettings(p.chatId, p.scope, {agent=p.agentValue, model=p.modelValue, reasoning=p.reasoningValue, inherit=p.inherit})
			p.message = message
			if ok then p.dirty = false; p.pending = p.scope == "default" end
			Refresh()
		end)
		Button(p, "Cancel", 100, 370, -422, function() if not p.pending then p.dirty=false; dropdown:Hide(); p:Hide() end end)
		Button(p, "X", 26, 594, -16, function() if not p.pending then p.dirty=false; dropdown:Hide(); p:Hide() end end)
		Refresh = function()
			local _, defaults = AzerMind.SettingsState(p.chatId, p.agentValue)
			local inherited = p.scope == "conversation" and p.inherit
			local agent = inherited and defaults.agent or p.agentValue
			local model = inherited and defaults.model or p.modelValue
			local reasoning = inherited and defaults.reasoning or p.reasoningValue
			p.inheritButton:SetShown(p.scope == "conversation")
			p.inheritLabel:SetShown(p.scope == "conversation")
			p.inheritButton:SetEnabled(not p.pending)
			p.inheritButton:SetChecked(p.inherit)
			p.scopeHelp:SetText(p.scope == "default" and "All conversations following defaults; used by new chats." or ("This conversation: " .. ((AzerMind.SettingsState(p.chatId, p.agentValue)).name or "current conversation")))
			p.agent:SetText(agent)
			p.effectiveModel=model
			local modelCaption=model
			local _,_,catalog=AzerMind.SettingsState(p.chatId,agent)
			for _,entry in ipairs(catalog) do if entry.model==model then modelCaption=entry.name or model; break end end
			p.model:SetText(model ~= "" and modelCaption or "Automatic (CLI configuration)")
			p.reasoning:SetText(reasoning ~= "" and reasoning or "Automatic (CLI configuration)")
			local _, _, _, _, _, meta = AzerMind.SettingsState(p.chatId, agent)
			p.model:Show(); p.modelLabel:Show()
            local efforts,known=AzerMind.ModelEfforts(agent,model)
            local reasoningSupported=known and #efforts>0
            if not inherited and p.reasoningValue~="" then
                local valid=false; for _,effort in ipairs(efforts) do if effort==p.reasoningValue then valid=true end end
                if not known or not valid then p.reasoningValue=""; p.dirty=true; p.message="Unsupported reasoning cleared to Automatic."; p.reasoning:SetText("Automatic (CLI configuration)") end
            end
            p.reasonHelp:SetText(known and "Reasoning is fixed for this model." or "Reasoning options are not known for this model. Using Automatic.")
            if inherited and not known and reasoning~="" then p.reasonHelp:SetText("Inherited reasoning: "..reasoning.." (capabilities not reported).") end
            p.reasonHelp:SetShown(not reasoningSupported)
            local catalogState={stale=" - cached; refresh failed",cached=" - cached",["not-installed"]=" - CLI not found",unavailable=" - no local catalog"}
            p.catalogInfo:SetText((meta.catalogSource or "Connect to load model choices.")..(catalogState[meta.catalogStatus] or ""))
            p.refreshModels:SetEnabled(not p.pending)
			p.reasoning:SetShown(reasoningSupported); p.reasonLabel:SetShown(reasoningSupported)
			p.agent:SetEnabled(not inherited and not p.pending)
			p.model:SetEnabled(not inherited and not p.pending); p.reasoning:SetEnabled(not inherited and not p.pending)
			p.save:SetEnabled(p.dirty and not p.pending)
			for _, tab in ipairs({defaultsButton, conversationButton}) do
				local selected = (tab == defaultsButton) == (p.scope == "default")
				Theme.Selected(tab, selected)
			end
			for _, field in ipairs({p.agent, p.model, p.reasoning}) do field:SetAlpha(inherited and 0.5 or 1) end
			p.status:SetText(p.message or (inherited and "Using defaults. Uncheck the box above to customize." or "Changes apply to your next message."))
		end
		Load = function()
			local c, defaults, _, _, pending = AzerMind.SettingsState(p.chatId, p.agentValue)
			p.pending = pending ~= nil; p.dirty = false; p.message = nil
			local options = AzerMind.ChatAISettings(c)
			p.inherit = (c.agent or "") == "" and (options.model or "") == "" and (options.reasoning or "") == ""
			p.agentValue = p.scope == "default" and defaults.agent or ((c.agent and c.agent ~= "") and c.agent or defaults.agent)
			p.modelValue = p.scope == "default" and defaults.model or (options.model or "")
			p.reasoningValue = p.scope == "default" and defaults.reasoning or (options.reasoning or "")
			p.customModel:Hide(); dropdown:Hide(); Refresh()
		end
		p.Refresh, p.Load = Refresh, Load
		AzerMind.AttachSettingsPanel(p)
	end
	if panel.dirty then
		if panel.chatId~=chat.id then panel.message="Save or cancel changes before switching conversations."; panel.Refresh() end
		panel:Show(); return
	end
	panel.chatId = chat.id; panel.Load(); panel:Show()
end


local contextPanel
function AzerMind.ShowContextSettings()
	if not contextPanel then
		local p = CreateFrame("Frame", "AzerMindContextSettings", AzerMindFrame, "BackdropTemplate")
		contextPanel = p
		Theme.ProtectChanges(p,function() return p.dirty end,function() p.dirty=false end)
		p:SetSize(600, 470); p:SetPoint("CENTER", AzerMindFrame, "CENTER")
		p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(AzerMindFrame:GetFrameLevel() + 100)
		p:EnableMouse(true); p:SetClampedToScreen(true); Solid(p, "window"); Theme.FitDialog(p)
		table.insert(UISpecialFrames, "AzerMindContextSettings")
		Label(p, "Share character context", 20, -18, "GameFontNormalLarge")
		Label(p, "Choose what accompanies future messages in all conversations.", 20, -46)
		local function Check(text, x, y, action)
			local b = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
			b:SetSize(24, 24); b:SetPoint("TOPLEFT", x, y)
			b.caption=Label(p, text, x + 28, y - 5)
			b:SetScript("OnClick", action); return b
		end
		local Refresh
		p.enabledBox = Check("Enable automatic sharing", 20, -76, function(self) p.enabled = self:GetChecked() == true; p.dirty=true; Refresh() end)
		p.checks = {}
		Refresh = function()
			p.enabledBox:SetChecked(p.enabled)
			for key, box in pairs(p.checks) do
				box:SetChecked(p.options[key]); box:SetEnabled(p.enabled)
				box.caption:SetAlpha(p.enabled and 1 or 0.5)
			end
			for _,button in ipairs(p.presets or {}) do button:SetEnabled(p.enabled) end
		end
		p.presets={
			Button(p, "Basic", 90, 20, -112, function() p.options = AzerMind.ContextOptions("basic"); p.dirty=true; Refresh() end),
			Button(p, "All available", 112, 118, -112, function() p.options = AzerMind.ContextOptions("full"); p.dirty=true; Refresh() end),
			Button(p, "Clear selection", 120, 238, -112, function() p.options = {}; p.dirty=true; Refresh() end)
		}
		for i, field in ipairs(AzerMind.ContextCategories) do
			local key, caption = field[1], field[2]
			local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
			p.checks[key] = Check(caption, 20 + column * 280, -156 - row * 28, function(self)
				p.options[key] = self:GetChecked() == true
				p.dirty=true
			end)
		end
		local help = Label(p, "Pet abilities and individual talent ranks are not collected. Missing data and size limits are marked in the preview. Turning sharing off does not erase previously sent data.", 20, -338)
		help:SetWidth(560); help:SetJustifyH("LEFT")
		Button(p, "Preview", 110, 20, -414, function()
			AzerMind.ShowCopy(p.enabled and AzerMind.GameContext(p.options) or "Automatic character context sharing is off.")
			AzerMindCopy:SetFrameLevel(p:GetFrameLevel() + 20)
		end)
		Button(p, "Cancel", 100, 346, -414, function() p.dirty=false; p:Hide() end)
		Button(p, "Save", 120, 454, -414, function()
			AzerMind.SaveContextSettings(p.options, p.enabled); p.dirty=false; p:Hide()
		end)
		Button(p, "X", 26, 554, -14, function() p:Hide() end)
		p.Refresh = Refresh
	end
	local p = contextPanel
	if p.dirty then p:Show(); return end
	p.options, p.enabled = AzerMind.ContextSettings()
	p.Refresh(); p:Show()
end

-- One URL per line keeps adding and removing references straightforward.
local guidePanel
function AzerMind.ShowGuideSettings()
	if not guidePanel then
		local p = CreateFrame("Frame", "AzerMindGuideSettings", AzerMindFrame, "BackdropTemplate")
		guidePanel = p
		Theme.ProtectChanges(p,function() return p.dirty end,function() p.dirty=false end)
		p:SetSize(600, 430); p:SetPoint("CENTER", AzerMindFrame, "CENTER")
		p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(AzerMindFrame:GetFrameLevel() + 130)
		p:EnableMouse(true); p:SetClampedToScreen(true); Solid(p, "window"); Theme.FitDialog(p)
		table.insert(UISpecialFrames, "AzerMindGuideSettings")
		Label(p, "Guide references", 20, -20, "GameFontNormalLarge")
		local help = Label(p, "Applies to: All conversations. One guide URL per line (up to 20). Independent of character sharing.", 20, -54)
		help:SetWidth(552); help:SetJustifyH("LEFT")
		local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
		scroll:SetSize(530, 210); scroll:SetPoint("TOPLEFT", 24, -124)
		p.count=Label(p,"",24,-96)
		Solid(scroll, "panel")
		local input = CreateFrame("EditBox", nil, scroll)
		input:SetMultiLine(true); input:SetAutoFocus(false); input:SetFontObject("ChatFontNormal")
		input:SetWidth(524); input:SetHeight(230); input:SetMaxLetters(10000)
		input:EnableMouse(true); scroll:EnableMouse(true)
		-- The empty area below the text must focus the editor too.
		scroll:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then input:SetFocus() end end)
		input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		scroll:SetScrollChild(input); p.input = input
		input:SetScript("OnTextChanged",function()
			local count=0; for line in (input:GetText().."\n"):gmatch("([^\n]*)\n") do if line:find("%S") then count=count+1 end end
			p.count:SetText(count.." / 20 guide links"); p.dirty=input:GetText()~=AzerMind.GuideReferences()
			if p.save then p.save:SetEnabled(p.dirty) end
		end)
		p:SetScript("OnHide",function() p.input:ClearFocus() end)
		p.status = Label(p, "Changes apply to future messages. Previously shared links remain in chat history.", 20, -354)
		p.status:SetWidth(560); p.status:SetJustifyH("LEFT")
		Button(p, "Cancel", 100, 346, -390, function() p.dirty=false; p.input:ClearFocus(); p:Hide() end)
		p.save=Button(p, "Save", 120, 454, -390, function()
			local ok, message = AzerMind.SaveGuideReferences(p.input:GetText())
			if ok then p.input:SetText(AzerMind.GuideReferences()); p.dirty=false; p.save:Disable(); p.status:SetText("Saved. Applies to future messages in all conversations.") else p.status:SetText(message) end
		end)
		Button(p, "X", 26, 554, -14, function() p.input:ClearFocus(); p:Hide() end)
	end
	if guidePanel.dirty then guidePanel:Show(); guidePanel.input:SetFocus(); return end
	guidePanel.input:SetText(AzerMind.GuideReferences())
	guidePanel.input:GetScript("OnTextChanged")(); guidePanel.dirty=false; guidePanel.save:Disable()
	guidePanel.status:SetText("Changes apply to future messages. Previously shared links remain in chat history.")
	guidePanel:Show(); guidePanel.input:SetFocus()
end

function AzerMind.ShowNotificationSettings()
    local p=AzerMindNotificationSettings
    if not p then
        p=CreateFrame("Frame","AzerMindNotificationSettings",AzerMindFrame,"BackdropTemplate")
        p:SetSize(520,280); p:SetPoint("CENTER"); p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(AzerMindFrame:GetFrameLevel()+120)
        p:EnableMouse(true); Solid(p,"window"); Theme.FitDialog(p); table.insert(UISpecialFrames,"AzerMindNotificationSettings")
        Label(p,"Reply notifications",110,-24,"GameFontNormalLarge")
        Label(p,"Applies to all conversations. Changes are saved immediately.",20,-70)
        local options={{key=0,label="None"},{key=3081,label="Whisper"},{key=18019,label="Battle.net toast"},{key=3175,label="Map ping"},{key=8960,label="Ready check"},{key=7355,label="Tutorial popup"}}
        p.sound=Theme.Selector(p,"Sound",320,options,AzerMind.ReplySound(),function(o) AzerMind.ReplySound(o.key) end)
        p.sound:SetPoint("TOPLEFT",20,-110)
        Button(p,"Preview",120,360,-110,function() local sound=AzerMind.ReplySound(); if sound~=0 then pcall(PlaySound,sound,"Master") end end)
        Button(p,"Close",100,380,-226,function() p:Hide() end)
        p.options=options
    end
    for _,o in ipairs(p.options) do if o.key==AzerMind.ReplySound() then p.sound:SetValue(o.key,o.label) end end
    p:Show()
end

function AzerMind.ShowKeySettings()
 local p=AzerMindKeySettings
 if not p then
  p=CreateFrame("Frame","AzerMindKeySettings",AzerMindFrame); p:SetSize(560,340); p:SetPoint("CENTER")
  p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(AzerMindFrame:GetFrameLevel()+120); p:EnableMouse(true)
  Solid(p,"window"); Theme.FitDialog(p); table.insert(UISpecialFrames,"AzerMindKeySettings")
  Label(p,"Chat key bindings",110,-24,"GameFontNormalLarge")
  Label(p,"Enter a key combination, for example CTRL-SHIFT-C.",20,-68)
  p.status=Label(p,"",20,-230); p.status:SetWidth(510); p.status:SetJustifyH("LEFT")
  for i,spec in ipairs({{"Open chat","AzerMindOpenChatKeyButton",function() AzerMind.Toggle(true) end},{"New chat","AzerMindNewChatKeyButton",function() AzerMind.NewChat() end}}) do
   local input=Theme.SearchField(p,nil,300,spec[1]); input:SetPoint("TOPLEFT",24,-116-(i-1)*70); input:SetMaxLetters(50)
   Button(p,"Bind",100,436,-116-(i-1)*70,function()
    if InCombatLockdown() then p.status:SetText("Key bindings can be changed outside combat."); return end
    local key=(input:GetText() or ""):upper():gsub("%s","")
    if key=="" or not key:match("^[%w%-]+$") then p.status:SetText("Enter a valid key combination."); return end
    local command="CLICK "..spec[2]..":LeftButton"
    local existing=GetBindingAction and GetBindingAction(key)
    if existing and existing~="" and existing~=command then p.status:SetText(key.." is already bound to "..existing..". Choose another key."); return end
    local first,second
    if GetBindingKey then first,second=GetBindingKey(command) end
    if SetBinding(key,command)==false then p.status:SetText("The client rejected this key combination."); return end
    if first and first~=key then SetBinding(first) end
    if second and second~=key then SetBinding(second) end
    SaveBindings(GetCurrentBindingSet()); p.status:SetText(spec[1].." bound to "..key..". Opening the chat focuses the message field.")
   end)
   local current=GetBindingKey and GetBindingKey("CLICK "..spec[2]..":LeftButton"); input:SetText(current or "")
  end
  Button(p,"Close",100,436,-286,function() p:Hide() end)
 end
 p:Show()
end
