-- Inventory browsing is read-only. Closed-bank contents are explicitly cached.
local T, picker, bankOpen = AzerMindTheme, nil, false
local function Read(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a,b,c,d,e,f,g,h,i,j,k,l,m,n = pcall(fn, ...)
	if ok then return a,b,c,d,e,f,g,h,i,j,k,l,m,n end
	return nil
end
local function Cache()
	AzerMindItemsDB = AzerMindItemsDB or {}
	local key = (Read(GetRealmName) or "") .. ":" .. (Read(UnitName, "player") or "")
	AzerMindItemsDB[key] = AzerMindItemsDB[key] or {}
	return AzerMindItemsDB[key]
end
local function ScanBank()
	if not bankOpen then return end
	local api, items = C_Container or {}, {}
	for bag = -1, 11 do
		if bag == -1 or bag >= 5 then
			for slot = 1, tonumber(Read(api.GetContainerNumSlots or GetContainerNumSlots, bag)) or 0 do
				local link = Read(api.GetContainerItemLink or GetContainerItemLink, bag, slot)
				if link then
					local info = Read(api.GetContainerItemInfo, bag, slot)
					local _, count = Read(GetContainerItemInfo, bag, slot)
					items[#items+1] = {link=link, count=type(info)=="table" and info.stackCount or count or 1}
				end
			end
		end
	end
	local cache = Cache(); cache.bank = items; cache.updated = date("%Y-%m-%d %H:%M")
end
function AzerMind.OwnedItems()
	local result, grouped = {}, {}
	local function Add(link, count, location)
		if type(link) ~= "string" then return end
		local payload, label = link:match("|H(item:[^|]+)|h(.-)|h")
		if not payload then return end
		local key = location .. ":" .. payload
		if grouped[key] then grouped[key].count = grouped[key].count + (count or 1); return end
		local query = C_Item and C_Item.GetItemInfo or GetItemInfo
		local name, _, quality, _, level, kind, subtype, _, slot, icon, _, classID, subclassID = Read(query, link)
		local item = {key=key, link=AzerMind.NormalizeItemLink(link), name=name or AzerMind.PlainText(label),
			id=tonumber(payload:match("item:(%d+)")), count=count or 1, location=location, quality=quality,
			level=level, kind=kind or "", subtype=subtype or "", slot=slot or "", icon=icon, classID=classID, subclassID=subclassID}
		grouped[key]=item; result[#result+1]=item
	end
	for slot=1,19 do Add(Read(GetInventoryItemLink, "player", slot), 1, "Equipped") end
	local api = C_Container or {}
	for bag=0,4 do
		for slot=1,tonumber(Read(api.GetContainerNumSlots or GetContainerNumSlots, bag)) or 0 do
			local link = Read(api.GetContainerItemLink or GetContainerItemLink, bag, slot)
			local info = Read(api.GetContainerItemInfo, bag, slot)
			local _, count = Read(GetContainerItemInfo, bag, slot)
			Add(link, type(info)=="table" and info.stackCount or count or 1, "Bags")
		end
	end
	for _, item in ipairs(Cache().bank or {}) do Add(item.link, item.count, "Bank") end
	table.sort(result, function(a,b) if a.name == b.name then return a.key < b.key end; return a.name < b.name end)
	return result
end
local categories = {
	{"All items"}, {"Armor",4}, {"  Cloth",4,1}, {"  Leather",4,2}, {"  Mail",4,3}, {"  Plate",4,4}, {"  Shields",4,6},
	{"Weapons",2}, {"Accessories","accessories"}, {"Consumables",0}, {"Materials",7}, {"Recipes",9}, {"Containers",1}, {"Gems",3}, {"Reagents",5}, {"Projectiles",6}, {"Quivers",11}, {"Keys",13}, {"Quest items",12}, {"Other","other"},
}
local accessorySlots = {INVTYPE_NECK=true, INVTYPE_FINGER=true, INVTYPE_TRINKET=true, INVTYPE_CLOAK=true}
local function Category(item, category)
	local class, sub = category[2], category[3]
	if not class then return true end
	if class == "accessories" then return accessorySlots[item.slot] or false end
	if class == "other" then return not ({[0]=true,[2]=true,[4]=true,[7]=true,[9]=true,[1]=true,[3]=true,[5]=true,[6]=true,[11]=true,[13]=true,[12]=true})[item.classID] end
	return item.classID == class and (not sub or item.subclassID == sub)
end
function AzerMind.ShowItemPicker()
	local chat = AzerMind.SettingsState(); if not chat then return end
	if not picker then
		local p = CreateFrame("Frame", "AzerMindItemPicker", AzerMindFrame)
		picker=p; p:SetSize(760,600); p:SetPoint("CENTER"); p:SetClampedToScreen(true)
		p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetFrameLevel(AzerMindFrame:GetFrameLevel()+110); p:EnableMouse(true)
		if p.SetIgnoreParentAlpha then p:SetIgnoreParentAlpha(true) end
		T.Surface(p,"window"); T.FitDialog(p); table.insert(UISpecialFrames,"AzerMindItemPicker")
		T.Label(p,"Items",20,-18,T.fonts.title)
		local function Button(label,w,x,y,action)
			local b=T.Button(p,label,w,26,action); b:SetPoint("TOPLEFT",x,y); return b
		end
		Button("X",26,714,-14,function() p:Hide() end)
		p.mode="owned"
		local tab=Button("My items",120,20,-52,function() p.mode="owned"; p.location="All"; p.onlySelected=false; p.Refresh() end)
		local db=Button("Item database",140,148,-52,function() p.mode="catalog"; p.location="All"; p.onlySelected=false; p.Refresh() end)
		p.version=T.Label(p,"",304,-59); p.version:SetWidth(430); p.version:SetJustifyH("LEFT")
		local search=T.SearchField(p,nil,708,"Search by name, type, or item ID")
		search:SetPoint("TOPLEFT",26,-110)
		search:SetMaxLetters(100); search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
		p.rows,p.selected,p.category,p.location,p.rarity,p.level,p.slot={}, {},1,"All",-1,false,"All"
		local scroll=CreateFrame("ScrollFrame","AzerMindItemPickerScroll",p,"UIPanelScrollFrameTemplate")
		-- Reserve the entire selection toolbar below the viewport. Previously
		-- the viewport extended through it, so rows covered its buttons.
		scroll:SetPoint("TOPLEFT",192,-224); scroll:SetPoint("BOTTOMRIGHT",-40,156)
		if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
		local content=CreateFrame("Frame",nil,scroll); content:SetSize(520,1); scroll:SetScrollChild(content)
		p.summary=T.Label(p,"",20,-526)
		p.bank=T.Label(p,"",20,-552); p.bank:SetWidth(410); p.bank:SetJustifyH("LEFT")
		p.page=1
		p.pageLabel=T.Label(p,"",302,-498)
		local categoryButtons, locationButtons={},{}
		local function Render()
			if p.rendering then return end
			p.rendering=true
			local visible, total, hidden=p.visible or {},0,0
			local filter=(search:GetText() or ""):lower()
			local query=table.concat({p.mode,filter,p.location,p.category,p.rarity,tostring(p.minLevel),tostring(p.maxLevel),tostring(p.subclass),p.slot,tostring(p.onlySelected)},":")
			if query~=p.query then
				p.query=query; p.page=1; visible={}; p.matchKeys={}; scroll:SetVerticalScroll(0)
			for _,item in ipairs(p.items or {}) do
				if p.slot~="All" then AzerMind.EnrichCatalogItem(item) end
                local match=(p.location=="All" or item.location==p.location or (p.mode=="catalog" and p.ownership[item.id] and p.ownership[item.id][p.location])) and Category(item,categories[p.category])
					and (p.rarity==-1 or item.quality==p.rarity)
                    and (not p.minLevel or (item.level and item.level>=p.minLevel))
                    and (not p.maxLevel or (item.level and item.level<=p.maxLevel))
                    and (not p.subclass or (tostring(item.classID)..":"..tostring(item.subclassID))==p.subclass)
					and (p.slot=="All" or item.slot==p.slot) and (not p.onlySelected or p.selected[item.key])
					and (item.name.." "..item.kind.." "..item.subtype.." "..(item.id or "")):lower():find(filter,1,true)
				if match then visible[#visible+1]=item; p.matchKeys[item.key]=true end
			end
			end
			for key in pairs(p.selected) do total=total+1; if not p.matchKeys[key] then hidden=hidden+1 end end
			p.visible=visible
			local pages=math.max(1,math.ceil(#visible/25)); p.page=math.min(p.page,pages)
			local pageStart=(p.page-1)*25
			local pageCount=math.min(25,#visible-pageStart)
			local first=math.floor(scroll:GetVerticalScroll()/48)+1
			local used=0
			for i=first,math.min(pageCount,first+5) do
				local item=visible[pageStart+i]; used=used+1
				if p.mode=="catalog" then AzerMind.EnrichCatalogItem(item) end
				local row=p.rows[used]
				if not row then
					row=CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate"); row:SetSize(24,24)
					row:SetHitRectInsets(0,-484,0,-20)
					row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(30,30); row.icon:SetPoint("TOPLEFT",30,-2)
					row.title=T.Label(row,"",68,-1); row.title:SetWidth(438); row.title:SetJustifyH("LEFT"); row.title:SetWordWrap(false)
					row.detail=T.Label(row,"",68,-22); row.detail:SetWidth(438); row.detail:SetJustifyH("LEFT"); row.detail:SetWordWrap(false); T.Color(row.detail,"SetTextColor","muted")
					row:SetScript("OnClick",function(self) p.selected[self.item.key]=self:GetChecked() or nil; if p.onlySelected then p.query=nil end; Render() end)
					local function ShowItemTooltip(self)
                        self.auctionExpanded = IsShiftKeyDown and IsShiftKeyDown() or false
						GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:ClearLines()
						Read(GameTooltip.SetHyperlink,GameTooltip,self.item.link)
						if p.mode=="catalog" then GameTooltip:AddLine(AzerMind.CatalogItemDetails(self.item.id),0.8,0.85,0.85,true) end
						local auction = AzerMind.AuctionItemDetails and AzerMind.AuctionItemDetails(self.item.id, not self.auctionExpanded)
						if auction then GameTooltip:AddLine(auction,0.8,0.85,0.85,true) end
						GameTooltip:Show()
                    end
                    row:SetScript("OnEnter",function(self)
                        ShowItemTooltip(self)
                        self:SetScript("OnUpdate",function(owner)
                            local expanded = IsShiftKeyDown and IsShiftKeyDown() or false
                            if GameTooltip:GetOwner() == owner and expanded ~= owner.auctionExpanded then ShowItemTooltip(owner) end
                        end)
                    end)
					row:RegisterForClicks("LeftButtonUp","RightButtonUp")
                    local select=row:GetScript("OnClick")
                    row:SetScript("OnClick",function(self,button) if button=="RightButton" then AzerMind.ShowSourceBrowser("item",self.item.id) else select(self) end end)
                    row:SetScript("OnLeave",function(self) self:SetScript("OnUpdate",nil); GameTooltip:Hide() end); p.rows[used]=row
				end
				row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*48)
				row.item=item; row:SetChecked(p.selected[item.key] or false); row.icon:SetTexture(item.icon or 134400)
				row.title:SetText(item.link..(item.count>1 and (" ×"..item.count) or ""))
				local slotName=_G[item.slot] or item.slot
				row.detail:SetText((item.subtype~="" and item.subtype or "Uncached type")..(slotName~="" and (" · "..slotName) or "").." · "..item.location)
				row:Show()
			end
			for i=used+1,#p.rows do p.rows[i]:Hide() end
			content:SetHeight(math.max(1,pageCount*48))
			p.pageLabel:SetText("Page "..p.page.." / "..pages)
			p.previous:SetEnabled(p.page>1); p.next:SetEnabled(p.page<pages)
			p.summary:SetText(total.." selected · "..hidden.." hidden by filters · "..#visible.." shown"..(#visible==0 and " · No matching items" or ""))
			p.insert:SetText("Add to message ("..total..")"); p.insert:SetEnabled(total>0 and total<=100)
			local cache=Cache(); p.bank:SetText(cache.updated and ("Bank · "..(bankOpen and "Live" or "Last updated "..cache.updated)) or "Open your bank to load its items.")
			for i,b in ipairs(categoryButtons) do T.Selected(b,p.category==i) end
			for name,b in pairs(locationButtons) do T.Selected(b,p.location==name) end
			if p.mode=="catalog" then
				p.bank:SetText(total>100 and "Choose up to 100 items per attachment." or "Rarity and slot filters require client-cached data.")
			end
			local unknown=0; for _,item in ipairs(p.items or {}) do if item.quality==nil then unknown=unknown+1 end end
			if unknown>0 and (p.rarity~=-1 or p.slot~="All") then
				p.bank:SetText(unknown.." items have unknown metadata and may be excluded by rarity/slot filters.")
			end
			if total>100 then p.bank:SetText("Choose up to 100 items per attachment.") end
			if p.minLevel and p.maxLevel and p.minLevel>p.maxLevel then p.bank:SetText("Required level: Min must not exceed Max.") end
            p.rendering=false
		end
		p.previous=Button("Previous",90,192,-492,function() p.page=math.max(1,p.page-1); scroll:SetVerticalScroll(0); Render() end)
		p.next=Button("Next",90,440,-492,function() p.page=p.page+1; scroll:SetVerticalScroll(0); Render() end)
		scroll:HookScript("OnVerticalScroll",function() if p.insert then Render() end end)
		for i,name in ipairs({"All","Equipped","Bags","Bank"}) do
			locationButtons[name]=Button(name,100,20+(i-1)*108,-148,function() p.location=name; scroll:SetVerticalScroll(0); Render() end)
		end
		local categoryScroll=CreateFrame("ScrollFrame","AzerMindItemCategoryScroll",p,"UIPanelScrollFrameTemplate")
        categoryScroll:SetPoint("TOPLEFT",20,-224); categoryScroll:SetSize(146,258)
        local categoryContent=CreateFrame("Frame",nil,categoryScroll); categoryContent:SetSize(132,#categories*24); categoryScroll:SetScrollChild(categoryContent)
        for i,category in ipairs(categories) do
            categoryButtons[i]=Button(category[1],132,0,-(i-1)*24,function() p.category=i; p.subclass=nil; p.subtypeSelector:SetValue("all","All"); scroll:SetVerticalScroll(0); Render() end)
			categoryButtons[i]:SetParent(categoryContent); categoryButtons[i]:ClearAllPoints(); categoryButtons[i]:SetPoint("TOPLEFT",0,-(i-1)*24); categoryButtons[i]:SetHeight(22)
		end
		local rarityOptions={{key=-1,label="All"}}
        for value=0,7 do rarityOptions[#rarityOptions+1]={key=value,label=_G["ITEM_QUALITY"..value.."_DESC"] or tostring(value)} end
        p.raritySelector=T.Selector(p,"Rarity",150,rarityOptions,-1,function(option) p.rarity=option.key; Render() end)
        p.raritySelector:SetPoint("TOPLEFT",20,-184); p.raritySelector:SetValue(-1,"All")
		T.Label(p,"Required level: Min / Max",500,-174)
        local function LevelInput(name,x,field)
            local input=T.SearchField(p,name,92,field=="minLevel" and "Min" or "Max")
            input.label:SetText(""); input:SetPoint("TOPLEFT",x,-192); input:SetNumeric(true); input:SetMaxLetters(3)
            input:SetScript("OnTextChanged",function(self) p[field]=tonumber(self:GetText()); Render() end)
            return input
        end
        p.minInput=LevelInput("AzerMindItemMinLevel",504,"minLevel")
        p.maxInput=LevelInput("AzerMindItemMaxLevel",628,"maxLevel")
        p.subtypeSelector=T.Selector(p,"Subtype",164,function()
            local options={{key="all",label="All"}}; local seen={}
            for _,item in ipairs(p.items or {}) do
                local key=tostring(item.classID)..":"..tostring(item.subclassID)
                if Category(item,categories[p.category]) and item.subclassID and not seen[key] then
                    seen[key]=true
                    local subtype=item.subtype~="" and item.subtype or ("Subclass "..item.subclassID)
                    options[#options+1]={key=key,label=(p.category==1 and item.kind~="" and (item.kind.." > ") or "")..subtype}
                end
            end
            table.sort(options,function(a,b) return tostring(a.key)<tostring(b.key) end)
            return options
        end,"all",function(option) p.subclass=option.key~="all" and option.key or nil; Render() end)
        p.subtypeSelector:SetPoint("TOPLEFT",20,-488)
		local slots={"All","INVTYPE_HEAD","INVTYPE_NECK","INVTYPE_SHOULDER","INVTYPE_CHEST","INVTYPE_WAIST","INVTYPE_LEGS","INVTYPE_FEET","INVTYPE_WRIST","INVTYPE_HAND","INVTYPE_FINGER","INVTYPE_TRINKET","INVTYPE_CLOAK","INVTYPE_WEAPON","INVTYPE_2HWEAPON","INVTYPE_WEAPONMAINHAND","INVTYPE_WEAPONOFFHAND","INVTYPE_HOLDABLE","INVTYPE_SHIELD","INVTYPE_RANGED","INVTYPE_RANGEDRIGHT"}
        local slotOptions={}
        for _,value in ipairs(slots) do slotOptions[#slotOptions+1]={key=value,label=_G[value] or value} end
        p.slotSelector=T.Selector(p,"Slot",164,slotOptions,"All",function(option) p.slot=option.key; Render() end)
        p.slotSelector:SetPoint("TOPLEFT",320,-184)
		Button("Reset filters",112,452,-148,function()
			p.location="All"; p.category=1; p.rarity=-1; p.slot="All"; p.level=false; p.onlySelected=false
			p.raritySelector:SetValue(-1,"All"); p.slotSelector:SetValue("All")
			p.minLevel=nil; p.maxLevel=nil; p.minInput:SetText(""); p.maxInput:SetText(""); p.subclass=nil; p.subtypeSelector:SetValue("all","All"); p.selectedToggle:SetValue(false)
			search:SetText(""); p.query=nil; Render()
		end)
		local divider=p:CreateTexture(nil,"BORDER")
		divider:SetHeight(1); divider:SetPoint("TOPLEFT",192,-452); divider:SetPoint("TOPRIGHT",-20,-452)
		T.Color(divider,"SetColorTexture","border")
		Button("Select all results",130,192,-460,function() for _,item in ipairs(p.visible) do p.selected[item.key]=true end; if p.onlySelected then p.query=nil end; Render() end)
		Button("Clear selection",130,330,-460,function() p.selected={}; if p.onlySelected then p.query=nil end; Render() end)
		p.selectedToggle=T.Toggle(p,"Show selected only",210,false,function(value) p.onlySelected=value; p.query=nil; Render() end); p.selectedToggle:SetPoint("TOPLEFT",468,-460)
		Button("Select page",164,572,-148,function()
			-- Replace the selection so items hidden by the current filters cannot
			-- accidentally ride along when selecting only equipment, bags, etc.
			for i=(p.page-1)*25+1,math.min(p.page*25,#p.visible) do p.selected[p.visible[i].key]=true end
			Render()
		end)
		p.insert=Button("Add to message (0)",174,566,-550,function()
			local chosen=0; for _ in pairs(p.selected) do chosen=chosen+1 end
            if chosen==0 then return end
			if chosen>100 then p.summary:SetText("Choose up to 100 items per attachment."); return end
			local lines={"--- Selected inventory items ---", "Inventory snapshot: "..date("%Y-%m-%d %H:%M")..". Only Equipped entries are worn."}
			for _,item in ipairs(p.items) do
				if p.selected[item.key] then
					if p.mode=="catalog" then AzerMind.EnrichCatalogItem(item) end
					lines[#lines+1]=item.location..": "..item.link.." ×"..item.count..(item.location=="Bank" and (" (bank snapshot: "..(Cache().updated or "unknown")..")") or "")
					if p.mode=="catalog" then lines[#lines+1]=AzerMind.CatalogItemDetails(item.id) end
					local auction = AzerMind.AuctionItemDetails and AzerMind.AuctionItemDetails(item.id)
					if auction then lines[#lines+1]=auction end
				end
			end
			lines[#lines+1]="--- End selected inventory items ---"
			local attachment=table.concat(lines,"\n")
			if #attachment>36000 then p.summary:SetText("This attachment is too large. Choose fewer items."); return end
			if AzerMind.AppendQuestDraft(attachment,p.chatId) then p:Hide() else p.summary:SetText("Conversation changed. Reopen Items to attach this selection.") end
		end)
		T.Primary(p.insert)
		T.Tooltip(p.insert,"Add items to message","Maximum 100 items per attachment. Adds to the draft; nothing is sent yet.")
        p:SetScript("OnHide",T.CloseChoiceMenu)
		Button("Cancel",90,468,-550,function() p:Hide() end)
		search:SetScript("OnTextChanged",function()
			p.searchVersion=(p.searchVersion or 0)+1; local version=p.searchVersion
			C_Timer.After(0.15,function() if p.insert and p:IsShown() and p.searchVersion==version then scroll:SetVerticalScroll(0); Render() end end)
		end)
		p.Refresh=function(metadataOnly)
			T.SourceSelection(p,p.mode)
            p.selectedToggle:SetValue(p.onlySelected)
            if not metadataOnly or p.rarity~=-1 or p.slot~="All" then p.query=nil end
			local err
			if p.mode=="catalog" then p.items,err=AzerMind.CatalogItemList() else p.items=AzerMind.OwnedItems() end
			p.items=p.items or {}
			if p.lastMode~=p.mode then scroll:SetVerticalScroll(0); p.lastMode=p.mode end
			T.Selected(tab,p.mode=="owned"); T.Selected(db,p.mode=="catalog")
			p.ownership={}
            for _,owned in ipairs(AzerMind.OwnedItems()) do
                if owned.id then p.ownership[owned.id]=p.ownership[owned.id] or {}; p.ownership[owned.id][owned.location]=true end
            end
            for _,b in pairs(locationButtons) do b:SetEnabled(true) end
			p.version:SetText(p.mode=="catalog" and (AzerMindCatalog and ("Forever snapshot · "..AzerMindCatalog.manifest.source.." "..AzerMindCatalog.manifest.version) or "Catalog unavailable") or "Equipment, bags and last bank snapshot")
            p.removedSelections=T.ReconcileSelection(p.selected,p.items,"key")
			Render()
            if p.removedSelections>0 then p.summary:SetText(p.removedSelections.." unavailable selections removed. "..p.summary:GetText()) end
			if err then p.summary:SetText(err) end
		end
	end
	if picker.chatId~=chat.id then picker.selections={}; picker.selectionSource=nil; picker.selected={} end
    picker.chatId=chat.id; picker:Show(); picker.Refresh()
end
local events=CreateFrame("Frame")
for _,event in ipairs({"BANKFRAME_OPENED","BANKFRAME_CLOSED","BAG_UPDATE_DELAYED","PLAYER_EQUIPMENT_CHANGED","GET_ITEM_INFO_RECEIVED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event)
	if event=="BANKFRAME_OPENED" then bankOpen=true; ScanBank()
	elseif event=="BANKFRAME_CLOSED" then bankOpen=false
	elseif event=="BAG_UPDATE_DELAYED" then ScanBank() end
	if picker and picker:IsShown() then picker.Refresh(event=="GET_ITEM_INFO_RECEIVED") end
end)
