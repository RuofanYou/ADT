-- 1:1 复制自 Referrence/Plumber/Modules/ControlCenter/SettingsPanelNew.lua
-- 精简版：删除 ChangelogTab、TabButton 切换、Minimize/Maximize
-- 仅保留核心 GUI：左侧分类、中间列表、右侧预览

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local L = ADT.L
local API = ADT.API
local ControlCenter = ADT.ControlCenter
local GetDBBool = ADT.GetDBBool

local Mixin = API.Mixin
local CreateFrame = CreateFrame
local DisableSharpening = API.DisableSharpening


local Def = {
    TextureFile = "Interface/AddOns/AdvancedDecorationTools/Art/ControlCenter/SettingsPanel.png",
    ButtonSize = 28,
    WidgetGap = 14,
    PageHeight = 380,  -- 缩小高度：约10行文本+标题+边距
    CategoryGap = 20,  -- 缩小分类间距
    TabButtonHeight = 40,

    TextColorNormal = {215/255, 192/255, 163/255},
    TextColorHighlight = {1, 1, 1},
    TextColorNonInteractable = {148/255, 124/255, 102/255},
    TextColorDisabled = {0.5, 0.5, 0.5},
    TextColorReadable = {163/255, 157/255, 147/255},
}


local MainFrame = CreateFrame("Frame", nil, UIParent, "ADTSettingsPanelLayoutTemplate")
ControlCenter.SettingsPanel = MainFrame
do
    local frameKeys = {"LeftSection", "RightSection", "CentralSection", "SideTab", "TabButtonContainer", "ModuleTab", "ChangelogTab"}
    for _, key in ipairs(frameKeys) do
        MainFrame[key] = MainFrame.FrameContainer[key]
    end
end
local SearchBox
local CategoryHighlight
local ActiveCategoryInfo = {}


local function SkinObjects(obj, texture)
    if obj.SkinnableObjects then
        for _, _obj in ipairs(obj.SkinnableObjects) do
            SkinObjects(_obj, texture)
        end
    elseif obj.SetTexture then
        if obj.useTrilinearFilter then
            obj:SetTexture(texture, nil, nil, "TRILINEAR")
        else
            obj:SetTexture(texture)
        end
    end
end

local function SetTexCoord(obj, x1, x2, y1, y2)
    obj:SetTexCoord(x1/1024, x2/1024, y1/1024, y2/1024)
end

local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

local function CreateNewFeatureMark(button, smallDot)
    local newTag = button:CreateTexture(nil, "OVERLAY")
    newTag:SetTexture("Interface/AddOns/AdvancedDecorationTools/Art/ControlCenter/NewFeatureTag", nil, nil, smallDot and "TRILINEAR" or "LINEAR")
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

local function CreateDivider(frame, width)
    local div = frame:CreateTexture(nil, "OVERLAY")
    div:SetSize(width, 24)
    div:SetTexture(Def.TextureFile)
    DisableSharpening(div)
    SetTexCoord(div, 416, 672, 16, 64)
    return div
end


local MakeFadingObject
do
    local FadeMixin = {}

    local function FadeIn_OnUpdate(self, elapsed)
        self.alpha = self.alpha + self.fadeSpeed * elapsed
        if self.alpha >= self.fadeInAlpha then
            self:SetScript("OnUpdate", nil)
            self.alpha = self.fadeInAlpha
        end
        self:SetAlpha(self.alpha)
    end

    local function FadeOut_OnUpdate(self, elapsed)
        self.alpha = self.alpha - self.fadeSpeed * elapsed
        if self.alpha <= self.fadeOutAlpha then
            self:SetScript("OnUpdate", nil)
            self.alpha = self.fadeOutAlpha
            if self.hideAfterFadeOut then
                self:Hide()
            end
        end
        self:SetAlpha(self.alpha)
    end

    function FadeMixin:FadeIn(instant)
        if instant then
            self.alpha = 1
            self:SetScript("OnUpdate", nil)
        else
            self.alpha = self:GetAlpha()
            self:SetScript("OnUpdate", FadeIn_OnUpdate)
        end
        self:Show()
    end

    function FadeMixin:FadeOut()
        self.alpha = self:GetAlpha()
        self:SetScript("OnUpdate", FadeOut_OnUpdate)
    end

    function FadeMixin:SetFadeInAlpha(alpha)
        if alpha <= 0.099 then
            self.fadeInAlpha = 1
        else
            self.fadeInAlpha = alpha
        end
    end

    function FadeMixin:SetFadeOutAlpha(alpha)
        if alpha <= 0.01 then
            self.fadeOutAlpha = 0
            self.hideAfterFadeOut = true
        else
            self.fadeOutAlpha = alpha
            self.hideAfterFadeOut = false
        end
    end

    function FadeMixin:SetFadeSpeed(fadeSpeed)
        self.fadeSpeed = fadeSpeed
    end

    function MakeFadingObject(obj)
        Mixin(obj, FadeMixin)
        obj:SetFadeOutAlpha(0)
        obj:SetFadeInAlpha(1)
        obj:SetFadeSpeed(5)
        obj.alpha = 1
    end
end


local CreateSearchBox
do
    local SearchBoxMixin = {}
    local StringTrim = API.StringTrim

    function SearchBoxMixin:SetTexture(texture)
        SkinObjects(self, texture)
    end

    function SearchBoxMixin:SetInstruction(text)
        self.Instruction:SetText(text)
    end

    function SearchBoxMixin:OnEnable()
        self:UpdateVisual()
    end

    function SearchBoxMixin:OnDisable()
        self:UpdateVisual()
    end

    function SearchBoxMixin:UpdateVisual()
        if self:IsEnabled() then
            if self:HasFocus() then
                self:SetTextColor(1, 1, 1)
            elseif self:IsMouseMotionFocus() then
                self:SetTextColor(1, 1, 1)
            else
                SetTextColor(self, Def.TextColorNormal)
            end
            self.Left:SetDesaturated(false)
            self.Center:SetDesaturated(false)
            self.Right:SetDesaturated(false)
            self.Left:SetVertexColor(1, 1, 1)
            self.Center:SetVertexColor(1, 1, 1)
            self.Right:SetVertexColor(1, 1, 1)
        else
            self:SetTextColor(0.5, 0.5, 0.5)
            self.Left:SetDesaturated(true)
            self.Center:SetDesaturated(true)
            self.Right:SetDesaturated(true)
            self.Left:SetVertexColor(0.5, 0.5, 0.5)
            self.Center:SetVertexColor(0.5, 0.5, 0.5)
            self.Right:SetVertexColor(0.5, 0.5, 0.5)
        end
    end

    function SearchBoxMixin:OnEscapePressed()
        self:ClearFocus()
    end

    function SearchBoxMixin:OnEnterPressed()
        self:ClearFocus()
    end

    function SearchBoxMixin:OnTextChanged(userInput)
        if self.hasOnTextChangeCallback then
            self.t = 0
            self:SetScript("OnUpdate", self.OnUpdate)
        end
        self.ResetButton:SetShown(self:HasText())
    end

    function SearchBoxMixin:OnUpdate(elapsed)
        self.t = self.t + elapsed
        if self.t > 0.2 then
            self.t = nil
            self:SetScript("OnUpdate", nil)
            if self.searchFunc then
                if self:IsNumeric() then
                    self.searchFunc(self, self:GetNumber())
                else
                    self.searchFunc(self, StringTrim(self:GetText()))
                end
            end
        end
    end

    function SearchBoxMixin:SetSearchFunc(searchFunc)
        self.searchFunc = searchFunc
        self.hasOnTextChangeCallback = searchFunc ~= nil
    end

    function SearchBoxMixin:OnHide()
        self.t = nil
        self:SetScript("OnUpdate", nil)
    end

    function SearchBoxMixin:UpdateText()
        local text = self:GetText()
        text = StringTrim(text)
        self:SetText(text or "")
        if text then
            self.Instruction:Hide()
            self.ResetButton:Show()
        else
            self.Instruction:Show()
            self.ResetButton:Hide()
        end
    end

    function SearchBoxMixin:OnEditFocusLost()
        self.Magnifier:SetVertexColor(0.5, 0.5, 0.5)
        self:UpdateText()
        self:UnlockHighlight()
        self:UpdateVisual()
    end

    function SearchBoxMixin:OnEditFocusGained()
        self.Instruction:Hide()
        self.Magnifier:SetVertexColor(1, 1, 1)
        self:LockHighlight()
        self:UpdateVisual()
    end

    function SearchBoxMixin:ClearText()
        self:SetText("")
        if not self:HasFocus() then
            self.Instruction:Show()
        end
    end

    function SearchBoxMixin:HasStickyFocus()
        return self:IsMouseMotionFocus() or self.ResetButton:IsMouseMotionFocus()
    end

    local function ResetButton_OnEnter(self)
        SetTexCoord(self.Texture, 904, 944, 0, 40)
    end

    local function ResetButton_OnLeave(self)
        SetTexCoord(self.Texture, 864, 904, 0, 40)
    end

    local function ResetButton_OnClick(self)
        self:GetParent():ClearText()
        ADT.LandingPageUtil.PlayUISound("CheckboxOff")
    end


    function CreateSearchBox(parent)
        local f = CreateFrame("EditBox", nil, parent, "ADTEditBoxArtTemplate")
        Mixin(f, SearchBoxMixin)

        f:SetTexture(Def.TextureFile)

        SetTexCoord(f.Left, 0, 32, 0, 80)
        SetTexCoord(f.Center, 32, 160, 0, 80)
        SetTexCoord(f.Right, 160, 192, 0, 80)

        SetTexCoord(f.Magnifier, 984, 1024, 0, 40)
        f.Magnifier:SetVertexColor(0.5, 0.5, 0.5)

        f:SetInstruction(SEARCH)

        f:SetSize(168, Def.ButtonSize)

        f:SetScript("OnEditFocusGained", f.OnEditFocusGained)
        f:SetScript("OnEditFocusLost", f.OnEditFocusLost)
        f:SetScript("OnEscapePressed", f.OnEscapePressed)
        f:SetScript("OnEnterPressed", f.OnEnterPressed)
        f:SetScript("OnEnable", f.OnEnable)
        f:SetScript("OnDisable", f.OnDisable)
        f:SetScript("OnHide", f.OnHide)
        f:SetScript("OnTextChanged", f.OnTextChanged)

        f.ResetButton:SetScript("OnEnter", ResetButton_OnEnter)
        f.ResetButton:SetScript("OnLeave", ResetButton_OnLeave)
        f.ResetButton:SetScript("OnClick", ResetButton_OnClick)
        SetTexCoord(f.ResetButton.Texture, 864, 904, 0, 40)

        f:SetSearchFunc(function(self, text)
            MainFrame:RunSearch(text)
        end)

        return f
    end
end


local CreateCategoryButton
do
    local CategoryButtonMixin = {}

    function CategoryButtonMixin:OnEnter()
        MainFrame:HighlightButton(self)
        SetTextColor(self.Label, Def.TextColorHighlight)
    end

    function CategoryButtonMixin:OnLeave()
        MainFrame:HighlightButton()
        SetTextColor(self.Label, Def.TextColorNormal)
    end

    function CategoryButtonMixin:SetCategory(key, text, anyNewFeature)
        self.Label:SetText(text)
        self.cateogoryName = string.lower(text)
        self.categoryKey = key

        self.NewTag:ClearAllPoints()
        self.NewTag:SetPoint("CENTER", self, "LEFT", 0, 0)
        self.NewTag:SetShown(anyNewFeature)
    end

    function CategoryButtonMixin:ShowCount(count)
        if count and count > 0 then
            self.Count:SetText(count)
            self.CountContainer:FadeIn()
        else
            self.CountContainer:FadeOut()
        end
    end

    function CategoryButtonMixin:OnClick()
        local cat = ControlCenter:GetCategoryByKey(self.categoryKey)
        if cat and cat.categoryType == 'decorList' then
            -- 装饰列表分类：切换到装饰列表视图
            MainFrame:ShowDecorListCategory(self.categoryKey)
            ADT.LandingPageUtil.PlayUISound("ScrollBarStep")
        elseif cat and cat.categoryType == 'about' then
            -- 信息分类：显示关于信息
            MainFrame:ShowAboutCategory(self.categoryKey)
            ADT.LandingPageUtil.PlayUISound("ScrollBarStep")
        else
            -- 设置类分类：先恢复设置视图，再滚动到对应位置
            -- 如果当前在装饰列表视图，先切换回设置视图
            if MainFrame.currentDecorCategory or MainFrame.currentAboutCategory then
                MainFrame:ShowSettingsView()
            end
            -- 延迟一帧确保 ActiveCategoryInfo 已更新
            C_Timer.After(0.01, function()
                if ActiveCategoryInfo[self.categoryKey] then
                    MainFrame.ModuleTab.ScrollView:ScrollTo(ActiveCategoryInfo[self.categoryKey].scrollOffset)
                end
            end)
            ADT.LandingPageUtil.PlayUISound("ScrollBarStep")
        end
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', self.categoryKey) end
        MainFrame:HighlightButton(self)
    end

    function CategoryButtonMixin:OnMouseDown()
        self.Label:SetPoint("LEFT", self, "LEFT", self.labelOffset + 1, -1)
    end

    function CategoryButtonMixin:OnMouseUp()
        self:ResetOffset()
    end

    function CategoryButtonMixin:ResetOffset()
        self.Label:SetPoint("LEFT", self, "LEFT", self.labelOffset, 0)
    end

    function CreateCategoryButton(parent)
        local f = CreateFrame("Button", nil, parent)
        Mixin(f, CategoryButtonMixin)
        f:SetSize(120, 26)
        f.labelOffset = 9
        f.Label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.Label:SetJustifyH("LEFT")
        f.Label:SetPoint("LEFT", f, "LEFT", 9, 0)
        SetTextColor(f.Label, Def.TextColorNormal)

        local CountContainer = CreateFrame("Frame", nil, f)
        f.CountContainer = CountContainer
        CountContainer:SetSize(Def.ButtonSize, Def.ButtonSize)
        CountContainer:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        CountContainer:Hide()
        CountContainer:SetAlpha(0)
        MakeFadingObject(CountContainer)
        CountContainer:SetFadeSpeed(8)

        f.Count = CountContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.Count:SetJustifyH("RIGHT")
        f.Count:SetPoint("RIGHT", CountContainer, "RIGHT", -9, 0)
        SetTextColor(f.Count, Def.TextColorNonInteractable)

        f:SetScript("OnEnter", f.OnEnter)
        f:SetScript("OnLeave", f.OnLeave)
        f:SetScript("OnClick", f.OnClick)
        f:SetScript("OnMouseDown", f.OnMouseDown)
        f:SetScript("OnMouseUp", f.OnMouseUp)

        f.NewTag = CreateNewFeatureMark(f, true)

        return f
    end
end


local OptionToggleMixin = {}
do
    function OptionToggleMixin:OnEnter()
        self.Texture:SetVertexColor(1, 1, 1)
        local tooltip = GameTooltip
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
        tooltip:SetText(SETTINGS, 1, 1, 1, 1)
        tooltip:Show()
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
end


local CreateSettingsEntry
do
    local EntryButtonMixin = {}

    function EntryButtonMixin:SetData(moduleData)
        self.Label:SetText(moduleData.name)
        self.dbKey = moduleData.dbKey
        self.virtual = moduleData.virtual
        self.data = moduleData
        self.NewTag:SetShown((not self.isChangelogButton) and moduleData.isNewFeature)
        self.OptionToggle:SetOnClickFunc(moduleData.optionToggleFunc, self.data and self.data.hasMovableWidget)
        self.hasOptions = moduleData.optionToggleFunc ~= nil
        self:UpdateState()
        self:UpdateVisual()
    end

    function EntryButtonMixin:OnEnter()
        MainFrame:HighlightButton(self)
        self:UpdateVisual()
        if not self.isChangelogButton then
            MainFrame:ShowFeaturePreview(self.data, self.parentDBKey)
        end
    end

    function EntryButtonMixin:OnLeave()
        MainFrame:HighlightButton()
        self:UpdateVisual()
    end

    function EntryButtonMixin:OnEnable()
        self:UpdateVisual()
    end

    function EntryButtonMixin:OnDisable()
        self:UpdateVisual()
    end

    function EntryButtonMixin:OnClick()
        if self.dbKey and self.data and self.data.toggleFunc then
            local newState = not GetDBBool(self.dbKey)
            ADT.SetDBValue(self.dbKey, newState, true)
            self.data.toggleFunc(newState)
            if newState then
                ADT.LandingPageUtil.PlayUISound("CheckboxOn")
            else
                ADT.LandingPageUtil.PlayUISound("CheckboxOff")
            end
        end

        MainFrame:UpdateSettingsEntries()
    end

    function EntryButtonMixin:UpdateState()
        if self.virtual then
            self:Enable()
            self.OptionToggle:SetShown(self.hasOptions)
            SetTexCoord(self.Box, 736, 784, 64, 112)
            return
        end

        local disabled
        if self.parentDBKey and not GetDBBool(self.parentDBKey) then
            disabled = true
        end

        if GetDBBool(self.dbKey) then
            if disabled then
                SetTexCoord(self.Box, 784, 832, 64, 112)
            else
                SetTexCoord(self.Box, 736, 784, 16, 64)
            end
            self.OptionToggle:SetShown(self.hasOptions)
        else
            if disabled then
                SetTexCoord(self.Box, 784, 832, 16, 64)
            else
                SetTexCoord(self.Box, 688, 736, 16, 64)
            end
            self.OptionToggle:Hide()
        end

        if disabled then
            self:Disable()
        else
            self:Enable()
        end
    end

    function EntryButtonMixin:UpdateVisual()
        if self:IsEnabled() then
            if self:IsMouseMotionFocus() then
                SetTextColor(self.Label, Def.TextColorHighlight)
                SetTexCoord(self.OptionToggle.Texture, 904, 944, 40, 80)
            else
                SetTextColor(self.Label, Def.TextColorNormal)
                SetTexCoord(self.OptionToggle.Texture, 864, 904, 40, 80)
            end
        else
            SetTextColor(self.Label, Def.TextColorDisabled)
        end
    end

    function CreateSettingsEntry(parent)
        local f = CreateFrame("Button", nil, parent, "ADTSettingsPanelEntryTemplate")
        Mixin(f, EntryButtonMixin)
        f:SetMotionScriptsWhileDisabled(true)
        f:SetScript("OnEnter", f.OnEnter)
        f:SetScript("OnLeave", f.OnLeave)
        f:SetScript("OnEnable", f.OnEnable)
        f:SetScript("OnDisable", f.OnDisable)
        f:SetScript("OnClick", f.OnClick)
        SetTextColor(f.Label, Def.TextColorNormal)

        f.Box.useTrilinearFilter = true
        SkinObjects(f, Def.TextureFile)

        f.NewTag = CreateNewFeatureMark(f)

        Mixin(f.OptionToggle, OptionToggleMixin)
        f.OptionToggle:OnLoad()

        return f
    end
end


local CreateSettingsHeader
do
    local HeaderMixin = {}

    function HeaderMixin:SetText(text)
        self.Label:SetText(text)
    end


    function CreateSettingsHeader(parent)
        local f = CreateFrame("Frame", nil, parent, "ADTSettingsPanelHeaderTemplate")
        Mixin(f, HeaderMixin)
        SetTextColor(f.Label, Def.TextColorNonInteractable)

        SkinObjects(f, Def.TextureFile)
        SetTexCoord(f.Left, 416, 456, 80, 120)
        SetTexCoord(f.Right, 456, 736, 80, 120)

        return f
    end
end


-- 装饰项按钮（用于临时板和历史记录列表）
local CreateDecorItemEntry
do
    local DecorItemMixin = {}

    function DecorItemMixin:SetData(item, categoryInfo)
        self.decorID = item.decorID
        self.categoryInfo = categoryInfo
        self.itemData = item
        
        -- 设置图标
        self.Icon:SetTexture(item.icon or 134400)
        
        -- 获取库存数量
        local entryInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID 
            and C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, item.decorID, true)
        local available = 0
        local displayName = item.name or ("装饰 #" .. tostring(item.decorID))
        
        if entryInfo then
            available = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
            if not item.name and entryInfo.name then
                displayName = entryInfo.name
            end
            if not item.icon and entryInfo.iconTexture then
                self.Icon:SetTexture(entryInfo.iconTexture)
            end
        end
        
        -- 临时板显示计数前缀
        if item.count and item.count > 1 then
            displayName = string.format("[x%d] %s", item.count, displayName)
        end
        
        self.Name:SetText(displayName)
        self.Count:SetText(tostring(available))
        self.available = available
        
        -- 禁用状态
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

    function DecorItemMixin:OnEnter()
        if not self.isDisabled then
            self.Highlight:Show()
            SetTextColor(self.Name, Def.TextColorHighlight)
        end
        -- 右侧预览
        MainFrame:ShowDecorPreview(self.itemData, self.available)
        -- Tooltip
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.Name:GetText() or "", 1, 1, 1)
        if self.available > 0 then
            GameTooltip:AddLine("库存：" .. self.available, 0, 1, 0)
        else
            GameTooltip:AddLine("库存：0（不可放置）", 1, 0.2, 0.2)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("左键：开始放置", 0.8, 0.8, 0.8)
        if self.categoryInfo and self.categoryInfo.key == 'Clipboard' then
            GameTooltip:AddLine("右键：从临时板移除", 1, 0.4, 0.4)
        end
        GameTooltip:Show()
    end

    function DecorItemMixin:OnLeave()
        self.Highlight:Hide()
        self:UpdateVisual()
        GameTooltip:Hide()
    end

    function DecorItemMixin:OnClick(button)
        if self.isDisabled and button ~= "RightButton" then return end
        if self.categoryInfo and self.categoryInfo.onItemClick then
            self.categoryInfo.onItemClick(self.decorID, button)
            -- 刷新列表
            C_Timer.After(0.1, function()
                if MainFrame.currentDecorCategory then
                    MainFrame:ShowDecorListCategory(MainFrame.currentDecorCategory)
                end
            end)
        end
    end

    function CreateDecorItemEntry(parent)
        local f = CreateFrame("Button", nil, parent, "ADTDecorItemEntryTemplate")
        Mixin(f, DecorItemMixin)
        f:SetSize(200, 36)
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        f:SetScript("OnEnter", f.OnEnter)
        f:SetScript("OnLeave", f.OnLeave)
        f:SetScript("OnClick", f.OnClick)
        SetTextColor(f.Name, Def.TextColorNormal)
        return f
    end
end


local CreateSelectionHighlight
do
    local SelectionHighlightMixin = {}

    function SelectionHighlightMixin:FadeIn()
        self.isFading = true
        self:SetAlpha(0)
        self.t = 0
        self.alpha = 0
        self:SetScript("OnUpdate", self.OnUpdate)
        self:Show()
    end

    function SelectionHighlightMixin:OnUpdate(elapsed)
        self.t = self.t + elapsed

        if self.isFading then
            self.alpha = self.alpha + 5 * elapsed
            if self.alpha > 1 then
                self.alpha = 1
                self.isFading = nil
                self:SetScript("OnUpdate", nil)
            end
            self:SetAlpha(self.alpha)
        end
    end

    function SelectionHighlightMixin:OnHide()
        self:Hide()
        self:ClearAllPoints()
    end

    function CreateSelectionHighlight(parent)
        local f = CreateFrame("Frame", nil, parent, "ADTSettingsAnimSelectionTemplate")
        Mixin(f, SelectionHighlightMixin)

        SkinObjects(f, Def.TextureFile)

        SetTexCoord(f.Left, 0, 32, 80, 160)
        SetTexCoord(f.Center, 32, 160, 80, 160)
        SetTexCoord(f.Right, 160, 192, 80, 160)

        f.d = 0.6
        f:Hide()
        f:SetScript("OnHide", f.OnHide)

        return f
    end
end


do  -- Left Section
    function MainFrame:HighlightButton(button)
        CategoryHighlight:Hide()
        CategoryHighlight:ClearAllPoints()
        if button then
            CategoryHighlight:SetPoint("LEFT", button, "LEFT", 0, 0)
            CategoryHighlight:SetPoint("RIGHT", button, "RIGHT", 0, 0)
            CategoryHighlight:SetParent(button)
            CategoryHighlight:FadeIn()
        end
    end
end


do  -- Right Section (已移除，保留函数但添加空检查)
    function MainFrame:ShowFeaturePreview(moduleData, parentDBKey)
        -- 右侧预览区已移除，函数保留但不执行任何操作
        if not self.FeatureDescription or not self.FeaturePreview then return end
        if not moduleData then return end
        local desc = moduleData.description
        local additonalDesc = moduleData.descriptionFunc and moduleData.descriptionFunc() or nil
        if additonalDesc then
            if desc then
                desc = desc.."\n\n"..additonalDesc
            else
                desc = additonalDesc
            end
        end
        self.FeatureDescription:SetText(desc)
        self.FeaturePreview:SetTexture("Interface/AddOns/AdvancedDecorationTools/Art/ControlCenter/Preview_"..(parentDBKey or moduleData.dbKey))
    end

    -- 显示装饰项预览（右侧预览区已移除，函数保留但不执行任何操作）
    function MainFrame:ShowDecorPreview(itemData, available)
        -- 右侧预览区已移除，不执行任何操作
        if not self.FeatureDescription or not self.FeaturePreview then return end
        if not itemData then return end
        -- 设置预览图标
        local icon = itemData.icon or 134400
        local entryInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID
            and C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, itemData.decorID, true)
        if entryInfo and entryInfo.iconTexture then
            icon = entryInfo.iconTexture
        end
        self.FeaturePreview:SetTexture(icon)
        
        -- 构建描述文本
        local name = itemData.name or (entryInfo and entryInfo.name) or ("装饰 #" .. tostring(itemData.decorID))
        local desc = name .. "\n\n"
        if available and available > 0 then
            desc = desc .. "|cff00ff00库存：" .. available .. "|r\n\n"
        else
            desc = desc .. "|cffff3333库存：0（不可放置）|r\n\n"
        end
        desc = desc .. "|cffaaaaaa左键：开始放置|r"
        if self.currentDecorCategory == 'Clipboard' then
            desc = desc .. "\n|cffff6666右键：从临时板移除|r"
        end
        self.FeatureDescription:SetText(desc)
    end
end


do  -- Search
    function MainFrame:RunSearch(text)
        if text and text ~= "" then
            self.listGetter = function()
                return ControlCenter:GetSearchResult(text)
            end
            self:RefreshFeatureList()
            for _, button in self.primaryCategoryPool:EnumerateActive() do
                if ActiveCategoryInfo[button.categoryKey] then
                    button:FadeIn()
                    button:ShowCount(ActiveCategoryInfo[button.categoryKey].numModules)
                else
                    button:FadeOut()
                    button:ShowCount(false)
                end
            end
        else
            -- 注意：不能直接赋值为 ControlCenter.GetSortedModules（那样会丢失冒号调用的 self）
            -- 绑定为闭包，确保以冒号语义调用，避免 self 为 nil。
            self.listGetter = function()
                return ControlCenter:GetSortedModules()
            end
            self:RefreshFeatureList()
            for _, button in self.primaryCategoryPool:EnumerateActive() do
                button:FadeIn()
                button:ShowCount(false)
            end
        end
    end
end


do  -- Central
    function MainFrame:RefreshFeatureList()
        local top, bottom
        local n = 0
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local content = {}

        local buttonHeight = Def.ButtonSize
        local categoryGap = Def.CategoryGap
        local buttonGap = 0
        local subOptionOffset = Def.ButtonSize
        local offsetX = 0

        ActiveCategoryInfo = {}
        self.firstModuleData = nil

        local sortedModule = self.listGetter and self.listGetter() or ControlCenter:GetSortedModules()

        for index, categoryInfo in ipairs(sortedModule) do
            -- 跳过装饰列表分类和信息分类（它们有自己的渲染方式）
            if categoryInfo.categoryType == 'decorList' or categoryInfo.categoryType == 'about' then
                -- 不渲染这些分类的内容，仅在 ActiveCategoryInfo 中标记
                ActiveCategoryInfo[categoryInfo.key] = {
                    scrollOffset = 0,
                    numModules = 0,
                }
            else
                n = n + 1
                top = offsetY
                bottom = offsetY + buttonHeight + buttonGap

                ActiveCategoryInfo[categoryInfo.key] = {
                    scrollOffset = top - fromOffsetY,
                    numModules = categoryInfo.numModules,
                }

                content[n] = {
                    dataIndex = n,
                    templateKey = "Header",
                    setupFunc = function(obj)
                        obj:SetText(categoryInfo.categoryName)
                        -- 确保纹理可见（对象池复用时可能被隐藏）
                        if obj.Left then obj.Left:Show() end
                        if obj.Right then obj.Right:Show() end
                        obj.Label:SetJustifyH("LEFT")
                    end,
                    top = top,
                    bottom = bottom,
                    offsetX = offsetX,
                }
                offsetY = bottom

                if n == 1 then
                    self.firstModuleData = categoryInfo.modules[1]
                end

            for _, data in ipairs(categoryInfo.modules) do
                n = n + 1
                top = offsetY
                bottom = offsetY + buttonHeight + buttonGap
                content[n] = {
                    dataIndex = n,
                    templateKey = "Entry",
                    setupFunc = function(obj)
                        obj.parentDBKey = nil
                        obj:SetData(data)
                    end,
                    top = top,
                    bottom = bottom,
                    offsetX = offsetX,
                }
                offsetY = bottom

                if data.subOptions then
                    for _, v in ipairs(data.subOptions) do
                        n = n + 1
                        top = offsetY
                        bottom = offsetY + buttonHeight + buttonGap
                        content[n] = {
                            dataIndex = n,
                            templateKey = "Entry",
                            setupFunc = function(obj)
                                obj.parentDBKey = data.dbKey
                                obj:SetData(v)
                            end,
                            top = top,
                            bottom = bottom,
                            offsetX = offsetX + 0.5*subOptionOffset,
                        }
                        offsetY = bottom
                    end
                end
            end
            offsetY = offsetY + categoryGap
            end -- end of else (非装饰列表分类)
        end

        local retainPosition = true
        self.ModuleTab.ScrollView:SetContent(content, retainPosition)

        if self.firstModuleData then
            self:ShowFeaturePreview(self.firstModuleData)
        end
    end

    function MainFrame:RefreshCategoryList()
        self.primaryCategoryPool:ReleaseAll()
        for index, categoryInfo in ipairs(ControlCenter:GetSortedModules()) do
            local categoryButton = self.primaryCategoryPool:Acquire()
            categoryButton:SetCategory(categoryInfo.key, categoryInfo.categoryName, categoryInfo.anyNewFeature)
            categoryButton:SetPoint("TOPLEFT", self.LeftSection, self.primaryCategoryPool.offsetX, self.primaryCategoryPool.leftListFromY - (index - 1) * Def.ButtonSize)
            
            -- 装饰列表分类显示数量角标
            if categoryInfo.categoryType == 'decorList' then
                local count = ControlCenter:GetDecorListCount(categoryInfo.key)
                categoryButton:ShowCount(count > 0 and count or nil)
            end
        end
    end

    function MainFrame:UpdateSettingsEntries()
        self.ModuleTab.ScrollView:CallObjectMethod("Entry", "UpdateState")
    end

    -- 显示装饰列表分类（临时板或最近放置）
    function MainFrame:ShowDecorListCategory(categoryKey)
        local cat = ControlCenter:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'decorList' then return end
        
        self.currentDecorCategory = categoryKey
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
        
        local list = cat.getListData and cat.getListData() or {}
        local content = {}
        local n = 0
        local buttonHeight = 36 -- 装饰项按钮高度
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local buttonGap = 2
        local offsetX = 0
        
        -- 添加标题
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(cat.categoryName)
                -- 确保纹理可见
                if obj.Left then obj.Left:Show() end
                if obj.Right then obj.Right:Show() end
                obj.Label:SetJustifyH("LEFT")
            end,
            top = offsetY,
            bottom = offsetY + Def.ButtonSize,
            offsetX = offsetX,
        }
        offsetY = offsetY + Def.ButtonSize
        
        -- 添加装饰项或空列表提示
        if #list == 0 then
            -- 空列表：用普通 Header 显示一行提示
            n = n + 1
            local emptyTop = offsetY
            local emptyBottom = offsetY + Def.ButtonSize
            content[n] = {
                dataIndex = n,
                templateKey = "Header",
                setupFunc = function(obj)
                    -- 注意：emptyText 可能包含换行符，这里只取第一行
                    local text = cat.emptyText or "列表为空"
                    local firstLine = text:match("^([^\n]*)")
                    obj:SetText(firstLine or text)
                    SetTextColor(obj.Label, Def.TextColorDisabled)
                    -- 确保纹理可见
                    if obj.Left then obj.Left:Show() end
                    if obj.Right then obj.Right:Show() end
                    obj.Label:SetJustifyH("LEFT")
                end,
                top = emptyTop,
                bottom = emptyBottom,
                offsetX = offsetX,
            }
            -- 如果有第二行提示，继续添加
            if cat.emptyText and cat.emptyText:find("\n") then
                local secondLine = cat.emptyText:match("\n(.*)$")
                if secondLine and secondLine ~= "" then
                    n = n + 1
                    offsetY = emptyBottom
                    content[n] = {
                        dataIndex = n,
                        templateKey = "Header",
                        setupFunc = function(obj)
                            obj:SetText(secondLine)
                            SetTextColor(obj.Label, Def.TextColorDisabled)
                            -- 确保纹理可见
                            if obj.Left then obj.Left:Show() end
                            if obj.Right then obj.Right:Show() end
                            obj.Label:SetJustifyH("LEFT")
                        end,
                        top = offsetY,
                        bottom = offsetY + Def.ButtonSize,
                        offsetX = offsetX,
                    }
                end
            end
        else
            -- 有装饰项：渲染列表
            for i, item in ipairs(list) do
                n = n + 1
                local top = offsetY
                local bottom = offsetY + buttonHeight + buttonGap
                local capCat = cat -- 捕获当前分类信息
                local capItem = item -- 捕获当前项
                content[n] = {
                    dataIndex = n,
                    templateKey = "DecorItem",
                    setupFunc = function(obj)
                        obj:SetData(capItem, capCat)
                    end,
                    top = top,
                    bottom = bottom,
                    offsetX = offsetX,
                }
                offsetY = bottom
            end
        end
        
        self.ModuleTab.ScrollView:SetContent(content, false)
        
        -- 显示第一个装饰项的预览
        if #list > 0 then
            local firstItem = list[1]
            local entryInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID
                and C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, firstItem.decorID, true)
            local available = 0
            if entryInfo then
                available = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
            end
            self:ShowDecorPreview(firstItem, available)
        else
            -- 空列表时显示提示
            self.FeaturePreview:SetTexture(134400) -- 问号图标
            self.FeatureDescription:SetText(cat.emptyText or "列表为空")
        end
    end

    -- 返回设置列表视图
    function MainFrame:ShowSettingsView()
        self.currentDecorCategory = nil
        self.currentAboutCategory = nil
        self:RefreshFeatureList()
    end

    -- 显示信息分类（关于插件）
    function MainFrame:ShowAboutCategory(categoryKey)
        local cat = ControlCenter:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'about' then return end
        
        self.currentDecorCategory = nil
        self.currentAboutCategory = categoryKey
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
        
        local content = {}
        local n = 0
        local buttonHeight = Def.ButtonSize
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local offsetX = 0
        
        -- 添加标题（保留分隔线）
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(cat.categoryName)
                -- 确保标题的分隔线可见
                if obj.Left then obj.Left:Show() end
                if obj.Right then obj.Right:Show() end
                obj.Label:SetJustifyH("LEFT") -- 标题左对齐
            end,
            top = offsetY,
            bottom = offsetY + Def.ButtonSize,
            offsetX = offsetX,
        }
        offsetY = offsetY + Def.ButtonSize * 2
        
        -- 添加信息文本（隐藏分隔线，居中显示）
        if cat.getInfoText then
            local infoText = cat.getInfoText()
            -- 按换行符拆分
            for line in infoText:gmatch("[^\n]+") do
                n = n + 1
                content[n] = {
                    dataIndex = n,
                    templateKey = "Header",
                    setupFunc = function(obj)
                        obj:SetText(line)
                        obj.Label:SetJustifyH("CENTER") -- 内容居中
                        -- 隐藏分隔线纹理
                        if obj.Left then obj.Left:Hide() end
                        if obj.Right then obj.Right:Hide() end
                    end,
                    top = offsetY,
                    bottom = offsetY + buttonHeight,
                    offsetX = offsetX,
                }
                offsetY = offsetY + buttonHeight
            end
        end
        
        self.ModuleTab.ScrollView:SetContent(content, false)
    end
end


local function CreateUI()
    local pageHeight = Def.PageHeight
    
    -- 紧凑布局：左侧固定宽度，中间动态宽度
    local sideSectionWidth = 130  -- 左侧：5个汉字(约75px) + 边距 + 数量角标
    local centralSectionWidth = 340  -- 中间：图标 + 长装饰名称(如"小型锯齿奥格瑞玛栅栏") + 数量
    
    MainFrame:SetSize(sideSectionWidth + centralSectionWidth, pageHeight)
    MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    MainFrame:SetToplevel(true)
    
    -- 窗口拖动功能
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    MainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ADT and ADT.SaveFramePosition then
            ADT.SaveFramePosition("SettingsPanelPos", self)
        end
    end)
    MainFrame:SetClampedToScreen(true)
    
    MainFrame.FrameContainer:EnableMouse(true)
    MainFrame.FrameContainer:EnableMouseMotion(true)
    MainFrame.FrameContainer:SetScript("OnMouseWheel", function(self, delta) end)



    local baseFrameLevel = MainFrame:GetFrameLevel()

    local LeftSection = MainFrame.LeftSection
    local CentralSection = MainFrame.CentralSection
    local RightSection = MainFrame.RightSection
    local Tab1 = MainFrame.ModuleTab

    LeftSection:SetWidth(sideSectionWidth)
    
    -- 修复：不隐藏 RightSection，而是将 CentralSection 的右边直接锚定到 MainFrame
    -- 这样可以避免 XML 中定义的锚点导致的布局问题
    RightSection:SetWidth(0)
    RightSection:ClearAllPoints()
    RightSection:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", 0, 0)
    RightSection:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    
    -- 重设 CentralSection 的右边锚点
    CentralSection:ClearAllPoints()
    CentralSection:SetPoint("TOPLEFT", LeftSection, "TOPRIGHT", 0, 0)
    CentralSection:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)


    -- LeftSection
    do
        -- 暂时隐藏搜索功能，保留代码方便以后恢复
        --[[
        SearchBox = CreateSearchBox(Tab1)
        SearchBox:SetPoint("TOPLEFT", LeftSection, "TOPLEFT", Def.WidgetGap, -Def.WidgetGap)
        SearchBox:SetWidth(sideSectionWidth - 2 * Def.WidgetGap)
        --]]


        -- 隐藏搜索框后，分类列表从顶部开始
        local leftListFromY = Def.WidgetGap

        -- 隐藏搜索框后不需要分隔线
        --[[
        local DivH = CreateDivider(Tab1, sideSectionWidth - 0.5*Def.WidgetGap)
        DivH:SetPoint("CENTER", LeftSection, "TOP", 0, -leftListFromY)
        leftListFromY = leftListFromY + Def.WidgetGap
        --]]
        local categoryButtonWidth = sideSectionWidth - 2*Def.WidgetGap

        local function Category_Create()
            local obj = CreateCategoryButton(Tab1)
            obj:SetSize(categoryButtonWidth, Def.ButtonSize)
            MakeFadingObject(obj)
            obj:SetFadeInAlpha(1)
            obj:SetFadeOutAlpha(0.5)
            obj.Label:SetWidth(categoryButtonWidth - 2 * obj.labelOffset - 14)
            return obj
        end

        local function Category_Acquire(obj)
            obj:FadeIn(true)
            obj:ResetOffset()
        end

        MainFrame.primaryCategoryPool = ADT.LandingPageUtil.CreateObjectPool(Category_Create, Category_Acquire)
        MainFrame.primaryCategoryPool.leftListFromY = -leftListFromY
        MainFrame.primaryCategoryPool.offsetX = Def.WidgetGap


        CategoryHighlight = CreateSelectionHighlight(Tab1)
        CategoryHighlight:SetSize(categoryButtonWidth, Def.ButtonSize)


        -- 6-piece Background
        local function CreatePiece(point, relativeTo, relativePoint, offsetX, offsetY, l, r, t, b)
            local tex = MainFrame.SideTab:CreateTexture(nil, "BORDER")
            tex:SetTexture(Def.TextureFile)
            tex:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
            SetTexCoord(tex, l, r, t, b)
            DisableSharpening(tex)
            return tex
        end

        local r1 = CreatePiece("TOP", LeftSection, "TOPRIGHT", 0, 0,    280, 360, 176, 240)
        r1:SetSize(40, 32)
        local r3 = CreatePiece("BOTTOM", LeftSection, "BOTTOMRIGHT", 0, 0,    280, 360, 832, 896)
        r3:SetSize(40, 32)
        local r2 = CreatePiece("TOPLEFT", r1, "BOTTOMLEFT", 0, 0,    280, 360, 240, 832)
        r2:SetPoint("BOTTOMRIGHT", r3, "TOPRIGHT", 0, 0)

        local l1 = CreatePiece("TOPLEFT", LeftSection, "TOPLEFT", 0, 0,    0, 280, 176, 240)
        l1:SetPoint("BOTTOMRIGHT", r1, "BOTTOMLEFT", 0, 0)
        local l3 = CreatePiece("BOTTOMLEFT", LeftSection, "BOTTOMLEFT", 0, 0,    0, 280, 832, 896)
        l3:SetPoint("TOPRIGHT", r3, "TOPLEFT", 0, 0)
        local l2 = CreatePiece("TOPLEFT", l1, "BOTTOMLEFT", 0, 0,    0, 280, 240, 832)
        l2:SetPoint("BOTTOMRIGHT", l3, "TOPRIGHT", 0, 0)
    end


    do  -- RightSection
        local previewSize = sideSectionWidth - 2*Def.WidgetGap

        local preview = Tab1:CreateTexture(nil, "OVERLAY")
        MainFrame.FeaturePreview = preview
        preview:SetSize(previewSize, previewSize)
        preview:SetPoint("TOP", RightSection, "TOP", 0, -Def.WidgetGap)

        local mask = Tab1:CreateMaskTexture(nil, "OVERLAY")
        mask:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, 0)
        mask:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", 0, 0)
        mask:SetTexture("Interface/AddOns/AdvancedDecorationTools/Art/ControlCenter/PreviewMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        preview:AddMaskTexture(mask)


        local description = Tab1:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        MainFrame.FeatureDescription = description
        SetTextColor(description, Def.TextColorReadable)
        description:SetJustifyH("LEFT")
        description:SetJustifyV("TOP")
        description:SetSpacing(4)
        local visualOffset = 2
        description:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", visualOffset, -Def.WidgetGap -visualOffset)
        description:SetPoint("BOTTOMRIGHT", RightSection, "BOTTOMRIGHT", -visualOffset -Def.WidgetGap, Def.WidgetGap)
        description:SetShadowColor(0, 0, 0)
        description:SetShadowOffset(1, -1)
    end


    do  -- CentralSection
        local Background = CentralSection:CreateTexture(nil, "BACKGROUND")
        Background:SetTexture("Interface/AddOns/AdvancedDecorationTools/Art/ControlCenter/SettingsPanelBackground")
        Background:SetPoint("TOPLEFT", CentralSection, "TOPLEFT", -8, 0)
        -- 修复：背景只覆盖 CentralSection，不延伸到被隐藏的右侧区域
        Background:SetPoint("BOTTOMRIGHT", CentralSection, "BOTTOMRIGHT", 0, 0)


        local ScrollBar = ControlCenter.CreateScrollBarWithDynamicSize(Tab1)
        ScrollBar:SetPoint("TOP", CentralSection, "TOPRIGHT", 0, -0.5*Def.WidgetGap)
        ScrollBar:SetPoint("BOTTOM", CentralSection, "BOTTOMRIGHT", 0, 0.5*Def.WidgetGap)
        ScrollBar:SetFrameLevel(20)
        MainFrame.ModuleTab.ScrollBar = ScrollBar
        ScrollBar:UpdateThumbRange()


        local ScrollView = API.CreateScrollView(Tab1, ScrollBar)
        MainFrame.ModuleTab.ScrollView = ScrollView
        ScrollBar.ScrollView = ScrollView
        ScrollView:SetPoint("TOPLEFT", CentralSection, "TOPLEFT", 0, -2)
        ScrollView:SetPoint("BOTTOMRIGHT", CentralSection, "BOTTOMRIGHT", 0, 2)
        ScrollView:SetStepSize(Def.ButtonSize * 2)
        ScrollView:OnSizeChanged()
        ScrollView:EnableMouseBlocker(true)
        ScrollView:SetBottomOvershoot(Def.CategoryGap)
        ScrollView:SetAlwaysShowScrollBar(true)
        ScrollView:SetShowNoContentAlert(true)
        ScrollView:SetNoContentAlertText(CATALOG_SHOP_NO_SEARCH_RESULTS or "")


        local centerButtonWidth = API.Round(centralSectionWidth - 2*Def.ButtonSize)
        Def.centerButtonWidth = centerButtonWidth


        local function EntryButton_Create()
            local obj = CreateSettingsEntry(ScrollView)
            obj:SetSize(centerButtonWidth, Def.ButtonSize)
            return obj
        end

        ScrollView:AddTemplate("Entry", EntryButton_Create)


        local function Header_Create()
            local obj = CreateSettingsHeader(ScrollView)
            obj:SetSize(centerButtonWidth, Def.ButtonSize)
            return obj
        end

        ScrollView:AddTemplate("Header", Header_Create)


        -- 装饰项模板（用于临时板和最近放置列表）
        local function DecorItem_Create()
            local obj = CreateDecorItemEntry(ScrollView)
            obj:SetSize(centerButtonWidth, 36)
            return obj
        end

        ScrollView:AddTemplate("DecorItem", DecorItem_Create)
    end


    local NineSlice = ADT.LandingPageUtil.CreateExpansionThemeFrame(MainFrame.FrameContainer, 10)
    MainFrame.NineSlice = NineSlice
    NineSlice:CoverParent(-24)
    NineSlice.Background:Hide()
    NineSlice:SetUsingParentLevel(false)
    NineSlice:SetFrameLevel(baseFrameLevel + 20)
    NineSlice:ShowCloseButton(true)
    NineSlice:SetCloseButtonOwner(MainFrame)


    -- 打开时恢复到上次选中的分类/视图
    function MainFrame:HighlightCategoryByKey(key)
        if not key or not self.primaryCategoryPool then return end
        for _, button in self.primaryCategoryPool:EnumerateActive() do
            if button and button.categoryKey == key then
                self:HighlightButton(button)
                break
            end
        end
    end

    Tab1:SetScript("OnShow", function()
        local key = (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey')) or MainFrame.currentDecorCategory or MainFrame.currentAboutCategory
        local cat = key and ControlCenter:GetCategoryByKey(key) or nil
        if cat and cat.categoryType == 'decorList' then
            MainFrame:ShowDecorListCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'about' then
            MainFrame:ShowAboutCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        else
            MainFrame:RefreshFeatureList()
            if key then
                C_Timer.After(0.01, function()
                    if ActiveCategoryInfo[key] then
                        MainFrame.ModuleTab.ScrollView:ScrollTo(ActiveCategoryInfo[key].scrollOffset)
                    end
                    MainFrame:HighlightCategoryByKey(key)
                end)
            end
        end
    end)

    -- 注册数据变化回调，实时刷新 GUI
    -- Clipboard 数据变化时刷新
    if ADT.Clipboard then
        local origOnChanged = ADT.Clipboard.OnChanged
        ADT.Clipboard.OnChanged = function(self)
            if origOnChanged then origOnChanged(self) end
            -- 如果当前显示的是临时板分类，则刷新列表
            if MainFrame:IsShown() and MainFrame.currentDecorCategory == 'Clipboard' then
                MainFrame:ShowDecorListCategory('Clipboard')
            end
            -- 刷新分类列表的数量角标
            MainFrame:RefreshCategoryList()
        end
    end

    -- History 数据变化时刷新
    if ADT.History then
        local origOnHistoryChanged = ADT.History.OnHistoryChanged
        ADT.History.OnHistoryChanged = function(self)
            if origOnHistoryChanged then origOnHistoryChanged(self) end
            -- 如果当前显示的是最近放置分类，则刷新列表
            if MainFrame:IsShown() and MainFrame.currentDecorCategory == 'History' then
                MainFrame:ShowDecorListCategory('History')
            end
            -- 刷新分类列表的数量角标
            MainFrame:RefreshCategoryList()
        end
    end
end

function MainFrame:UpdateLayout()
    local frameWidth = math.floor(self:GetWidth() + 0.5)
    if frameWidth == self.frameWidth then
        return
    end
    self.frameWidth = frameWidth

    self.ModuleTab.ScrollView:OnSizeChanged()
    if self.ModuleTab.ScrollBar.OnSizeChanged then
        self.ModuleTab.ScrollBar:OnSizeChanged()
    end
end


function MainFrame:ShowUI(mode)
    if CreateUI then
        CreateUI()
        CreateUI = nil

        ControlCenter:UpdateCurrentSortMethod()
        self:RefreshCategoryList()
    end

    mode = mode or "standalone"
    self.mode = mode
    self.NineSlice:ShowCloseButton(mode ~= "blizzard")
    self:UpdateLayout()
    if ADT and ADT.RestoreFramePosition then
        ADT.RestoreFramePosition("SettingsPanelPos", self)
    end
    self:Show()
end

function MainFrame:HandleEscape()
    self:Hide()
    return false
end

-- ESC 关闭功能（与 Plumber 一致）
do
    local CloseDummy = CreateFrame("Frame", "ADTSettingsPanelSpecialFrame", UIParent)
    CloseDummy:Hide()
    table.insert(UISpecialFrames, CloseDummy:GetName())

    CloseDummy:SetScript("OnHide", function()
        if MainFrame:HandleEscape() then
            CloseDummy:Show()
        end
    end)

    MainFrame:HookScript("OnShow", function()
        if MainFrame.mode == "standalone" then
            CloseDummy:Show()
        end
    end)

    MainFrame:HookScript("OnHide", function()
        CloseDummy:Hide()
    end)
end

-- 编辑模式自动打开 GUI（替代独立弹窗）
do
    local EditorWatcher = CreateFrame("Frame")
    local wasEditorActive = false
    
    local function UpdateEditorState()
        local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
        
        if isActive then
            if not wasEditorActive then
                -- 进入编辑模式：自动打开 GUI
                MainFrame:ShowUI("editor")
                -- 若没有历史分类记录，首次进入仍默认到“临时板”；
                -- 若已有 LastCategoryKey，则交由 Tab1:OnShow 的恢复逻辑处理（避免覆盖）。
                C_Timer.After(0.1, function()
                    local key = ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey')
                    if not key then
                        MainFrame:ShowDecorListCategory('Clipboard')
                    end
                end)
            end
            -- 调整层级确保在编辑器之上
            if HouseEditorFrame then
                MainFrame:SetParent(HouseEditorFrame)
                MainFrame:SetFrameStrata("TOOLTIP")
            end
        else
            -- 退出编辑模式：隐藏 GUI
            MainFrame:SetParent(UIParent)
            MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            MainFrame:Hide()
        end
        
        wasEditorActive = isActive
    end
    
    EditorWatcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    EditorWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    EditorWatcher:SetScript("OnEvent", function()
        C_Timer.After(0.15, UpdateEditorState)
    end)
end
