-- 控制中心 GUI（简化版实现，文件名：gui.lua）
-- 说明：删除了 ChangelogTab/TabButton/最小化等不必要元素，仅保留
-- 左侧分类、中间功能列表、右侧预览等核心交互。

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
    BackgroundFile = "Interface/AddOns/AdvancedDecorationTools/Art/ControlCenter/CommonFrameWithHeader.tga", -- [NEW] HD Background
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
    -- 右侧内容区域左侧统一内边距（从左侧容器右边框算起，需与左侧 Category 按钮到右边框的边距一致：Def.WidgetGap）
    -- 注意：实际读取请使用 GetRightPadding() 以保证与 Def.WidgetGap 一致。
    RightContentPaddingLeft = 14,
    -- 左侧分类：标题与数量的视觉间隔以及为数量预留的宽度
    CategoryLabelToCountGap = 8,
    CountTextWidthReserve = 22,
    -- 与 Entry 模板保持一致的左内边距（ADTSettingsPanelEntryTemplate 中文本的 x 偏移）
    EntryLabelLeftInset = 28,
    -- Header 左移微调（用于靠近渐变边缘，但不顶边）
    HeaderLeftNudge = 8,
    -- About(信息) 面板的纯文本行相对容器的额外左内边距（不使用图标位）
    AboutTextExtraLeft = 0,
    -- 高亮条边距与最小高度（配合 housing-basic-container）
    -- 语义：
    --   - HighlightTextPaddingLeft：高亮左边缘距离“文本起点”的预留像素，保证文本不贴框
    --   - HighlightRightInset：高亮右边缘距按钮右边缘的收缩像素，尽可能把右侧计数也框入
    HighlightTextPaddingLeft = 10,
    HighlightRightInset = 2,
    HighlightMinHeight = 22,
}

-- 单一权威：右侧内容起始的左内边距，强制与左侧 Category 的外边距一致
local function GetRightPadding()
    return Def.WidgetGap
end


-- 依据“实际分类文本宽度”动态计算左侧栏目标宽度（单一权威）
-- 说明：不再使用按语种的固定值；改为测量当前语言下所有分类标题的像素宽度，
--       再加上控件自身的左右留白，得到最小充分宽度。
local function ComputeSideSectionWidth()
    local labelOffset = 9                -- 与 CategoryButton 的 labelOffset 保持一致
    local meterParent = MainFrame or UIParent
    -- 复用隐藏量尺，避免频繁创建对象
    if not meterParent._ADT_TextMeter then
        local m = meterParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        m:Hide()
        meterParent._ADT_TextMeter = m
    end
    local M = meterParent._ADT_TextMeter

    local function textWidth(text)
        M:SetText(text or "")
        local w = math.ceil(M:GetStringWidth() or 0)
        M:SetText("")
        return w
    end

    local maxLabel = 0
    -- 直接用数据源的分类名称测量，避免按钮本身宽度限制导致的“被截断宽度”。
    if ControlCenter and ControlCenter.GetSortedModules then
        local list = ControlCenter:GetSortedModules() or {}
        for _, cat in ipairs(list) do
            maxLabel = math.max(maxLabel, textWidth(cat.categoryName))
        end
    end
    -- 兜底：如果数据源不可用，再尝试已创建的按钮标签
    if maxLabel == 0 and MainFrame and MainFrame.primaryCategoryPool and MainFrame.primaryCategoryPool.EnumerateActive then
        for _, btn in MainFrame.primaryCategoryPool:EnumerateActive() do
            if btn and btn.Label and btn.Label.GetText then
                maxLabel = math.max(maxLabel, textWidth(btn.Label:GetText() or ""))
            end
        end
    end

    -- 计算按钮与侧栏总宽度：按钮左右文本留白 + 计数区域预留(14) + 左侧区域两侧边距
    local buttonWidth = maxLabel + 2*labelOffset + Def.CountTextWidthReserve + Def.CategoryLabelToCountGap
    local sideWidth = buttonWidth + 2*Def.WidgetGap
    -- 返回整数像素，避免锯齿
    return API.Round(sideWidth)
end


local MainFrame = CreateFrame("Frame", nil, UIParent, "ADTSettingsPanelLayoutTemplate")
ControlCenter.SettingsPanel = MainFrame
do
    local frameKeys = {"LeftSection", "RightSection", "CentralSection", "SideTab", "TabButtonContainer", "ModuleTab", "ChangelogTab"}
    for _, key in ipairs(frameKeys) do
        MainFrame[key] = MainFrame.FrameContainer[key]
    end

    -- 创建专用边框Frame（确保在所有子内容之上）
    local BorderFrame = CreateFrame("Frame", nil, MainFrame)
    BorderFrame:SetAllPoints(MainFrame)
    BorderFrame:SetFrameLevel(MainFrame:GetFrameLevel() + 100) -- 确保边框在最上层
    MainFrame.BorderFrame = BorderFrame
    
    -- 使用 housing-wood-frame Atlas 九宫格边框
    local border = BorderFrame:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", BorderFrame, "TOPLEFT", -4, 4)
    border:SetPoint("BOTTOMRIGHT", BorderFrame, "BOTTOMRIGHT", 4, -4)
    border:SetAtlas("housing-wood-frame")
    border:SetTextureSliceMargins(16, 16, 16, 16)
    border:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    BorderFrame.WoodFrame = border

    -- 使用标准暴雪关闭按钮（与 housing 边框协调）
    local CloseButton = CreateFrame("Button", nil, BorderFrame, "UIPanelCloseButton")
    MainFrame.CloseButton = CloseButton
    CloseButton:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", 2, 2)
    CloseButton:SetScript("OnClick", function()
        MainFrame:Hide()
        if ADT.UI and ADT.UI.PlaySoundCue then
            ADT.UI.PlaySoundCue('ui.checkbox.off')
        end
    end)
end
local SearchBox
local CategoryHighlight
local ActiveCategoryInfo = {}


-- 取消通用“贴图换肤”函数，全面改用暴雪内置 Atlas/模板

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
    div:SetSize(width, 8)
    div:SetAtlas("house-upgrade-header-divider-horz")
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


-- ============================================================================
-- 自定义下拉菜单系统（使用 SettingsPanel.png 素材）
-- ============================================================================
local ADTDropdownMenu
do
    -- 将常量存储在菜单对象上，避免闭包问题
    local MENU_WIDTH = 160
    local ITEM_HEIGHT = 20   -- 下拉项更矮，视觉更精致
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
        
        -- 单选按钮：最小化复选框 + 黄色对勾（使用暴雪 Atlas）
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
    -- 重要：在编辑器模式下，SettingsPanel 会提升到 "TOOLTIP" 层级。
    -- 若下拉菜单仅为 FULLSCREEN_DIALOG，则会被面板遮挡，导致“看似没弹出”。
    -- 因此统一使用最高层级 TOOLTIP，确保始终在面板之上。
    ADTDropdownMenu:SetFrameStrata("TOOLTIP")
    ADTDropdownMenu:SetFrameLevel(100)
    ADTDropdownMenu:Hide()
    ADTDropdownMenu:EnableMouse(true)
    ADTDropdownMenu:SetClampedToScreen(true)
    
    -- 使用九宫格背景（SettingsPanel.png 左上角区域）
    -- 根据图片素材坐标设置九宫格背景
    local bg = ADTDropdownMenu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    -- 使用暴雪通用面板背景
    bg:SetAtlas("housing-basic-panel-background")
    bg:SetVertexColor(1, 1, 1)
    ADTDropdownMenu.Background = bg
    
    -- 金色边框（使用九宫格）
    local borderSize = 3
    local borders = {}
    for i = 1, 4 do
        borders[i] = ADTDropdownMenu:CreateTexture(nil, "BORDER")
        borders[i]:SetColorTexture(0.6, 0.5, 0.3)
    end
    -- 上边框
    borders[1]:SetPoint("TOPLEFT", ADTDropdownMenu, "TOPLEFT", 0, 0)
    borders[1]:SetPoint("TOPRIGHT", ADTDropdownMenu, "TOPRIGHT", 0, 0)
    borders[1]:SetHeight(borderSize)
    -- 下边框
    borders[2]:SetPoint("BOTTOMLEFT", ADTDropdownMenu, "BOTTOMLEFT", 0, 0)
    borders[2]:SetPoint("BOTTOMRIGHT", ADTDropdownMenu, "BOTTOMRIGHT", 0, 0)
    borders[2]:SetHeight(borderSize)
    -- 左边框
    borders[3]:SetPoint("TOPLEFT", ADTDropdownMenu, "TOPLEFT", 0, 0)
    borders[3]:SetPoint("BOTTOMLEFT", ADTDropdownMenu, "BOTTOMLEFT", 0, 0)
    borders[3]:SetWidth(borderSize)
    -- 右边框
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
        
        ADT.DebugPrint("[Dropdown] Setting size: " .. MENU_WIDTH .. "x" .. menuHeight)
        self:SetSize(MENU_WIDTH, menuHeight)
        
        -- 记录归属者，便于“点外面关闭”时排除自身与触发按钮
        self.owner = owner

        -- 定位到按钮下方
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
        
        -- 创建菜单项
        local currentValue = ADT.GetDBValue(dbKey)
        ADT.DebugPrint("[Dropdown] Current value: " .. tostring(currentValue))
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
                if MainFrame.UpdateSettingsEntries then
                    MainFrame:UpdateSettingsEntries()
                end
            end
            
            table.insert(self.items, item)
        end
        
        -- 再次确保层级足够高（在某些 UI 改动后防御性设置）
        self:SetFrameStrata("TOOLTIP")
        self:SetFrameLevel( max( (owner and owner:GetFrameLevel() or 0) + 10, 100) )

        ADT.DebugPrint("[Dropdown] Showing menu frame")
        self:Show()
        ADT.DebugPrint("[Dropdown] Menu frame IsShown: " .. tostring(self:IsShown()))

        -- 由于点击按钮时鼠标仍处于按下状态，会导致“立即关闭”。
        -- 这里等待一次鼠标松开，再开始侦测点击外部以关闭。
        self.waitRelease = true
        self:SetScript("OnUpdate", function()
            -- 首先等待一次任意键松开，避免首帧被立刻关闭
            if self.waitRelease then
                if not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then
                    self.waitRelease = false
                end
                return
            end

            -- 鼠标按下，且既不在菜单上也不在触发按钮上，则关闭
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

    -- 允许按 ESC 关闭下拉菜单（与 Settings 面板行为一致）
    if ADTDropdownMenu.GetName then
        local name = ADTDropdownMenu:GetName()
        if name and UISpecialFrames then
            -- 避免重复插入
            local found
            for i, v in ipairs(UISpecialFrames) do if v == name then found = true break end end
            if not found then table.insert(UISpecialFrames, name) end
        end
    end
end


local CreateSearchBox
do
    local StringTrim = API.StringTrim

    function CreateSearchBox(parent)
        -- 使用暴雪原生 SearchBoxTemplate，避免自定义贴图/切片
        local f = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
        f:SetAutoFocus(false)
        f:SetSize(168, Def.ButtonSize)
        f.Instructions:SetText(SEARCH)

        -- 统一文字颜色
        f:SetTextColor(1, 1, 1)

        -- 文本变化回调（200ms 防抖）
        local t
        f:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            t = 0
            self:SetScript("OnUpdate", function(self2, elapsed)
                t = t + elapsed
                if t > 0.2 then
                    self2:SetScript("OnUpdate", nil)
                    local text = StringTrim(self2:GetText())
                    MainFrame:RunSearch(text)
                end
            end)
        end)

        -- 清除按钮与 Esc 行为
        if f.ClearButton then
            f.ClearButton:SetScript("OnClick", function(btn)
                local self2 = btn:GetParent()
                self2:SetText("")
                MainFrame:RunSearch("")
                if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.checkbox.off') end
            end)
        end
        f:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

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
            if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.scroll.step') end
        elseif cat and cat.categoryType == 'about' then
            -- 信息分类：显示关于信息
            MainFrame:ShowAboutCategory(self.categoryKey)
            if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.scroll.step') end
        else
            -- 设置类分类：仅显示该分类的条目（不与其它分类混排）
            MainFrame:ShowSettingsCategory(self.categoryKey)
            if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.scroll.step') end
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
        -- 使用固定宽度，防止数字位数变化造成视觉跳动（单一权威：与 ComputeSideSectionWidth 里的预留一致）
        local countWidth = Def.CountTextWidthReserve or 22
        CountContainer:SetSize(countWidth, Def.ButtonSize)
        -- 右侧外边距与左侧 labelOffset 对称：9px
        CountContainer:SetPoint("RIGHT", f, "RIGHT", -f.labelOffset, 0)
        CountContainer:Hide()
        CountContainer:SetAlpha(0)
        -- 去掉数字背景框，仅淡入文字
        MakeFadingObject(CountContainer)
        CountContainer:SetFadeSpeed(8)

        f.Count = CountContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.Count:SetJustifyH("RIGHT")
        -- 数字右内边距 2px，避免贴边；与容器宽度分离以获得更稳定的视觉对齐
        f.Count:ClearAllPoints()
        f.Count:SetPoint("RIGHT", CountContainer, "RIGHT", -2, 0)
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
        
        -- 下拉菜单类型：更新标签显示当前选中值
        if moduleData.type == 'dropdown' then
            self:UpdateDropdownLabel()
        end
        
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
        ADT.DebugPrint("[SettingsPanel] OnClick triggered, dbKey=" .. tostring(self.dbKey))
        if self.dbKey and self.data then
            ADT.DebugPrint("[SettingsPanel] data.type=" .. tostring(self.data.type))
            -- 下拉菜单类型：使用暴雪 12.0+ Menu API（最佳实践）
            if self.data.type == 'dropdown' then
                ADT.DebugPrint("[SettingsPanel] Using MenuUtil.CreateContextMenu")
                MenuUtil.CreateContextMenu(self, function(owner, root)
                    if self.data.dropdownBuilder then
                        self.data.dropdownBuilder(owner, root)
                    else
                        if not self.data.options then return end
                        local function IsSelected(value)
                            return ADT.GetDBValue(self.dbKey) == value
                        end
                        local function SetSelected(value)
                            ADT.SetDBValue(self.dbKey, value, true)
                            if self.data.toggleFunc then
                                self.data.toggleFunc(value)
                            end
                            self:UpdateDropdownLabel()
                            if MainFrame.UpdateSettingsEntries then
                                MainFrame:UpdateSettingsEntries()
                            end
                            return MenuResponse.Close
                        end
                        for _, opt in ipairs(self.data.options) do
                            if opt and opt.action == 'button' and opt.onClick then
                                root:CreateButton(opt.text, function()
                                    opt.onClick()
                                    return MenuResponse.Close
                                end)
                            else
                                root:CreateRadio(opt.text, IsSelected, SetSelected, opt.value)
                            end
                        end
                    end
                end)
                return  -- 不需要执行后续的 UpdateSettingsEntries
            -- 普通复选框类型
            elseif self.data.toggleFunc then
                local newState = not GetDBBool(self.dbKey)
                ADT.SetDBValue(self.dbKey, newState, true)
                self.data.toggleFunc(newState)
                if newState then
                    if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.checkbox.on') end
                else
                    if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.checkbox.off') end
                end
            end
        end

        MainFrame:UpdateSettingsEntries()
    end
    
    -- 更新下拉菜单的显示标签
    function EntryButtonMixin:UpdateDropdownLabel()
        if not self.data or self.data.type ~= 'dropdown' or not self.data.options then return end
        local currentValue = ADT.GetDBValue(self.dbKey)
        local displayText = self.data.name
        for _, opt in ipairs(self.data.options) do
            if opt.value == currentValue then
                displayText = self.data.name .. "：" .. opt.text
                break
            end
        end
        self.Label:SetText(displayText)
    end

    function EntryButtonMixin:UpdateState()
        if self.virtual then
            self:Enable()
            self.OptionToggle:SetShown(self.hasOptions)
            -- 虚拟条目：仅显示容器，不显示对勾
            if self.Box.SetAtlas then self.Box:SetAtlas("checkbox-minimal") end
            if self.Check then self.Check:Hide() end
            return
        end
        
        -- 下拉菜单类型：显示下拉箭头，使用柔和金色文字
        if self.data and self.data.type == 'dropdown' then
            -- 下拉项不显示左侧复选框/对勾，也不显示右侧更多按钮图标
            if self.Box then self.Box:Hide() end
            if self.Check then self.Check:Hide() end
            self.OptionToggle:Hide()
            self:Enable()
            -- 设置柔和金色文字（0.922, 0.871, 0.761）
            SetTextColor(self.Label, { 0.922, 0.871, 0.761 })
            self:UpdateDropdownLabel()
            return
        else
            self.Box:Show()  -- 确保复选框显示
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

    function EntryButtonMixin:UpdateVisual()
        if self:IsEnabled() then
            if self:IsMouseMotionFocus() then
                SetTextColor(self.Label, Def.TextColorHighlight)
            else
                -- 下拉菜单使用柔和金色，普通条目使用默认颜色
                if self.data and self.data.type == 'dropdown' then
                    SetTextColor(self.Label, { 0.922, 0.871, 0.761 })
                else
                    SetTextColor(self.Label, Def.TextColorNormal)
                end
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

        -- 复选框属于“小尺寸图元”，若使用三线性过滤(TRILINEAR)，在缩放/生成mipmap时会从图集相邻切片取样，
        -- 即便我们做了 +1px inset，仍可能出现“橙色勾边缘发灰/发白”的串色伪影。
        -- 因此这里明确关闭三线性过滤，退回 LINEAR，以保证像素仅在当前切片内采样。
        f.Box.useTrilinearFilter = false
        if f.Box.SetAtlas then f.Box:SetAtlas("checkbox-minimal") end
        -- 对勾覆盖层（黄色对勾）
        local check = f:CreateTexture(nil, "OVERLAY")
        f.Check = check
        check:SetAtlas("common-icon-checkmark-yellow")
        check:SetSize(20, 20)
        check:SetPoint("CENTER", f.Box, "CENTER", 0, 0)
        check:Hide()

        f.NewTag = CreateNewFeatureMark(f)

        -- 暂不显示独立的“更多选项”按钮图标，保留点击行为
        Mixin(f.OptionToggle, OptionToggleMixin)
        f.OptionToggle:OnLoad()
        f.OptionToggle.Texture:Hide()

        return f
    end
end


local CreateSettingsHeader
do
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


    function CreateSettingsHeader(parent)
        local f = CreateFrame("Frame", nil, parent, "ADTSettingsPanelHeaderTemplate")
        Mixin(f, HeaderMixin)
        SetTextColor(f.Label, Def.TextColorNonInteractable)

        -- 使用 Housing 风格分割线，弃用旧的 SettingsPanel 贴片
        if f.Left then f.Left:Hide() end
        if f.Right then f.Right:Hide() end

        local divider = f:CreateTexture(nil, "ARTWORK")
        f.Divider = divider
        divider:SetAtlas("house-upgrade-header-divider-horz")
        divider:SetHeight(2)
        -- 具体锚点在 SetLeftPadding 中与内容对齐

        -- 统一左边距：标题与右侧内容共用同一左起点（不对齐到图标位）
        local defaultHeaderLeft = GetRightPadding()
        f:SetLeftPadding(defaultHeaderLeft)
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
        local displayName = item.name or (string.format((ADT.L and ADT.L['Decor #%d']) or '装饰 #%d', tonumber(item.decorID) or 0))
        
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
            GameTooltip:AddLine(string.format((ADT.L and ADT.L['Stock: %d']) or '库存：%d', self.available), 0, 1, 0)
        else
            GameTooltip:AddLine((ADT.L and ADT.L['Stock: 0 (Unavailable)']) or '库存：0（不可放置）', 1, 0.2, 0.2)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((ADT.L and ADT.L['Left Click: Place']) or '左键：开始放置', 0.8, 0.8, 0.8)
        if self.categoryInfo and self.categoryInfo.key == 'Clipboard' then
            GameTooltip:AddLine((ADT.L and ADT.L['Right Click: Remove from Clipboard']) or '右键：从临时板移除', 1, 0.4, 0.4)
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
        -- Icon border removed - user prefers clean icons without frames
        f:SetScript("OnEnter", f.OnEnter)
        f:SetScript("OnLeave", f.OnLeave)
        f:SetScript("OnClick", f.OnClick)
        SetTextColor(f.Name, Def.TextColorNormal)
        -- 名称仅单行显示，过长时自动省略号
        if f.Name and f.Name.SetMaxLines then f.Name:SetMaxLines(1) end
        if f.Name and f.Name.SetWordWrap then f.Name:SetWordWrap(false) end
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

        -- 使用暴雪 Atlas：housing-basic-container（与截图一致）
        -- 彻底摆脱 SettingsPanel.png 切片依赖
        if f.Left then f.Left:Hide() end
        if f.Center then f.Center:Hide() end
        if f.Right then f.Right:Hide() end

        local bg = f:CreateTexture(nil, "ARTWORK")
        f.Background = bg
        bg:SetAllPoints(true)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("housing-basic-container") then
            bg:SetAtlas("housing-basic-container")
        else
            -- 兜底视觉：半透明金色条，防止在极端版本下出现空白
            bg:SetColorTexture(1.0, 0.82, 0.0, 0.15)
        end

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
            -- 使用 housing-basic-container：
            -- 左边缘相对“文本起点”向左外扩，高亮应覆盖文本并留出可读留白
            local labelOffset = tonumber(button.labelOffset) or 9
            local textPad = tonumber(Def.HighlightTextPaddingLeft) or 10
            local insetLeft = math.max(0, labelOffset - textPad)

            -- 右边缘尽量贴近按钮右缘，把计数容器也包含在内
            local insetRight = tonumber(Def.HighlightRightInset) or 2
            CategoryHighlight:SetPoint("LEFT", button, "LEFT", insetLeft, 0)
            CategoryHighlight:SetPoint("RIGHT", button, "RIGHT", -insetRight, 0)
            CategoryHighlight:SetParent(button)
            -- 提高高度以匹配容器厚边框，同时保留上下留白
            local minH = tonumber(Def.HighlightMinHeight) or 22
            local h = math.max(minH, (Def.ButtonSize or 28) - 4)
            CategoryHighlight:SetHeight(h)
            CategoryHighlight:FadeIn()
        end
    end

    -- 运行时根据语言调整左侧栏宽度，并联动更新相关控件尺寸
    function MainFrame:_ApplySideWidth(sideWidth)
        sideWidth = API.Round(sideWidth)
        local LeftSection = self.LeftSection
        if not LeftSection then return end

        LeftSection:SetWidth(sideWidth)

        -- 分类按钮宽度与高亮条宽度
        local btnWidth = sideWidth - 2*Def.WidgetGap
        if CategoryHighlight and CategoryHighlight.SetSize then
            CategoryHighlight:SetSize(btnWidth, Def.ButtonSize)
        end
        if self.primaryCategoryPool and self.primaryCategoryPool.EnumerateActive then
            for _, button in self.primaryCategoryPool:EnumerateActive() do
                if button and button.SetSize then
                    button:SetSize(btnWidth, Def.ButtonSize)
                end
                if button and button.Label and button.labelOffset then
                    button.Label:SetWidth(btnWidth - 2*button.labelOffset - (Def.CountTextWidthReserve + Def.CategoryLabelToCountGap))
                end
            end
        end

        -- 右侧预览图尺寸与滚动区联动（中央区随锚点自动伸缩，但滚动条需手动刷新）
        local previewSize = math.max(64, sideWidth - 2*Def.ButtonSize)
        if self.FeaturePreview and self.FeaturePreview.SetSize then
            self.FeaturePreview:SetSize(previewSize, previewSize)
        end

        if self.CentralSection and self.ModuleTab and self.ModuleTab.ScrollView then
            local CentralSection = self.CentralSection
            local newWidth = API.Round(CentralSection:GetWidth() - 2*Def.ButtonSize)
            if newWidth > 0 then
                self.centerButtonWidth = newWidth
                local ScrollView = self.ModuleTab.ScrollView
                ScrollView:CallObjectMethod("Entry", "SetWidth", newWidth)
                ScrollView:CallObjectMethod("Header", "SetWidth", newWidth)
                ScrollView:CallObjectMethod("DecorItem", "SetWidth", newWidth)
                ScrollView:OnSizeChanged(true)
                if self.ModuleTab.ScrollBar and self.ModuleTab.ScrollBar.UpdateThumbRange then
                    self.ModuleTab.ScrollBar:UpdateThumbRange()
                end
            end
        end
    end

    function MainFrame:AnimateSideWidthTo(targetWidth)
        local from = self.LeftSection and self.LeftSection:GetWidth() or targetWidth
        if not from or math.abs(from - targetWidth) < 1 then
            self:_ApplySideWidth(targetWidth)
            return
        end
        local t, d = 0, 0.25
        local ease = ADT.EasingFunctions and ADT.EasingFunctions.outQuint
        self:SetScript("OnUpdate", function(_, elapsed)
            t = t + (elapsed or 0)
            if t >= d then
                self:SetScript("OnUpdate", nil)
                self:_ApplySideWidth(targetWidth)
                return
            end
            local cur
            if ease then
                cur = ease(t, from, targetWidth - from, d)
            else
                cur = API.Lerp(from, targetWidth, t/d)
            end
            self:_ApplySideWidth(cur)
        end)
    end

    function MainFrame:RefreshLanguageLayout(animated)
        local target = ComputeSideSectionWidth()
        if animated then
            self:AnimateSideWidthTo(target)
        else
            self:_ApplySideWidth(target)
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
        local name = itemData.name or (entryInfo and entryInfo.name) or (string.format((ADT.L and ADT.L['Decor #%d']) or '装饰 #%d', tonumber(itemData.decorID) or 0))
        local desc = name .. "\n\n"
        if available and available > 0 then
            desc = desc .. string.format("|cff00ff00%s|r\n\n", string.format((ADT.L and ADT.L['Stock: %d']) or '库存：%d', available))
        else
            desc = desc .. string.format("|cffff3333%s|r\n\n", (ADT.L and ADT.L['Stock: 0 (Unavailable)']) or '库存：0（不可放置）')
        end
        desc = desc .. string.format("|cffaaaaaa%s|r", (ADT.L and ADT.L['Left Click: Place']) or '左键：开始放置')
        if self.currentDecorCategory == 'Clipboard' then
            desc = desc .. string.format("\n|cffff6666%s|r", (ADT.L and ADT.L['Right Click: Remove from Clipboard']) or '右键：从临时板移除')
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
        -- 右侧内容整体左内边距（不移动各小节 Header）
        local offsetX = GetRightPadding()

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
                        -- 使用 Housing 分割线
                        if obj.Left then obj.Left:Hide() end
                        if obj.Right then obj.Right:Hide() end
                        if obj.Divider then obj.Divider:Show() end
                        obj.Label:SetJustifyH("LEFT")
                    end,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    top = top,
                    bottom = bottom,
                    -- Header 与右侧内容共用同一左起点
                    offsetX = GetRightPadding(),
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
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
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
                            point = "TOPLEFT",
                            relativePoint = "TOPLEFT",
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

    -- 仅显示一个“设置类”分类（不与其它分类混排）
    function MainFrame:ShowSettingsCategory(categoryKey)
        local cat = ControlCenter:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'settings' then return end

        self.currentSettingsCategory = categoryKey
        self.currentDecorCategory = nil
        self.currentAboutCategory = nil
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end

        local content = {}
        local n = 0
        local buttonHeight = Def.ButtonSize
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local buttonGap = 0
        local subOptionOffset = Def.ButtonSize
        local offsetX = GetRightPadding()

        -- 分类标题
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(cat.categoryName)
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Show() end
                obj.Label:SetJustifyH("LEFT")
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + buttonHeight,
            offsetX = GetRightPadding(),
        }
        offsetY = offsetY + buttonHeight

        -- 分类内条目
        for _, data in ipairs(cat.modules) do
            n = n + 1
            local top = offsetY
            local bottom = offsetY + buttonHeight + buttonGap
            content[n] = {
                dataIndex = n,
                templateKey = "Entry",
                setupFunc = function(obj)
                    obj.parentDBKey = nil
                    obj:SetData(data)
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
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
                        point = "TOPLEFT",
                        relativePoint = "TOPLEFT",
                        top = top,
                        bottom = bottom,
                        offsetX = offsetX + 0.5*subOptionOffset,
                    }
                    offsetY = bottom
                end
            end
        end

        self.firstModuleData = cat.modules[1]
        self.ModuleTab.ScrollView:SetContent(content, false)
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
        -- 保持现有宽度；语言切换时由 RefreshLanguageLayout(true) 统一处理动画与宽度
    end

    function MainFrame:UpdateSettingsEntries()
        self.ModuleTab.ScrollView:CallObjectMethod("Entry", "UpdateState")
    end

    -- 显示装饰列表分类（临时板或最近放置）
    function MainFrame:ShowDecorListCategory(categoryKey)
        local cat = ControlCenter:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'decorList' then return end
        
        self.currentDecorCategory = categoryKey
        self.currentSettingsCategory = nil
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
        
        local list = cat.getListData and cat.getListData() or {}
        local content = {}
        local n = 0
        local buttonHeight = 36 -- 装饰项按钮高度
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local buttonGap = 2
        -- 右侧内容左内边距（Header 同步此起点）
        local offsetX = GetRightPadding()
        
        -- 添加标题（左对齐锚点）
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(cat.categoryName)
                -- 标题使用 Housing 分割线
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Show() end
                obj.Label:SetJustifyH("LEFT")
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + Def.ButtonSize,
            offsetX = GetRightPadding(),
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
                    local text = cat.emptyText or (ADT.L and ADT.L['List Is Empty']) or "列表为空"
                    local firstLine = text:match("^([^\n]*)")
                    obj:SetText(firstLine or text)
                    SetTextColor(obj.Label, Def.TextColorDisabled)
                    -- 仅保留页面主标题的分隔纹理；空列表提示不显示分隔线
                    if obj.Left then obj.Left:Hide() end
                    if obj.Right then obj.Right:Hide() end
                    if obj.Divider then obj.Divider:Hide() end
                    obj.Label:SetJustifyH("LEFT")
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
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
                            -- 空列表第二行同样不显示分隔线
                            if obj.Left then obj.Left:Hide() end
                            if obj.Right then obj.Right:Hide() end
                            if obj.Divider then obj.Divider:Hide() end
                            obj.Label:SetJustifyH("LEFT")
                        end,
                        point = "TOPLEFT",
                        relativePoint = "TOPLEFT",
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
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
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
            self.FeatureDescription:SetText(cat.emptyText or (ADT.L and ADT.L['List Is Empty']) or "列表为空")
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
        self.currentSettingsCategory = nil
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
        
        local content = {}
        local n = 0
        local buttonHeight = Def.ButtonSize
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        -- 右侧内容左内边距（Header 同步此起点）
        local offsetX = GetRightPadding()
        
        -- 添加标题（保留分隔线，左对齐锚点）
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(cat.categoryName)
                -- 确保标题的分割线可见（Housing 风格）
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Show() end
                obj.Label:SetJustifyH("LEFT") -- 标题左对齐
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + Def.ButtonSize,
            offsetX = GetRightPadding(),
        }
        offsetY = offsetY + Def.ButtonSize * 2
        
        -- 添加信息文本（隐藏分隔线，更靠左对齐；信息面板不占用 Entry 的“图标位”）
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
                        obj.Label:SetJustifyH("LEFT") -- 信息行更靠左
                        -- 隐藏分割线纹理
                        if obj.Left then obj.Left:Hide() end
                        if obj.Right then obj.Right:Hide() end
                        if obj.Divider then obj.Divider:Hide() end
                        -- 单独设置信息行的左边距：不使用 Entry 的 28px 图标缩进
                        if obj.SetLeftPadding then obj:SetLeftPadding(GetRightPadding() + (Def.AboutTextExtraLeft or 0)) end
                    end,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
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
    
    -- 紧凑布局：左侧宽度按“分类文本宽度”动态计算
    local sideSectionWidth = ComputeSideSectionWidth()
    local centralSectionWidth = 340  -- 中间：图标 + 长装饰名称(如"小型锯齿奥格瑞玛栅栏") + 数量
    
    MainFrame:SetSize(sideSectionWidth + centralSectionWidth, pageHeight)
    if ADT and ADT.RestoreFrameSize then
        ADT.RestoreFrameSize("SettingsPanelSize", MainFrame)
    end
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

    -- 允许缩放 + 右下角手柄（仅改变右侧内容宽度）
    do
        -- 计算最小尺寸：高度至少能显示两行条目；
        -- 宽度：左侧固定列宽 + 右侧至少能显示“艾尔..”
        local meter = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        meter:SetText("艾尔..")
        local textMin = math.ceil(meter:GetStringWidth())
        meter:SetText("")
        meter:Hide()

        local iconW, gapW, countW, padW = 28, 8, 40, 16
        local rightMin = iconW + gapW + textMin + countW + padW
        local minH = 160
        local minW = sideSectionWidth + rightMin

        MainFrame:SetResizable(true)
        if MainFrame.SetResizeBounds then
            MainFrame:SetResizeBounds(minW, minH)
        else
            -- 旧版本兼容：确保不会被缩到过小
            if MainFrame.SetMinResize then MainFrame:SetMinResize(minW, minH) end
        end

        -- 右下角缩放手柄（使用聊天窗口的抓手贴图）
        local grip = CreateFrame("Button", nil, MainFrame.BorderFrame or MainFrame)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
        grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
        -- 为了让“右下角抓手”在缩放时精准跟随鼠标，我们在开始缩放前
        -- 将面板的锚点归一为 TOPLEFT（基于当前的屏幕绝对位置）。
        -- 如果保持 CENTER 等锚点，StartSizing("BOTTOMRIGHT") 会以中心为基准放大，
        -- 视觉上就会出现“右下角不在鼠标上”的错位感。
        local function ReanchorToTopLeft(f)
            if not (f and f.GetLeft and f.GetTop and f.ClearAllPoints) then return end
            local parent = f:GetParent() or UIParent
            local fScale = f.GetEffectiveScale and f:GetEffectiveScale() or 1
            local pScale = parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
            local left = (f:GetLeft() or 0) * (fScale / pScale)
            local top  = (f:GetTop() or 0)  * (fScale / pScale)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", left, top)
        end

        grip:SetScript("OnMouseDown", function()
            if not MainFrame then return end
            ReanchorToTopLeft(MainFrame)
            if MainFrame.StartSizing then MainFrame:StartSizing("BOTTOMRIGHT") end
        end)
        grip:SetScript("OnMouseUp", function()
            if MainFrame and MainFrame.StopMovingOrSizing then MainFrame:StopMovingOrSizing() end
            if ADT and ADT.SaveFrameSize then ADT.SaveFrameSize("SettingsPanelSize", MainFrame) end
            if ADT and ADT.SaveFramePosition then ADT.SaveFramePosition("SettingsPanelPos", MainFrame) end
        end)
        MainFrame.ResizeGrip = grip
    end
    
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
            obj.Label:SetWidth(categoryButtonWidth - 2 * obj.labelOffset - (Def.CountTextWidthReserve + Def.CategoryLabelToCountGap))
            return obj
        end

        local function Category_Acquire(obj)
            obj:FadeIn(true)
            obj:ResetOffset()
        end

        MainFrame.primaryCategoryPool = API.CreateObjectPool(Category_Create, Category_Acquire, nil)
        MainFrame.primaryCategoryPool.leftListFromY = -leftListFromY
        MainFrame.primaryCategoryPool.offsetX = Def.WidgetGap


        CategoryHighlight = CreateSelectionHighlight(Tab1)
        CategoryHighlight:SetSize(categoryButtonWidth, Def.ButtonSize)

        -- 左侧面板采用完整九宫格框体（The War Within 卡片风格）
        do
            local frame = Tab1:CreateTexture(nil, "BORDER")
            MainFrame.LeftPanelBackground = frame
            frame:SetAtlas("ui-frame-thewarwithin-cardparchmentwider")
            -- 经验值：该卡片边框厚度约 28-32px，取 32 以确保角不被拉伸
            frame:SetTextureSliceMargins(32, 32, 32, 32)
            frame:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
            frame:SetPoint("TOPLEFT", LeftSection, "TOPLEFT", -4, 4)
            frame:SetPoint("BOTTOMRIGHT", LeftSection, "BOTTOMRIGHT", 4, -4)
        end
    end


    do  -- RightSection（预览与说明）
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


    do  -- CentralSection（设置列表所在区域）
        -- 使用 Housing 基础面板背景（更通用的面板底纹）；移除遮罩层，按你的最新偏好保持原始透明度
        local Background = CentralSection:CreateTexture(nil, "BACKGROUND")
        Background:SetAtlas("housing-basic-panel-background")
        -- 适度内缩，让边缘花纹不被边框压住
        Background:SetPoint("TOPLEFT", CentralSection, "TOPLEFT", -4, -2)
        Background:SetPoint("BOTTOMRIGHT", CentralSection, "BOTTOMRIGHT", -2, 2)


        -- 暂不显示自研滚动条，后续将切换为暴雪 ScrollBox 体系
        MainFrame.ModuleTab.ScrollBar = nil

        local ScrollView = API.CreateListView(Tab1)
        MainFrame.ModuleTab.ScrollView = ScrollView
        ScrollView:SetPoint("TOPLEFT", CentralSection, "TOPLEFT", 0, -2)
        ScrollView:SetPoint("BOTTOMRIGHT", CentralSection, "BOTTOMRIGHT", 0, 2)
        ScrollView:SetStepSize(Def.ButtonSize * 2)
        ScrollView:OnSizeChanged()
        ScrollView:EnableMouseBlocker(true)
        ScrollView:SetBottomOvershoot(Def.CategoryGap)
        -- 不显示滚动条
        ScrollView:SetAlwaysShowScrollBar(false)
        ScrollView:SetShowNoContentAlert(true)
        ScrollView:SetNoContentAlertText(CATALOG_SHOP_NO_SEARCH_RESULTS or "")


        -- 初始右侧可用宽度，随着窗口缩放动态更新
        MainFrame.centerButtonWidth = API.Round(CentralSection:GetWidth() - 2*Def.ButtonSize)
        Def.centerButtonWidth = MainFrame.centerButtonWidth


        local function EntryButton_Create()
            local obj = CreateSettingsEntry(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
            return obj
        end

        ScrollView:AddTemplate("Entry", EntryButton_Create)


        local function Header_Create()
            local obj = CreateSettingsHeader(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
            return obj
        end

        ScrollView:AddTemplate("Header", Header_Create)


        -- 装饰项模板（用于临时板和最近放置列表）
        local function DecorItem_Create()
            local obj = CreateDecorItemEntry(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, 36)
            return obj
        end

        ScrollView:AddTemplate("DecorItem", DecorItem_Create)
    end


    -- 取消自定义边框相关占位与调用，改由顶部 UIPanelCloseButton 控制关闭


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
        local key = (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey')) or MainFrame.currentDecorCategory or MainFrame.currentAboutCategory or MainFrame.currentSettingsCategory
        local cat = key and ControlCenter:GetCategoryByKey(key) or nil
        if cat and cat.categoryType == 'decorList' then
            MainFrame:ShowDecorListCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'about' then
            MainFrame:ShowAboutCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'settings' then
            MainFrame:ShowSettingsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        else
            -- 默认回退到第一个“设置类”分类
            local all = ControlCenter:GetSortedModules()
            local firstSettings
            for _, info in ipairs(all) do
                if info.categoryType ~= 'decorList' and info.categoryType ~= 'about' then
                    firstSettings = info.key; break
                end
            end
            if firstSettings then
                MainFrame:ShowSettingsCategory(firstSettings)
                MainFrame:HighlightCategoryByKey(firstSettings)
            else
                MainFrame:RefreshFeatureList()
            end
        end
    end)

    -- 单一 OnSizeChanged：当窗口缩放时，仅调整右侧内容宽度
    MainFrame:SetScript("OnSizeChanged", function(self)
        local CentralSection = self.CentralSection
        if not CentralSection or not self.ModuleTab or not self.ModuleTab.ScrollView then return end
        local newWidth = API.Round(CentralSection:GetWidth() - 2*Def.ButtonSize)
        if newWidth <= 0 then return end
        if self.centerButtonWidth ~= newWidth then
            self.centerButtonWidth = newWidth
            local ScrollView = self.ModuleTab.ScrollView
            ScrollView:CallObjectMethod("Entry", "SetWidth", newWidth)
            ScrollView:CallObjectMethod("Header", "SetWidth", newWidth)
            ScrollView:CallObjectMethod("DecorItem", "SetWidth", newWidth)
            ScrollView:OnSizeChanged(true)
            if self.ModuleTab.ScrollBar and self.ModuleTab.ScrollBar.UpdateThumbRange then
                self.ModuleTab.ScrollBar:UpdateThumbRange()
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
    if self.ModuleTab.ScrollBar and self.ModuleTab.ScrollBar.OnSizeChanged then
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
    -- 关闭按钮由 UIPanelCloseButton 提供，无需额外控制
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

-- ESC 关闭功能（按 ESC 关闭面板）
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

    -- 注意：OnSizeChanged 已在 CreateUI 中注册，此处不再重复绑定。
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
    EditorWatcher:SetScript("OnEvent", function(_, event)
        if event == "HOUSE_EDITOR_MODE_CHANGED" then
            -- 离开编辑模式时，立刻隐藏以避免可见闪烁；进入时再做轻微延迟以等待编辑器完成布局
            local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
            if not isActive then
                -- 立即隐藏，不等待
                if MainFrame then
                    MainFrame:SetParent(UIParent)
                    MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                    MainFrame:Hide()
                end
                wasEditorActive = false
                return
            end
        end
        -- 进入或其它情况：短延迟以确保编辑器框架已就位
        C_Timer.After(0.05, UpdateEditorState)
    end)
end
