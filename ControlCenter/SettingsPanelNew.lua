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
    PageHeight = 576,
    CategoryGap = 40,
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
        if ActiveCategoryInfo[self.categoryKey] then
            MainFrame.ModuleTab.ScrollView:ScrollTo(ActiveCategoryInfo[self.categoryKey].scrollOffset)
            ADT.LandingPageUtil.PlayUISound("ScrollBarStep")
        end
    end

    function CategoryButtonMixin:OnMouseDown()
        if ActiveCategoryInfo[self.categoryKey] then
            self.Label:SetPoint("LEFT", self, "LEFT", self.labelOffset + 1, -1)
        end
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


do  -- Right Section
    function MainFrame:ShowFeaturePreview(moduleData, parentDBKey)
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
        end
    end

    function MainFrame:UpdateSettingsEntries()
        self.ModuleTab.ScrollView:CallObjectMethod("Entry", "UpdateState")
    end
end


local function CreateUI()
    local pageHeight = Def.PageHeight

    local scalerWidth = 1 / 0.85
    local ratio_Center = 0.618
    local sideSectionWidth = API.Round((pageHeight * scalerWidth) * (1 - ratio_Center))
    local centralSectionWidth = API.Round((pageHeight * scalerWidth) * ratio_Center)
    MainFrame:SetSize(2 * sideSectionWidth + centralSectionWidth, Def.PageHeight)
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
    RightSection:SetWidth(sideSectionWidth)


    -- LeftSection
    do
        SearchBox = CreateSearchBox(Tab1)
        SearchBox:SetPoint("TOPLEFT", LeftSection, "TOPLEFT", Def.WidgetGap, -Def.WidgetGap)
        SearchBox:SetWidth(sideSectionWidth - 2 * Def.WidgetGap)


        local leftListFromY = 2*Def.WidgetGap + Def.ButtonSize

        local DivH = CreateDivider(Tab1, sideSectionWidth - 0.5*Def.WidgetGap)
        DivH:SetPoint("CENTER", LeftSection, "TOP", 0, -leftListFromY)


        leftListFromY = leftListFromY + Def.WidgetGap
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
        Background:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)


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
    end


    local NineSlice = ADT.LandingPageUtil.CreateExpansionThemeFrame(MainFrame.FrameContainer, 10)
    MainFrame.NineSlice = NineSlice
    NineSlice:CoverParent(-24)
    NineSlice.Background:Hide()
    NineSlice:SetUsingParentLevel(false)
    NineSlice:SetFrameLevel(baseFrameLevel + 20)
    NineSlice:ShowCloseButton(true)
    NineSlice:SetCloseButtonOwner(MainFrame)


    Tab1:SetScript("OnShow", function()
        MainFrame:RefreshFeatureList()
    end)
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

