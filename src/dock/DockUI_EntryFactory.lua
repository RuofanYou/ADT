-- DockUI_EntryFactory.lua
-- DockUI 条目/标题/装饰项创建工厂

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local API = ADT.API
local Mixin = API.Mixin
local CreateFrame = CreateFrame
local GetDBBool = ADT.GetDBBool

local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding

-- ============================================================================
-- 工具函数
-- ============================================================================

local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

local function CreateNewFeatureMark(button, smallDot)
    local newTag = button:CreateTexture(nil, "OVERLAY")
    newTag:SetTexture("Interface/AddOns/AdvancedDecorationTools/Art/CommandDock/NewFeatureTag", nil, nil, smallDot and "TRILINEAR" or "LINEAR")
    newTag:SetSize(16, 16)
    newTag:SetPoint("RIGHT", button, "LEFT", 0, 0)
    newTag:Hide()
    if smallDot then
        newTag:SetTexCoord(0.5, 1, 0, 1)
    else
        newTag:SetTexCoord(0, 0.5, 0, 1)
    end
    return newTag
end

-- ============================================================================
-- OptionToggle Mixin
-- ============================================================================

local OptionToggleMixin = {}

function OptionToggleMixin:OnEnter()
    self.Texture:SetVertexColor(1, 1, 1)
    local tooltip = GameTooltip
    tooltip:SetOwner(self, "ANCHOR_RIGHT")
    tooltip:SetText(SETTINGS, 1, 1, 1, 1)
    tooltip:Show()

    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if MainFrame and MainFrame.HighlightButton then
        local entry = self:GetParent()
        if entry then MainFrame:HighlightButton(entry) end
    end
end

function OptionToggleMixin:OnLeave()
    self:ResetVisual()
    GameTooltip:Hide()
end

function OptionToggleMixin:OnClick(button)
    if self.onClickFunc then
        self.onClickFunc(self, button)
    end
end

function OptionToggleMixin:SetOnClickFunc(onClickFunc, hasMovableWidget)
    self.onClickFunc = onClickFunc
    self.hasMovableWidget = hasMovableWidget
end

function OptionToggleMixin:ResetVisual()
    self.Texture:SetVertexColor(0.65, 0.65, 0.65)
end

function OptionToggleMixin:OnLoad()
    self:SetScript("OnEnter", self.OnEnter)
    self:SetScript("OnLeave", self.OnLeave)
    self:SetScript("OnClick", self.OnClick)
    self:ResetVisual()
end

-- ============================================================================
-- EntryButton Mixin
-- ============================================================================

local EntryButtonMixin = {}

function EntryButtonMixin:SetData(moduleData)
    self.Label:SetText(moduleData.name)
    self.dbKey = moduleData.dbKey
    self.virtual = moduleData.virtual
    self.data = moduleData
    self.NewTag:SetShown((not self.isChangelogButton) and moduleData.isNewFeature)
    self.OptionToggle:SetOnClickFunc(moduleData.optionToggleFunc, self.data and self.data.hasMovableWidget)
    self.hasOptions = moduleData.optionToggleFunc ~= nil
    
    if moduleData.type == 'dropdown' then
        self:UpdateDropdownLabel()
    end
    
    self:UpdateState()
    self:UpdateVisual()
end

function EntryButtonMixin:OnEnter()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if MainFrame and MainFrame.HighlightButton then MainFrame:HighlightButton(self) end
    self:UpdateVisual()
end

function EntryButtonMixin:OnLeave()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if MainFrame and MainFrame.HighlightButton then MainFrame:HighlightButton(nil) end
    self:UpdateVisual()
end

function EntryButtonMixin:OnEnable()
    self:UpdateVisual()
end

function EntryButtonMixin:OnDisable()
    self:UpdateVisual()
end

function EntryButtonMixin:OnClick(button)
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if self.dbKey and self.data then
        if self.data.type == 'dropdown' then
            -- 使用统一下拉菜单模块（单一权威）
            local options = self.data.options or {}
            local toggleFunc = self.data.toggleFunc
            ADT.DockUI.DropdownMenu:ShowMenu(self, options, self.dbKey, toggleFunc)
            return
        else
            local newState = not GetDBBool(self.dbKey)
            ADT.SetDBValue(self.dbKey, newState, true)
            if self.data.toggleFunc then self.data.toggleFunc(newState) end
            if newState then 
                if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.checkbox.on') end
            else 
                if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.checkbox.off') end 
            end
        end
    end

    if MainFrame and MainFrame.UpdateSettingsEntries then
        MainFrame:UpdateSettingsEntries()
    end
end

function EntryButtonMixin:UpdateDropdownLabel()
    if not self.data or self.data.type ~= 'dropdown' then return end
    local currentValue = ADT.GetDBValue(self.dbKey)
    local name = self.data.name or ""
    local displayText = name
    if self.data.options then
        for _, opt in ipairs(self.data.options) do
            if opt and opt.value == currentValue then
                displayText = name .. "：" .. (opt.text or tostring(opt.value))
                break
            end
        end
    end
    if displayText == name and type(self.data.valueToText) == 'function' then
        local ok, txt = pcall(self.data.valueToText, currentValue)
        if ok and txt and txt ~= "" then
            displayText = name .. "：" .. tostring(txt)
        end
    end
    self.Label:SetText(displayText)
end

function EntryButtonMixin:UpdateState()
    if self.virtual then
        self:Enable()
        self.OptionToggle:SetShown(self.hasOptions)
        if self.Box.SetAtlas then self.Box:SetAtlas("checkbox-minimal") end
        if self.Check then self.Check:Hide() end
        return
    end
    
    if self.data and self.data.type == 'readonly' then
        if self.Box then self.Box:Hide() end
        if self.Check then self.Check:Hide() end
        self.OptionToggle:Hide()
        self:Disable()
        SetTextColor(self.Label, Def.TextColorDisabled)
        return
    end

    if self.data and self.data.type == 'number' then
        if self.Box then self.Box:Hide() end
        if self.Check then self.Check:Hide() end
        self.OptionToggle:Hide()
        self:Enable()
        local v = tonumber(ADT.GetDBValue(self.dbKey)) or tonumber(self.data.default) or 0
        local fmt = self.data.format or "%s：%s"
        self.Label:SetText(string.format(fmt, self.data.name, tostring(v)))
        self:SetScript("OnClick", function(_, btn)
            local minv = tonumber(self.data.min) or -math.huge
            local maxv = tonumber(self.data.max) or math.huge
            local step = tonumber(self.data.step) or 1
            if IsShiftKeyDown and IsShiftKeyDown() then
                local mul = tonumber(self.data.shiftStepMul) or 5
                step = step * mul
            end
            local nv = v
            if btn == "RightButton" then nv = v - step else nv = v + step end
            if nv < minv then nv = minv elseif nv > maxv then nv = maxv end
            v = nv
            ADT.SetDBValue(self.dbKey, v, true)
            self.Label:SetText(string.format(fmt, self.data.name, tostring(v)))
        end)
        return
    end

    if self.data and self.data.type == 'dropdown' then
        if self.Box then self.Box:Hide() end
        if self.Check then self.Check:Hide() end
        self.OptionToggle:Hide()
        self:Enable()
        SetTextColor(self.Label, { 0.922, 0.871, 0.761 })
        self:UpdateDropdownLabel()
        return
    else
        self.Box:Show()
    end

    local disabled
    if self.parentDBKey and not GetDBBool(self.parentDBKey) then
        disabled = true
    end

    if GetDBBool(self.dbKey) then
        if self.Box.SetAtlas then self.Box:SetAtlas("checkbox-minimal") end
        if self.Check then self.Check:Show() end
        self.OptionToggle:SetShown(self.hasOptions)
    else
        if self.Box.SetAtlas then self.Box:SetAtlas("checkbox-minimal") end
        if self.Check then self.Check:Hide() end
        self.OptionToggle:Hide()
    end

    if disabled then
        self:Disable()
    else
        self:Enable()
    end
end

function EntryButtonMixin:EnsureTextHighlight() return nil end
function EntryButtonMixin:HideTextHighlight() end
function EntryButtonMixin:UpdateTextHighlight(_) end

function EntryButtonMixin:UpdateVisual()
    if self:IsEnabled() then
        SetTextColor(self.Label, Def.TextColorNormal)
    else
        SetTextColor(self.Label, Def.TextColorDisabled)
    end
end

function EntryButtonMixin:GetDesiredWidth()
    local w = 0
    if self.Label and self.Label.GetStringWidth then
        w = math.ceil(self.Label:GetStringWidth() or 0)
    end
    return w + 56
end

-- ============================================================================
-- CreateSettingsEntry
-- ============================================================================

local function CreateSettingsEntry(parent)
    local f = CreateFrame("Button", nil, parent, "ADTSettingsPanelEntryTemplate")
    Mixin(f, EntryButtonMixin)
    if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    f:SetMotionScriptsWhileDisabled(true)
    f:SetScript("OnEnter", f.OnEnter)
    f:SetScript("OnLeave", f.OnLeave)
    f:SetScript("OnEnable", f.OnEnable)
    f:SetScript("OnDisable", f.OnDisable)
    f:SetScript("OnClick", f.OnClick)
    SetTextColor(f.Label, Def.TextColorNormal)
    if f.Label and f.Label.SetMaxLines then f.Label:SetMaxLines(1) end
    if f.Label and f.Label.SetWordWrap then f.Label:SetWordWrap(false) end

    f.Box.useTrilinearFilter = false
    if f.Box.SetAtlas then f.Box:SetAtlas("checkbox-minimal") end
    
    local check = f:CreateTexture(nil, "OVERLAY")
    f.Check = check
    check:SetAtlas("common-icon-checkmark-yellow")
    check:SetSize(20, 20)
    check:SetPoint("CENTER", f.Box, "CENTER", 0, 0)
    check:Hide()

    f.NewTag = CreateNewFeatureMark(f)

    Mixin(f.OptionToggle, OptionToggleMixin)
    f.OptionToggle:OnLoad()
    f.OptionToggle.Texture:Hide()

    return f
end

-- ============================================================================
-- Header Mixin & CreateSettingsHeader
-- ============================================================================

local HeaderMixin = {}

function HeaderMixin:SetText(text)
    self.Label:SetText(text)
end

function HeaderMixin:SetLeftPadding(pixels)
    local x = tonumber(pixels) or 8
    if self.Label then
        self.Label:ClearAllPoints()
        self.Label:SetPoint("BOTTOMLEFT", self, "LEFT", x, 5)
    end
    if self.Divider then
        self.Divider:ClearAllPoints()
        self.Divider:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 6)
        self.Divider:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 6)
    end
end

local function CreateSettingsHeader(parent)
    local f = CreateFrame("Frame", nil, parent, "ADTSettingsPanelHeaderTemplate")
    Mixin(f, HeaderMixin)
    SetTextColor(f.Label, Def.TextColorNonInteractable)

    if f.Left then f.Left:Hide() end
    if f.Right then f.Right:Hide() end

    local divider = f:CreateTexture(nil, "ARTWORK")
    f.Divider = divider
    divider:SetAtlas("house-upgrade-header-divider-horz")
    divider:SetHeight(2)

    local defaultHeaderLeft = GetRightPadding()
    f:SetLeftPadding(defaultHeaderLeft)
    
    function f:GetDesiredWidth()
        local w = 0
        if self.Label and self.Label.GetStringWidth then
            w = math.ceil(self.Label:GetStringWidth() or 0)
        end
        return w + 2 * GetRightPadding()
    end
    return f
end

-- ============================================================================
-- DecorItem Mixin & CreateDecorItemEntry
-- ============================================================================

local DecorItemMixin = {}

local function GetDecorListStyle(categoryKey)
    local cfg = ADT.GetHousingCFG and ADT.GetHousingCFG() or nil
    local dl  = cfg and cfg.DockDecorList or nil
    if not dl then
        return { countRightInset = 6, nameToCountGap = 8, countWidth = 32 }
    end
    local common = dl.Common or {}
    local style
    if categoryKey == 'Clipboard' then
        style = dl.Clipboard or {}
    elseif categoryKey == 'History' then
        style = dl.Recent or {}
    else
        style = {}
    end
    return {
        countRightInset = tonumber(style.countRightInset) or tonumber(common.countRightInset) or 6,
        nameToCountGap  = tonumber(style.nameToCountGap)  or tonumber(common.nameToCountGap)  or 8,
        countWidth      = tonumber(style.countWidth)      or tonumber(common.countWidth)      or 32,
    }
end

function DecorItemMixin:SetData(item, categoryInfo)
    self.decorID = item.decorID
    self.categoryInfo = categoryInfo
    self.itemData = item
    
    self.Icon:SetTexture(item.icon or 134400)
    
    local entryInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID 
        and C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, item.decorID, true)
    local available = 0
    local displayName = item.name or string.format(ADT.L["Decor #%d"], tonumber(item.decorID) or 0)
    
    if entryInfo then
        available = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
        if not item.name and entryInfo.name then
            displayName = entryInfo.name
        end
        if not item.icon and entryInfo.iconTexture then
            self.Icon:SetTexture(entryInfo.iconTexture)
        end
    end
    
    if item.count and item.count > 1 then
        displayName = string.format("[x%d] %s", item.count, displayName)
    end
    
    self.Name:SetText(displayName)
    self.Count:SetText(tostring(available))
    self.available = available

    do
        local catKey = categoryInfo and categoryInfo.key or nil
        local sty = GetDecorListStyle(catKey)
        if self.Count and self.Count.ClearAllPoints then
            self.Count:ClearAllPoints()
            self.Count:SetPoint("RIGHT", self, "RIGHT", -sty.countRightInset, 0)
            if self.Count.SetWidth then self.Count:SetWidth(sty.countWidth) end
        end
        if self.Name and self.Name.ClearAllPoints and self.Icon then
            self.Name:ClearAllPoints()
            self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 8, 0)
            self.Name:SetPoint("RIGHT", self.Count, "LEFT", -sty.nameToCountGap, 0)
        end
    end
    
    self.isDisabled = available <= 0
    self:UpdateVisual()
end

function DecorItemMixin:UpdateVisual()
    if self.isDisabled then
        self.Name:SetTextColor(0.5, 0.5, 0.5)
        if self.Icon.SetDesaturated then self.Icon:SetDesaturated(true) end
    else
        SetTextColor(self.Name, Def.TextColorNormal)
        if self.Icon.SetDesaturated then self.Icon:SetDesaturated(false) end
    end
end

function DecorItemMixin:GetDesiredWidth()
    local w = 0
    if self.Name and self.Name.GetStringWidth then
        w = math.ceil(self.Name:GetStringWidth() or 0)
    end
    local catKey = self.categoryInfo and self.categoryInfo.key or nil
    local sty = GetDecorListStyle(catKey)
    local leftFixed = 40
    local rightFixed = sty.countWidth + sty.nameToCountGap + sty.countRightInset
    return w + leftFixed + rightFixed
end

function DecorItemMixin:OnEnter()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not self.isDisabled then
        self.Highlight:Show()
        SetTextColor(self.Name, Def.TextColorHighlight)
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.Name:GetText() or "", 1, 1, 1)
    if self.available > 0 then
        GameTooltip:AddLine(string.format(ADT.L["Stock: %d"], self.available), 0, 1, 0)
    else
        GameTooltip:AddLine(ADT.L["Stock: 0 (Unavailable)"], 1, 0.2, 0.2)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ADT.L["Left Click: Place"], 0.8, 0.8, 0.8)
    if self.categoryInfo and self.categoryInfo.key == 'Clipboard' then
        GameTooltip:AddLine(ADT.L["Right Click: Remove from Clipboard"], 1, 0.4, 0.4)
    end
    GameTooltip:Show()
end

function DecorItemMixin:OnLeave()
    self.Highlight:Hide()
    self:UpdateVisual()
    GameTooltip:Hide()
end

function DecorItemMixin:OnClick(button)
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if self.isDisabled and button ~= "RightButton" then return end
    if self.categoryInfo and self.categoryInfo.onItemClick then
        self.categoryInfo.onItemClick(self.decorID, button)
        C_Timer.After(0.1, function()
            if MainFrame and MainFrame.currentDecorCategory then
                MainFrame:ShowDecorListCategory(MainFrame.currentDecorCategory)
            end
        end)
    end
end

local function CreateDecorItemEntry(parent)
    local f = CreateFrame("Button", nil, parent, "ADTDecorItemEntryTemplate")
    Mixin(f, DecorItemMixin)
    f:SetSize(200, 36)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnEnter", f.OnEnter)
    f:SetScript("OnLeave", f.OnLeave)
    f:SetScript("OnClick", f.OnClick)
    SetTextColor(f.Name, Def.TextColorNormal)
    if f.Name and f.Name.SetMaxLines then f.Name:SetMaxLines(1) end
    if f.Name and f.Name.SetWordWrap then f.Name:SetWordWrap(false) end
    return f
end

-- ============================================================================
-- 导出
-- ============================================================================

ADT.DockUI.CreateSettingsEntry = CreateSettingsEntry
ADT.DockUI.CreateSettingsHeader = CreateSettingsHeader
ADT.DockUI.CreateDecorItemEntry = CreateDecorItemEntry
ADT.DockUI.CreateNewFeatureMark = CreateNewFeatureMark
