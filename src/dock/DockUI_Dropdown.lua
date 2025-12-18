-- DockUI_Dropdown.lua
-- DockUI 自定义下拉菜单系统

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local API = ADT.API
local Mixin = API.Mixin
local CreateFrame = CreateFrame
local DisableSharpening = API.DisableSharpening

local Def = ADT.DockUI.Def

-- ============================================================================
-- 工具函数
-- ============================================================================

local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

-- ============================================================================
-- 下拉菜单系统
-- ============================================================================

local ADTDropdownMenu
do
    local MENU_WIDTH = 160
    local ITEM_HEIGHT = 20
    local PADDING = 6
    
    -- 菜单项 Mixin
    local DropdownItemMixin = {}
    
    function DropdownItemMixin:OnEnter()
        self.Highlight:Show()
        SetTextColor(self.Text, Def.TextColorHighlight)
    end
    
    function DropdownItemMixin:OnLeave()
        self.Highlight:Hide()
        SetTextColor(self.Text, { 0.922, 0.871, 0.761 })
    end
    
    function DropdownItemMixin:OnClick()
        if self.onClickFunc then
            self.onClickFunc()
        end
        ADTDropdownMenu:Hide()
    end
    
    function DropdownItemMixin:SetSelected(selected)
        self.selected = selected
        if self.Check then
            self.Check:SetShown(selected)
        end
    end
    
    function DropdownItemMixin:SetText(text)
        self.Text:SetText(text)
    end
    
    -- 创建单个菜单项
    local function CreateDropdownItem(parent)
        local f = CreateFrame("Button", nil, parent)
        Mixin(f, DropdownItemMixin)
        f:SetSize(MENU_WIDTH - 2 * PADDING, ITEM_HEIGHT)
        
        -- 高亮背景
        f.Highlight = f:CreateTexture(nil, "BACKGROUND")
        f.Highlight:SetAllPoints(true)
        f.Highlight:SetColorTexture(1, 0.82, 0, 0.15)
        f.Highlight:Hide()
        
        -- 单选按钮
        f.Radio = f:CreateTexture(nil, "ARTWORK")
        f.Radio:SetSize(14, 14)
        f.Radio:SetPoint("LEFT", f, "LEFT", 4, 0)
        f.Radio:SetAtlas("checkbox-minimal")
        DisableSharpening(f.Radio)
        f.Check = f:CreateTexture(nil, "OVERLAY")
        f.Check:SetPoint("CENTER", f.Radio, "CENTER", 0, 0)
        f.Check:SetSize(12, 12)
        f.Check:SetAtlas("common-icon-checkmark-yellow")
        f.Check:Hide()
        
        -- 文本
        f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.Text:SetPoint("LEFT", f.Radio, "RIGHT", 4, 0)
        f.Text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        f.Text:SetJustifyH("LEFT")
        SetTextColor(f.Text, { 0.922, 0.871, 0.761 })
        
        f:SetScript("OnEnter", f.OnEnter)
        f:SetScript("OnLeave", f.OnLeave)
        f:SetScript("OnClick", f.OnClick)
        
        return f
    end
    
    -- 创建下拉菜单主框架
    ADTDropdownMenu = CreateFrame("Frame", "ADTDropdownMenuFrame", UIParent)
    ADTDropdownMenu:SetFrameStrata("TOOLTIP")
    ADTDropdownMenu:SetFrameLevel(100)
    ADTDropdownMenu:Hide()
    ADTDropdownMenu:EnableMouse(true)
    ADTDropdownMenu:SetClampedToScreen(true)
    
    -- 背景
    local bg = ADTDropdownMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("housing-basic-panel-background")
    bg:SetVertexColor(1, 1, 1)
    ADTDropdownMenu.Background = bg
    
    -- 边框
    local borderSize = 3
    local borders = {}
    for i = 1, 4 do
        borders[i] = ADTDropdownMenu:CreateTexture(nil, "BORDER")
        borders[i]:SetColorTexture(0.6, 0.5, 0.3)
    end
    borders[1]:SetPoint("TOPLEFT", ADTDropdownMenu, "TOPLEFT", 0, 0)
    borders[1]:SetPoint("TOPRIGHT", ADTDropdownMenu, "TOPRIGHT", 0, 0)
    borders[1]:SetHeight(borderSize)
    borders[2]:SetPoint("BOTTOMLEFT", ADTDropdownMenu, "BOTTOMLEFT", 0, 0)
    borders[2]:SetPoint("BOTTOMRIGHT", ADTDropdownMenu, "BOTTOMRIGHT", 0, 0)
    borders[2]:SetHeight(borderSize)
    borders[3]:SetPoint("TOPLEFT", ADTDropdownMenu, "TOPLEFT", 0, 0)
    borders[3]:SetPoint("BOTTOMLEFT", ADTDropdownMenu, "BOTTOMLEFT", 0, 0)
    borders[3]:SetWidth(borderSize)
    borders[4]:SetPoint("TOPRIGHT", ADTDropdownMenu, "TOPRIGHT", 0, 0)
    borders[4]:SetPoint("BOTTOMRIGHT", ADTDropdownMenu, "BOTTOMRIGHT", 0, 0)
    borders[4]:SetWidth(borderSize)
    ADTDropdownMenu.Borders = borders
    
    ADTDropdownMenu.items = {}
    ADTDropdownMenu.itemPool = {}
    
    function ADTDropdownMenu:AcquireItem()
        local item = table.remove(self.itemPool)
        if not item then
            item = CreateDropdownItem(self)
        end
        item:Show()
        return item
    end
    
    function ADTDropdownMenu:ReleaseAllItems()
        for _, item in ipairs(self.items) do
            item:Hide()
            table.insert(self.itemPool, item)
        end
        wipe(self.items)
    end
    
    function ADTDropdownMenu:ShowMenu(owner, options, dbKey, toggleFunc)
        ADT.DebugPrint("[Dropdown] ShowMenu called, dbKey=" .. tostring(dbKey) .. ", options count=" .. tostring(#options))
        self:ReleaseAllItems()
        
        local numOptions = #options
        local menuHeight = numOptions * ITEM_HEIGHT + 2 * PADDING
        
        self:SetSize(MENU_WIDTH, menuHeight)
        self.owner = owner
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
        
        local currentValue = ADT.GetDBValue(dbKey)
        for i, opt in ipairs(options) do
            local item = self:AcquireItem()
            item:SetText(opt.text)
            item:SetSelected(currentValue == opt.value)
            item:SetPoint("TOPLEFT", self, "TOPLEFT", PADDING, -PADDING - (i - 1) * ITEM_HEIGHT)
            
            item.onClickFunc = function()
                ADT.SetDBValue(dbKey, opt.value, true)
                if toggleFunc then
                    toggleFunc(opt.value)
                end
                if owner.UpdateDropdownLabel then
                    owner:UpdateDropdownLabel()
                end
                local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
                if MainFrame and MainFrame.UpdateSettingsEntries then
                    MainFrame:UpdateSettingsEntries()
                end
            end
            
            table.insert(self.items, item)
        end
        
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel( max( (owner and owner:GetFrameLevel() or 0) + 10, 100) )
        self:Show()

        self.waitRelease = true
        self:SetScript("OnUpdate", function()
            if self.waitRelease then
                if not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then
                    self.waitRelease = false
                end
                return
            end
            if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                and not self:IsMouseOver()
                and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
    end
    
    ADTDropdownMenu:SetScript("OnHide", function(self)
        self:ReleaseAllItems()
        self:SetScript("OnUpdate", nil)
        self.owner = nil
        self.waitRelease = nil
    end)

    -- ESC 关闭
    if ADTDropdownMenu.GetName then
        local name = ADTDropdownMenu:GetName()
        if name and UISpecialFrames then
            local found
            for i, v in ipairs(UISpecialFrames) do if v == name then found = true break end end
            if not found then table.insert(UISpecialFrames, name) end
        end
    end
end

-- 导出
ADT.DockUI.DropdownMenu = ADTDropdownMenu
