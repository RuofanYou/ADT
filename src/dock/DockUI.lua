
-- DockUI.lua
-- 主框架：左侧分类、中间功能列表、右侧预览等核心交互。
-- 注意：配置常量/调试/高亮/下拉菜单/条目工厂/折叠逻辑已拆分到子模块。

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local L = ADT.L
local API = ADT.API
local CommandDock = ADT.CommandDock
local GetDBBool = ADT.GetDBBool

local Mixin = API.Mixin
local CreateFrame = CreateFrame
local DisableSharpening = API.DisableSharpening

-- 从子模块获取配置（单一权威：DockUI_Def.lua）
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding

-- 从子模块获取工厂函数（单一权威：DockUI_EntryFactory.lua）
local CreateSettingsEntry = ADT.DockUI.CreateSettingsEntry
local CreateSettingsHeader = ADT.DockUI.CreateSettingsHeader
local CreateDecorItemEntry = ADT.DockUI.CreateDecorItemEntry
local CreateNewFeatureMark = ADT.DockUI.CreateNewFeatureMark

-- 临时应急：使用静态左窗
local USE_STATIC_LEFT_PANEL = (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) or false

-- 工具函数
local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

-- 折叠/展开与面板显隐逻辑已迁移到 DockUI_Collapse.lua（单一权威）

-- 提前提供一个“请求子面板自适应高度”的稳定入口（占位包装器）。
-- 目的：解决 /reload 后 HoverHUD 先于 SubPanel 初始化时，
--       首次 RecalculateHeight 触发的请求被丢失的问题。
-- 真实实现仍在 SubPanel.lua 内部生成（单一权威），
-- 此处仅做一次性延迟转发，避免业务层出现空指针。
if not ADT.DockUI.RequestSubPanelAutoResize then
    ADT.DockUI.RequestSubPanelAutoResize = function()
        -- 优先直接找到 SubPanel 实例并调用其单一权威入口，避免任何重复实现。
        local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
        local sub = main and (main.SubPanel or (main.EnsureSubPanel and main:EnsureSubPanel()))
        local caller = sub and sub._ADT_RequestAutoResize
        if type(caller) == "function" then
            caller()
            return
        end
        -- 若 SubPanel 尚未完成构建，延后半帧重试一次（最多一次）。
        if not (ADT and ADT.DockUI) then return end
        if ADT.DockUI.__resizeRetryScheduled then return end
        ADT.DockUI.__resizeRetryScheduled = true
        C_Timer.After(0.05, function()
            if ADT and ADT.DockUI then ADT.DockUI.__resizeRetryScheduled = nil end
            local main2 = ADT.CommandDock and ADT.CommandDock.SettingsPanel
            local sub2 = main2 and (main2.SubPanel or (main2.EnsureSubPanel and main2:EnsureSubPanel()))
            local caller2 = sub2 and sub2._ADT_RequestAutoResize
            if type(caller2) == "function" then caller2() end
        end)
    end
end

-- 依据“实际分类文本宽度”动态计算左侧栏目标宽度（单一权威）
-- 说明：不再使用按语种的固定值；改为测量当前语言下所有分类标题的像素宽度，
--       再加上控件自身的左右留白，得到最小充分宽度。
local function ComputeSideSectionWidth()
    return (ADT.DockLeft and ADT.DockLeft.ComputeSideSectionWidth and ADT.DockLeft.ComputeSideSectionWidth()) or 180
end

-- 导出侧栏宽度计算（单一权威）
ADT.DockUI.ComputeSideSectionWidth = ComputeSideSectionWidth

-- 调试设施已迁移到 DockUI_Debug.lua（单一权威）

local MainFrame = CreateFrame("Frame", nil, UIParent, "ADTSettingsPanelLayoutTemplate")
CommandDock.SettingsPanel = MainFrame
do
    -- 清理废弃：仍不使用 SideTab/TabButtonContainer；
    -- 但为兼容性保留 LeftSection/RightSection（模板已 hidden，并在此仅作为占位键读取）。
    local frameKeys = {"LeftSection", "RightSection", "CentralSection", "ModuleTab", "ChangelogTab", "TopTabOwner"}
    for _, key in ipairs(frameKeys) do
        MainFrame[key] = MainFrame.FrameContainer[key]
    end
    -- 顶部标签回退为左右布局：隐藏顶栏托管容器，避免遮挡
    if MainFrame.TopTabOwner then MainFrame.TopTabOwner:Hide() end

    -- 创建专用边框Frame（确保在所有子内容之上）
    local BorderFrame = CreateFrame("Frame", nil, MainFrame)
    BorderFrame:SetAllPoints(MainFrame)
    BorderFrame:SetFrameLevel(MainFrame:GetFrameLevel() + 100) -- 确保边框在最上层
    MainFrame.BorderFrame = BorderFrame
    BorderFrame:EnableMouse(false) -- 仅视觉，不拦截鼠标
    
    -- 使用 housing-wood-frame Atlas 九宫格边框
    local border = BorderFrame:CreateTexture(nil, "OVERLAY")
    -- 让右侧边框严格贴合自身容器，避免“向左溢出”覆盖左窗
    border:SetPoint("TOPLEFT", BorderFrame, "TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", BorderFrame, "BOTTOMRIGHT", 0, 0)
    border:SetAtlas("housing-wood-frame")
    border:SetTextureSliceMargins(16, 16, 16, 16)
    border:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    BorderFrame.WoodFrame = border

    -- 使用标准暴雪关闭按钮（与 housing 边框协调）
    local CloseButton = CreateFrame("Button", nil, BorderFrame, "UIPanelCloseButton")
    MainFrame.CloseButton = CloseButton
    -- 锚到边框容器右上角，并向内收缩，避免跑到面板外侧
    CloseButton:ClearAllPoints()
    CloseButton:SetPoint("TOPRIGHT", BorderFrame, "TOPRIGHT", Def.CloseBtnOffsetX, Def.CloseBtnOffsetY)
    -- 防御：确保层级在木框之上，且不会吃掉左侧面板的鼠标
    CloseButton:SetFrameLevel((BorderFrame:GetFrameLevel() or 0) + 2)
    CloseButton:SetScript("OnClick", function()
        -- 根因修复：
        -- 右侧 Dock 主框体在家宅编辑器内被用户手动关闭时，
        -- 若直接 Hide() 父容器，会导致后续模式切换（如外观模式→普通编辑）
        -- 采纳的 Instructions 与 HoverHUD 全部挂在隐藏的父层级下，SubPanel 永久不可见。
        -- 设计上“主体面板显隐”应独立于 SubPanel，因此在编辑器内点击关闭仅隐藏主体面板，
        -- 保持 Dock 容器与 SubPanel 继续可用（不挡交互且可随悬停/选中自动显隐）。
        local inEditor = (C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()) or false
        if inEditor and ADT and ADT.DockUI and ADT.DockUI.SetMainPanelsVisible then
            ADT.DockUI.SetMainPanelsVisible(false)
        else
            MainFrame:Hide()
        end
        if ADT.UI and ADT.UI.PlaySoundCue then
            ADT.UI.PlaySoundCue('ui.checkbox.off')
        end
    end)
end
--
-- 将暴雪家宅编辑器中的“放置的装饰清单”按钮（PlacedDecorListButton）
-- 采纳到 ADT 的 Header 内（偏左位置）。
-- 单一权威：采纳/恢复逻辑仅在本文件维护，外部只需触发 DockUI.Attach/Restore。
--
ADT.DockUI = ADT.DockUI or {}
do
    -- 回归“只搬运官方按钮”的实现：不创建代理、不屏蔽官方逻辑。
    local OrigParent, OrigStrata
    local OrigPoint -- {p, rel, rp, x, y}
    local Attached = false

    local function GetPlacedListButton()
        local hf = _G.HouseEditorFrame
        local expert = hf and hf.ExpertDecorModeFrame
        local btn = expert and expert.PlacedDecorListButton
        return btn, expert
    end

    local function _IsExpertMode()
        local HEM = C_HouseEditor and C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode()
        return HEM == (Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.ExpertDecor)
    end

    local function SaveOriginal(btn)
        if OrigParent then return end
        OrigParent = btn:GetParent()
        OrigStrata = btn:GetFrameStrata()
        if btn:GetNumPoints() > 0 then
            local p, rel, rp, x, y = btn:GetPoint(1)
            OrigPoint = { p = p, rel = rel, rp = rp, x = x, y = y }
        end
    end

    local function RestoreToOriginal()
        local btn = GetPlacedListButton()
        if not (btn and OrigParent) then return end
        btn:ClearAllPoints()
        btn:SetParent(OrigParent)
        if OrigPoint then
            btn:SetPoint(OrigPoint.p or "CENTER", OrigPoint.rel or OrigParent, OrigPoint.rp or OrigPoint.p, tonumber(OrigPoint.x) or 0, tonumber(OrigPoint.y) or 0)
        end
        if OrigStrata then btn:SetFrameStrata(OrigStrata) end
        Attached = false
    end

    local function AttachIntoHeader()
        if not (MainFrame and MainFrame.Header) then return end
        local btn = GetPlacedListButton()
        if not btn then return end
        SaveOriginal(btn)
        btn:ClearAllPoints()
        -- 关键：不改父级，只以 Header 作为锚点移动位置（KISS）
        local cfg = (ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.PlacedListButton) or {}
        local p  = cfg.point or "LEFT"
        local rp = cfg.relPoint or p
        local x  = tonumber(cfg.offsetX) or 40
        local y  = tonumber(cfg.offsetY) or 0
        btn:SetPoint(p, MainFrame.Header, rp, x, y)
        -- 尺寸/层级（可选）
        pcall(function()
            if cfg.scale and btn.SetScale then btn:SetScale(cfg.scale) end
            local strata = cfg.strata or (MainFrame:GetFrameStrata() or "FULLSCREEN_DIALOG")
            btn:SetFrameStrata(strata)
            local lvl
            if MainFrame.BorderFrame and tonumber(cfg.levelBiasOverBorder or 0) > 0 then
                lvl = (MainFrame.BorderFrame:GetFrameLevel() or 0) + tonumber(cfg.levelBiasOverBorder or 0)
            else
                lvl = (MainFrame:GetFrameLevel() or 0) + tonumber(cfg.levelBias or 0)
            end
            btn:SetFrameLevel(lvl)
        end)
        btn:Show()
        Attached = true
    end

    -- 对外：只做“附着/恢复”，不更改官方逻辑
    function ADT.DockUI.AttachPlacedListButton() AttachIntoHeader() end
    function ADT.DockUI.RestorePlacedListButton() RestoreToOriginal() end

    -- 事件驱动：进入家宅编辑器时附着；退出时恢复
    local EL = CreateFrame("Frame")
    EL:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    EL:RegisterEvent("ADDON_LOADED")
    EL:RegisterEvent("PLAYER_LOGIN")
    EL:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_HouseEditor" then
            AttachIntoHeader()
        elseif event == "PLAYER_LOGIN" then
            AttachIntoHeader()
        elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
            if C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() and _IsExpertMode() then
                AttachIntoHeader()
            else
                RestoreToOriginal()
            end
        end
    end)
end
local SearchBox
local CategoryHighlight
local ActiveCategoryInfo = {}

-- 动态收敛左侧分类容器高度
--[[ 已迁移至 LeftPanel.lua
function MainFrame:UpdateLeftSectionHeight()
    local LeftSection = self.LeftSection
    if not LeftSection then return end
    local n = 0
    if self.primaryCategoryPool and self.primaryCategoryPool.EnumerateActive then
        for _ in self.primaryCategoryPool:EnumerateActive() do n = n + 1 end
    end
    local topPad = Def.WidgetGap or 14
    local catH = Def.CategoryHeight or Def.ButtonSize or 28
    local height = math.max(catH, topPad + n * catH + topPad)
    LeftSection:SetHeight(height)
end]]

-- 启用“上下布局 + 顶部标签”
local USE_TOP_TABS = false

-- 顶部标签系统初始化（基于 TabSystemOwner + TabSystemTopButtonTemplate）
function MainFrame:InitTopTabs()
    if not USE_TOP_TABS then return end
    if not (self.TopTabOwner and self.TopTabOwner.TabSystem) then return end

    self.TopTabOwner:SetTabSystem(self.TopTabOwner.TabSystem)

    self.__tabKeyFromID = {}
    self.__tabIDFromKey = {}

    local list = CommandDock:GetSortedModules() or {}
    for _, info in ipairs(list) do
        local tabID = self.TopTabOwner:AddNamedTab(info.categoryName)
        self.__tabKeyFromID[tabID] = info.key
        self.__tabIDFromKey[info.key] = tabID

        -- 捕获每次循环的局部值，避免闭包引用同一 upvalue
        local catKey = info.key
        local catType = info.categoryType

        -- 选中回调：按分类类型分派到现有渲染函数；若内容未初始化则缓存待应用
        self.TopTabOwner:SetTabCallback(tabID, function(isUserAction)
            if not (self.ModuleTab and self.ModuleTab.ScrollView) then
                self.__pendingTabKey = catKey
                return
            end
            if catType == 'decorList' then
                self:ShowDecorListCategory(catKey)
            elseif catType == 'about' then
                self:ShowAboutCategory(catKey)
            else
                self:ShowSettingsCategory(catKey)
            end
        end)
    end

    -- 记录待应用默认标签，等内容区创建后再选中
    self.__pendingTabKey = (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey')) or 'Housing'
end

-- 空壳下方拼接弹窗：实现迁移至独立模块 src/dock/SubPanel.lua

function MainFrame:ApplyInitialTabSelection()
    if not (USE_TOP_TABS and self.TopTabOwner and self.__tabIDFromKey) then return end
    if not (self.ModuleTab and self.ModuleTab.ScrollView) then return end
    local key = self.__pendingTabKey or 'Housing'
    local id = self.__tabIDFromKey[key] or 1
    self.TopTabOwner:SetTab(id)
    self.__pendingTabKey = nil
end


-- 取消通用“贴图换肤”函数，全面改用暴雪内置 Atlas/模板

local function SetTexCoord(obj, x1, x2, y1, y2)
    obj:SetTexCoord(x1/1024, x2/1024, y1/1024, y2/1024)
end

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

-- 下拉菜单系统已迁移到 DockUI_Dropdown.lua（单一权威）
local ADTDropdownMenu = ADT.DockUI.DropdownMenu


--[[ LeftPanel/SearchBox：已迁移到 src/dock/LeftPanel.lua
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
end]]


--[[ LeftPanel/CategoryButton：已迁移到 src/dock/LeftPanel.lua
local CreateCategoryButton
do
    local CategoryButtonMixin = {}

    function CategoryButtonMixin:OnEnter()
        if ADT and ADT.DebugPrint then
            ADT.DebugPrint("[DockLeft] OnEnter key="..tostring(self.categoryKey)
                .." over="..tostring(self:IsMouseOver())
                .." btn="..(self.GetName and (self:GetName() or "") or ""))
        end
        MainFrame:HighlightButton(self)
        SetTextColor(self.Label, Def.TextColorHighlight)
    end

    function CategoryButtonMixin:OnLeave()
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[DockLeft] OnLeave key="..tostring(self.categoryKey)) end
        MainFrame:HighlightButton()
        SetTextColor(self.Label, Def.TextColorNormal)
    end

    function CategoryButtonMixin:SetCategory(key, text, anyNewFeature)
        if ADT and ADT.API and ADT.API.StringTrim then
            text = ADT.API.StringTrim(text or "")
        else
            text = tostring(text or ""):match("^%s*(.-)%s*$")
        end
        self.Label:SetText(text)
        self.cateogoryName = string.lower(text)
        self.categoryKey = key

        self.NewTag:ClearAllPoints()
        self.NewTag:SetPoint("CENTER", self, "LEFT", 0, 0)
        self.NewTag:SetShown(anyNewFeature)
    end

    function CategoryButtonMixin:ShowCount(count)
        -- 计数显示/隐藏，并根据当前按钮宽度重新计算 Label 的可用宽度，
        -- 保证左右内边距对称（无计数时不预留右侧空白）。
        local hasCount = count and count > 0
        if hasCount then
            self.Count:SetText(count)
            self.CountContainer:FadeIn()
        else
            self.CountContainer:FadeOut()
        end
        if self.UpdateLabelWidth then self:UpdateLabelWidth() end
    end

    function CategoryButtonMixin:OnClick()
        if ADT and ADT.DebugPrint then
            local f = GetMouseFocus and GetMouseFocus()
            local fname = f and (f.GetName and f:GetName()) or tostring(f)
            ADT.DebugPrint("[DockLeft] OnClick key="..tostring(self.categoryKey).." focus="..tostring(fname))
        end
        local cat = CommandDock:GetCategoryByKey(self.categoryKey)
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
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[DockLeft] OnMouseDown key="..tostring(self.categoryKey)) end
    end

    function CategoryButtonMixin:OnMouseUp()
        self:ResetOffset()
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[DockLeft] OnMouseUp key="..tostring(self.categoryKey)) end
    end

    function CategoryButtonMixin:ResetOffset()
        self.Label:SetPoint("LEFT", self, "LEFT", self.labelOffset, 0)
    end

    function CreateCategoryButton(parent)
        local f = CreateFrame("Button", nil, parent)
        Mixin(f, CategoryButtonMixin)
        f:SetSize(120, 26)
        f.labelOffset = Def.CategoryButtonLabelOffset or 9
        if f.RegisterForClicks then f:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
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
        f.Count:SetPoint("RIGHT", CountContainer, "RIGHT", - (Def.CategoryCountRightInset or 2), 0)
        SetTextColor(f.Count, Def.TextColorNonInteractable)

        f:SetScript("OnEnter", f.OnEnter)
        f:SetScript("OnLeave", f.OnLeave)
        f:SetScript("OnClick", f.OnClick)
        f:SetScript("OnMouseDown", f.OnMouseDown)
        f:SetScript("OnMouseUp", f.OnMouseUp)

        f.NewTag = CreateNewFeatureMark(f, true)

        -- 统一的 Label 宽度自适应：根据是否显示计数决定是否预留右侧空间
        function f:UpdateLabelWidth()
            local bw = tonumber(self:GetWidth()) or 0
            if bw <= 0 then return end
            local reserve = 0
            if self.CountContainer and self.CountContainer:IsShown() then
                reserve = (Def.CountTextWidthReserve + Def.CategoryLabelToCountGap)
            end
            self.Label:SetWidth(bw - 2 * self.labelOffset - reserve)
        end

        return f
    end
end]]

-- 条目工厂（OptionToggleMixin、CreateSettingsEntry、CreateSettingsHeader、CreateDecorItemEntry）
-- 已迁移到 DockUI_EntryFactory.lua（单一权威）

-- 高亮容器逻辑已迁移到 DockUI_Highlight.lua（单一权威）




-- 子面板的实现已迁移至 src/dock/SubPanel.lua


--[[ LeftPanel/SelectionHighlight：已迁移到 src/dock/LeftPanel.lua
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

        -- 统一改用纯色矩形，保证左右对称
        if f.Left then f.Left:Hide() end
        if f.Center then f.Center:Hide() end
        if f.Right then f.Right:Hide() end

        local bg = f:CreateTexture(nil, "ARTWORK")
        f.Background = bg
        bg:SetAllPoints(true)
        bg:SetColorTexture(0, 0, 0, 0.30)

        f.d = 0.6
        f:Hide()
        f:SetScript("OnHide", f.OnHide)

        return f
    end
end]]


do  -- Left Section
    -- 高亮逻辑由 LeftPanel 注入到 MainFrame；此处不再实现

    -- 单一权威：中央区域宽度 = MainFrame 总宽度 - LeftSection 占位宽度
    -- 说明：当 Dock 主体宽度仅包含“右侧内容区”时（_widthIsCentralOnly=true），
    -- 直接返回 MainFrame 宽度；否则按 “总宽 - 左栏宽度”。
    function MainFrame:_GetCentralSectionWidth()
        local total = tonumber(self.GetWidth and self:GetWidth()) or 0
        if self._widthIsCentralOnly then
            return API.Round(total)
        end
        local sidew = tonumber(self.LeftSection and self.LeftSection.GetWidth and self.LeftSection:GetWidth()) or 0
        local w = total - sidew
        if w < 0 then w = 0 end
        return API.Round(w)
    end

    -- 单一权威：同步中央列表模板宽度（Entry/Header/DecorItem/KeybindEntry）
    function MainFrame:_SyncCentralTemplateWidths(forceRender)
        local sv = self.ModuleTab and self.ModuleTab.ScrollView
        if not (sv and sv.CallObjectMethod) then return false end

        local centralW = self:_GetCentralSectionWidth()
        local pad = GetRightPadding()
        local newWidth = API.Round(centralW - 2 * pad)
        if newWidth <= 0 then return false end

        self.centerButtonWidth = newWidth
        sv:CallObjectMethod("Entry", "SetWidth", newWidth)
        sv:CallObjectMethod("Header", "SetWidth", newWidth)
        sv:CallObjectMethod("DecorItem", "SetWidth", newWidth)
        sv:CallObjectMethod("KeybindEntry", "SetWidth", newWidth)

        if forceRender and sv.OnSizeChanged then
            sv:OnSizeChanged(true)
        end
        if self.ModuleTab and self.ModuleTab.ScrollBar and self.ModuleTab.ScrollBar.UpdateThumbRange then
            self.ModuleTab.ScrollBar:UpdateThumbRange()
        end
        return true
    end

    -- 运行时根据语言调整左侧栏宽度，并联动更新相关控件尺寸
    function MainFrame:_ApplySideWidth(sideWidth)
        sideWidth = API.Round(sideWidth)
        local LeftSection = self.LeftSection
        if not LeftSection then return end

        LeftSection:SetWidth(sideWidth)

        -- 同步左侧滑出容器宽度与收起位置
        if self.LeftSlideContainer then
            self.LeftSlideContainer:SetWidth(sideWidth)
        end
        if self.LeftSlideDriver and self.GetLeftClosedOffset then
            local closed = self.GetLeftClosedOffset()
            if math.abs(self.LeftSlideDriver.target) > 0.5 then
                self.LeftSlideDriver.target = closed
                if math.abs(self.LeftSlideDriver.x - closed) < 1 then
                    self.LeftSlideDriver.x = closed
                    if self.LeftSlideDriver.onUpdate then self.LeftSlideDriver.onUpdate(closed) end
                end
            end
        end

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
                if button and button.UpdateLabelWidth then button:UpdateLabelWidth() end
            end
        end

        -- 右侧预览图尺寸与滚动区联动（中央区随锚点自动伸缩，但滚动条需手动刷新）
        local previewSize = math.max(64, sideWidth - 2*Def.ButtonSize)
        if self.FeaturePreview and self.FeaturePreview.SetSize then
            self.FeaturePreview:SetSize(previewSize, previewSize)
        end

        self:_SyncCentralTemplateWidths(true)
    end

    function MainFrame:AnimateSideWidthTo(targetWidth, onDone)
        local from = self.LeftSection and self.LeftSection:GetWidth() or targetWidth
        if not from or math.abs(from - targetWidth) < 1 then
            self:_ApplySideWidth(targetWidth)
            if type(onDone) == "function" then onDone() end
            return
        end
        local t, d = 0, 0.25
        local ease = ADT.EasingFunctions and ADT.EasingFunctions.outQuint
        self:SetScript("OnUpdate", function(_, elapsed)
            t = t + (elapsed or 0)
            if t >= d then
                self:SetScript("OnUpdate", nil)
                self:_ApplySideWidth(targetWidth)
                if type(onDone) == "function" then onDone() end
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
            self:AnimateSideWidthTo(target, function()
                if self.UpdateAutoWidth then self:UpdateAutoWidth() end
            end)
        else
            self:_ApplySideWidth(target)
            if self.UpdateAutoWidth then self:UpdateAutoWidth() end
        end
    end

    -- 中央“设置项”行高亮：已下沉到 EntryButtonMixin（每个条目自管），避免跨层级 frame level 混乱。
end


do  -- Right Section (已移除，保留函数但添加空检查)
    function MainFrame:ShowFeaturePreview(moduleData, parentDBKey)
        -- 仅更新预览贴图；已移除说明文字
        if not self.FeaturePreview then return end
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
        self.FeaturePreview:SetTexture("Interface/AddOns/AdvancedDecorationTools/Art/CommandDock/Preview_"..(parentDBKey or moduleData.dbKey))
    end

    -- 显示装饰项预览（右侧预览区已移除，函数保留但不执行任何操作）
    function MainFrame:ShowDecorPreview(itemData, available)
        -- 仅更新预览贴图
        if not self.FeaturePreview then return end
        if not itemData then return end
        -- 设置预览图标
        local icon = itemData.icon or 134400
        local entryInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID
            and C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, itemData.decorID, true)
        if entryInfo and entryInfo.iconTexture then
            icon = entryInfo.iconTexture
        end
        self.FeaturePreview:SetTexture(icon)
    end
end


do  -- Search
    function MainFrame:RunSearch(text)
        if text and text ~= "" then
            self.listGetter = function()
                return CommandDock:GetSearchResult(text)
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
            -- 注意：不能直接赋值为 CommandDock.GetSortedModules（那样会丢失冒号调用的 self）
            -- 绑定为闭包，确保以冒号语义调用，避免 self 为 nil。
            self.listGetter = function()
                return CommandDock:GetSortedModules()
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

        local sortedModule = self.listGetter and self.listGetter() or CommandDock:GetSortedModules()

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
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
    end

    -- 仅显示一个“设置类”分类（不与其它分类混排）
    function MainFrame:ShowSettingsCategory(categoryKey)
        if not (self.ModuleTab and self.ModuleTab.ScrollView) then
            self.__pendingTabKey = categoryKey
            return
        end
        local cat = CommandDock:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'settings' then return end

        -- 安全兜底：如果目标分类没有任何条目（例如 AutoRotate 仍未注入具体选项），
        -- 自动回退到第一个“包含条目”的设置类分类（通常是 Housing/通用），
        -- 避免出现“右侧只有说明、中央列表为空”的错觉。
        if (not cat.modules) or (#cat.modules == 0) then
            for _, info in ipairs(CommandDock:GetSortedModules()) do
                if info.categoryType == 'settings' and info.modules and #info.modules > 0 then
                    if ADT and ADT.DebugPrint then ADT.DebugPrint("[SettingsPanel] Empty category "..tostring(categoryKey)..", fallback -> "..tostring(info.key)) end
                    categoryKey = info.key
                    cat = info
                    break
                end
            end
        end

        self.currentSettingsCategory = categoryKey
        self.currentDecorCategory = nil
        self.currentAboutCategory = nil
        self.currentDyePresetsCategory = nil
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
            if ADT and ADT.DebugPrint then ADT.DebugPrint("[SettingsPanel] item: "..tostring(data.name).." dbKey="..tostring(data.dbKey)) end
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
        if (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) and self.UpdateStaticLeftPlacement then C_Timer.After(0, function() self:UpdateStaticLeftPlacement() end) end
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[SettingsPanel] ShowSettingsCategory("..tostring(categoryKey)..") items="..tostring(#content)) end
        if self.firstModuleData then
            self:ShowFeaturePreview(self.firstModuleData)
        end
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
        if (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) and self.UpdateStaticLeftPlacement then C_Timer.After(0, function() self:UpdateStaticLeftPlacement() end) end
    end

    function MainFrame:RefreshCategoryList()
        if not self.primaryCategoryPool then return end
        self.primaryCategoryPool:ReleaseAll()
        for index, categoryInfo in ipairs(CommandDock:GetSortedModules()) do
            local categoryButton = self.primaryCategoryPool:Acquire()
            categoryButton:SetCategory(categoryInfo.key, categoryInfo.categoryName, categoryInfo.anyNewFeature)
            categoryButton:SetPoint("TOPLEFT", self.LeftSlideContainer, self.primaryCategoryPool.offsetX, self.primaryCategoryPool.leftListFromY - (index - 1) * (Def.CategoryHeight or Def.ButtonSize))
            -- 根据需求取消临时板/最近放置的数量角标显示，避免不必要的数据遍历
            if ADT and ADT.DebugPrint and ADT.IsDebugEnabled and ADT.IsDebugEnabled() then
                local lx, ly = categoryButton:GetLeft(), categoryButton:GetTop()
                ADT.DebugPrint(string.format("[DockLeft] acquire #%d key=%s x=%.1f y=%.1f", index, tostring(categoryInfo.key), lx or -1, ly or -1))
            end
        end
        -- 动态收敛左侧容器高度：根据分类数量计算
        self:UpdateLeftSectionHeight()
        -- 静态模式下，同步一次弹窗高度与位置
        if (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) and self.UpdateStaticLeftPlacement then self:UpdateStaticLeftPlacement() end
        -- 保持现有宽度；语言切换时由 RefreshLanguageLayout(true) 统一处理动画与宽度
    end

    function MainFrame:UpdateSettingsEntries()
        self.ModuleTab.ScrollView:CallObjectMethod("Entry", "UpdateState")
    end

    -- 显示装饰列表分类（临时板或最近放置）
    function MainFrame:ShowDecorListCategory(categoryKey)
        if not (self.ModuleTab and self.ModuleTab.ScrollView) then
            self.__pendingTabKey = categoryKey
            return
        end
        local cat = CommandDock:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'decorList' then return end
        
        self.currentDecorCategory = categoryKey
        self.currentSettingsCategory = nil
        self.currentAboutCategory = nil
        self.currentDyePresetsCategory = nil
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
            local emptyTop = offsetY + (Def.EmptyStateTopGap or 0)
            local emptyBottom = emptyTop + Def.ButtonSize
            content[n] = {
                dataIndex = n,
                templateKey = "Header",
                setupFunc = function(obj)
                    -- 注意：emptyText 可能包含换行符，这里只取第一行
                    local text = cat.emptyText
                    if not text then text = ADT.L["List Is Empty"] end
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

        -- 临时板在折叠→展开后的竞态兜底：
        -- 若本帧拿到的列表为空，延后一小段时间再读取一次；
        -- 仅当当前仍停留在同一分类且确实有数据时，才二次重渲，避免无谓刷新。
        if #list == 0 then
            C_Timer.After(0.06, function()
                if not (MainFrame and MainFrame.IsShown and MainFrame:IsShown()) then return end
                if MainFrame.currentDecorCategory ~= categoryKey then return end
                local cat2 = CommandDock:GetCategoryByKey(categoryKey)
                local list2 = cat2 and cat2.getListData and cat2.getListData() or {}
                if type(list2) == 'table' and #list2 > 0 then
                    MainFrame:ShowDecorListCategory(categoryKey)
                else
                    -- 没有数据也强制刷新一次视口，避免残留空白态
                    local sv = MainFrame.ModuleTab and MainFrame.ModuleTab.ScrollView
                    if sv and sv.OnSizeChanged then sv:OnSizeChanged(true) end
                end
            end)
        end
        
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
            -- 空列表时显示提示（已无右侧预览/说明）
            if self.FeaturePreview then self.FeaturePreview:SetTexture(134400) end
            if self.FeatureDescription then
                local text = cat.emptyText
                if not text then text = ADT.L["List Is Empty"] end
                self.FeatureDescription:SetText(text)
            end
        end
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
    end

    -- 显示染色预设分类
    function MainFrame:ShowDyePresetsCategory(categoryKey)
        if not (self.ModuleTab and self.ModuleTab.ScrollView) then
            self.__pendingTabKey = categoryKey
            return
        end
        local cat = CommandDock:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'dyePresetList' then return end
        
        self.currentDecorCategory = nil
        self.currentSettingsCategory = nil
        self.currentAboutCategory = nil
        self.currentDyePresetsCategory = categoryKey
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
        
        local list = cat.getListData and cat.getListData() or {}
        local content = {}
        local n = 0
        local buttonHeight = 32 -- 预设条目高度
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local buttonGap = 2
        local offsetX = GetRightPadding()
        
        -- 添加分类标题
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
            bottom = offsetY + Def.ButtonSize,
            offsetX = GetRightPadding(),
        }
        offsetY = offsetY + Def.ButtonSize
        
        -- 添加"保存当前剪贴板"按钮
        n = n + 1
        local saveBtnH = 28
        content[n] = {
            dataIndex = n,
            templateKey = "CenterButton",
            setupFunc = function(btn)
                -- 始终可点击，点击时检测剪贴板状态
                local btnText = ADT.L["Save Current Dye"] or "保存当前染色"
                if btn.SetText then btn:SetText(btnText) end
                btn:Enable()
                btn:SetScript("OnClick", function()
                    -- 点击时检测剪贴板状态
                    local hasClipboard = ADT.DyeClipboard and ADT.DyeClipboard._savedColors and #ADT.DyeClipboard._savedColors > 0
                    if not hasClipboard then
                        if ADT.Notify then ADT.Notify(ADT.L["No dye copied"] or "未复制任何染色", "error") end
                        return
                    end
                    if cat.onSaveClick then
                        cat.onSaveClick()
                        -- 刷新列表
                        C_Timer.After(0.05, function()
                            MainFrame:ShowDyePresetsCategory(categoryKey)
                        end)
                    end
                end)
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + saveBtnH,
            offsetX = offsetX,
        }
        offsetY = offsetY + saveBtnH + 8
        
        -- 添加预设列表或空列表提示
        if #list == 0 then
            n = n + 1
            local emptyTop = offsetY + (Def.EmptyStateTopGap or 0)
            local emptyBottom = emptyTop + Def.ButtonSize
            content[n] = {
                dataIndex = n,
                templateKey = "Header",
                setupFunc = function(obj)
                    local text = cat.emptyText
                    if not text then text = ADT.L["No dye presets"] or "暂无染色预设" end
                    local firstLine = text:match("^([^\n]*)") or text
                    obj:SetText(firstLine)
                    SetTextColor(obj.Label, Def.TextColorDisabled)
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
            offsetY = emptyBottom
            
            -- 第二行提示
            if cat.emptyText and cat.emptyText:find("\n") then
                local secondLine = cat.emptyText:match("\n(.*)$")
                if secondLine and secondLine ~= "" then
                    n = n + 1
                    content[n] = {
                        dataIndex = n,
                        templateKey = "Header",
                        setupFunc = function(obj)
                            obj:SetText(secondLine)
                            SetTextColor(obj.Label, Def.TextColorDisabled)
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
            -- 渲染预设列表（显示色块）
            for i, preset in ipairs(list) do
                n = n + 1
                local top = offsetY
                local bottom = offsetY + buttonHeight + buttonGap
                local capIndex = i
                local capCat = cat
                local capPreset = preset
                content[n] = {
                    dataIndex = n,
                    templateKey = "DyePresetItem",
                    setupFunc = function(obj)
                        obj:SetPresetData(capIndex, capPreset, capCat)
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
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
    end

    -- 返回设置列表视图
    function MainFrame:ShowSettingsView()
        self.currentDecorCategory = nil
        self.currentAboutCategory = nil
        self.currentDyePresetsCategory = nil
        self:RefreshFeatureList()
    end

    -- 显示信息分类（关于插件）
    function MainFrame:ShowAboutCategory(categoryKey)
        if not (self.ModuleTab and self.ModuleTab.ScrollView) then
            self.__pendingTabKey = categoryKey
            return
        end
        local cat = CommandDock:GetCategoryByKey(categoryKey)
        if not cat or cat.categoryType ~= 'about' then return end
        
        self.currentDecorCategory = nil
        self.currentAboutCategory = categoryKey
        self.currentSettingsCategory = nil
        self.currentDyePresetsCategory = nil
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
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
    end

    -- 显示快捷键分类
    function MainFrame:ShowKeybindsCategory(categoryKey)
        if ADT and ADT.DebugPrint then
            ADT.DebugPrint("[ShowKeybindsCategory] called with key=" .. tostring(categoryKey))
        end
        if not (self.ModuleTab and self.ModuleTab.ScrollView) then
            if ADT and ADT.DebugPrint then
                ADT.DebugPrint("[ShowKeybindsCategory] RETURN: ModuleTab/ScrollView not ready")
            end
            self.__pendingTabKey = categoryKey
            return
        end
        local cat = CommandDock:GetCategoryByKey(categoryKey)
        if ADT and ADT.DebugPrint then
            ADT.DebugPrint("[ShowKeybindsCategory] cat=" .. tostring(cat and "found" or "nil") .. ", categoryType=" .. tostring(cat and cat.categoryType or "nil"))
        end
        if not cat or cat.categoryType ~= 'keybinds' then
            if ADT and ADT.DebugPrint then
                ADT.DebugPrint("[ShowKeybindsCategory] RETURN: not keybinds type")
            end
            return
        end
        
        self.currentDecorCategory = nil
        self.currentAboutCategory = nil
        self.currentKeybindsCategory = categoryKey
        self.currentSettingsCategory = nil
        if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
        
        local content = {}
        local n = 0
        local buttonHeight = Def.ButtonSize
        local fromOffsetY = Def.ButtonSize
        local offsetY = fromOffsetY
        local offsetX = GetRightPadding()
        
        -- 添加标题（带右侧提示区域）
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
                
                -- 创建或获取提示文本（右侧）
                -- 说明：原实现将 FontString 作为 ScrollView 的子级，受 SetClipsChildren(true) 裁剪，
                -- 当 hintOffsetY 较大时（例如 200）会被截断，无法“越出弹窗”。
                -- 为遵循 KISS，改为把提示挂到 MainFrame 上，并通过锚点相对 Header 定位，
                -- 既可突破 ScrollView 的裁剪，又不破坏现有滚动与对象池逻辑。
                if not obj._keybindHint then
                    local KCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.KeybindUI) or {}
                    local hintOffsetX = KCFG.headerHintOffsetX or -8
                    local hintOffsetY = KCFG.headerHintOffsetY or 0
                    -- 挂到 MainFrame（FULLSCREEN_DIALOG 层），避免被 ScrollView 裁剪
                    local hint = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    hint:SetDrawLayer("OVERLAY", 7)
                    hint:SetPoint("RIGHT", obj, "RIGHT", hintOffsetX, hintOffsetY)
                    hint:SetJustifyH("RIGHT")
                    hint:SetTextColor(0.6, 0.8, 1, 1)  -- 浅蓝色

                    -- 跟随 Header 显隐，避免在滚动释放后残留
                    if not obj._adt_hintHooked then
                        obj:HookScript("OnHide", function() if hint then hint:Hide() end end)
                        obj:HookScript("OnShow", function() if hint then hint:Show() end end)
                        obj._adt_hintHooked = true
                    end

                    obj._keybindHint = hint
                end
                obj._keybindHint:SetText("")
                obj._keybindHint:Show()
                
                -- 注册为全局引用，供 KeybindEntry 使用
                MainFrame._keybindCategoryHint = obj._keybindHint
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + Def.ButtonSize,
            offsetX = GetRightPadding(),
        }
        offsetY = offsetY + Def.ButtonSize
        
        -- 获取所有快捷键动作
        local actions = ADT.Keybinds and ADT.Keybinds.GetAllActions and ADT.Keybinds:GetAllActions() or {}
        
        if ADT and ADT.DebugPrint then
            ADT.DebugPrint("[ShowKeybindsCategory] ADT.Keybinds exists=" .. tostring(ADT.Keybinds ~= nil) .. ", actions count=" .. tostring(#actions))
        end
        
        if #actions == 0 then
            -- 快捷键模块未加载
            n = n + 1
            content[n] = {
                dataIndex = n,
                templateKey = "Header",
                setupFunc = function(obj)
                    obj:SetText(ADT.L["Keybinds Module Not Loaded"])
                    SetTextColor(obj.Label, Def.TextColorDisabled)
                    if obj.Left then obj.Left:Hide() end
                    if obj.Right then obj.Right:Hide() end
                    if obj.Divider then obj.Divider:Hide() end
                    obj.Label:SetJustifyH("LEFT")
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                top = offsetY,
                bottom = offsetY + buttonHeight,
                offsetX = offsetX,
            }
        else
            -- 渲染快捷键列表
            for _, actionInfo in ipairs(actions) do
                n = n + 1
                local top = offsetY
                local bottom = offsetY + buttonHeight + 2
                local capAction = actionInfo  -- 捕获
                content[n] = {
                    dataIndex = n,
                    templateKey = "KeybindEntry",
                    setupFunc = function(obj)
                        -- 仅以动作名为键，渲染时从 Keybinds 读取现值，避免滚动复用后显示回退
                        obj:SetKeybindByActionName(capAction.name)
                    end,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    top = top,
                    bottom = bottom,
                    offsetX = offsetX,
                }
                offsetY = bottom
            end
            
            -- 底部提示
            offsetY = offsetY + Def.ButtonSize
            n = n + 1
            content[n] = {
                dataIndex = n,
                templateKey = "Header",
                setupFunc = function(obj)
                    obj:SetText(ADT.L["Keybinds Housing Only Hint"])
                    SetTextColor(obj.Label, Def.TextColorWarn or {1, 0.82, 0})
                    if obj.Left then obj.Left:Hide() end
                    if obj.Right then obj.Right:Hide() end
                    if obj.Divider then obj.Divider:Hide() end
                    obj.Label:SetJustifyH("LEFT")
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                top = offsetY,
                bottom = offsetY + buttonHeight,
                offsetX = offsetX,
            }
            
            -- 恢复默认：改为明确的按钮控件，避免整块区域可点
            offsetY = offsetY + buttonHeight + 8
            n = n + 1
            local resetBtnH = 24
            local resetBtnW = 120
            content[n] = {
                dataIndex = n,
                templateKey = "CenterButton",
                setupFunc = function(btn)
                    -- 统一文案（由 i18n 提供）；按钮样式更直观
                    if btn.SetText then btn:SetText(ADT.L["Reset All Keybinds"]) end
                    btn:SetScript("OnClick", function()
                        if ADT.Keybinds and ADT.Keybinds.ResetAllToDefaults then
                            ADT.Keybinds:ResetAllToDefaults()
                            if ADT.Notify then ADT.Notify(ADT.L["Keybinds Reset Done"]) end
                            MainFrame:ShowKeybindsCategory(categoryKey)
                        end
                    end)
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                top = offsetY,
                bottom = offsetY + resetBtnH,
                -- 左侧对齐：不再占用整行点击区域
                offsetX = offsetX,
            }
        end
        
        self.ModuleTab.ScrollView:SetContent(content, false)
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
    end
end


local function CreateUI()
    local pageHeight = Def.PageHeight
    
    -- 紧凑布局：左侧宽度按“分类文本宽度”动态计算
    local sideSectionWidth = ComputeSideSectionWidth()
    MainFrame.sideSectionWidth = sideSectionWidth
    -- 右侧仅保留预览，默认更窄；后续在 UpdateAutoWidth 中会按可用空间动态压缩/放宽
    local rightSectionWidth = math.min(sideSectionWidth, 160)
    MainFrame.rightSectionWidth = rightSectionWidth
    local centralSectionWidth = 340  -- 中间：图标 + 长装饰名称(如"小型锯齿奥格瑞玛栅栏") + 数量

    -- KISS：Dock 主体只包裹“右侧内容区”，不再把左侧/右侧栏并入自身宽度，
    -- 以免在 /fstack 中出现超出可见区域的大命中框。
    MainFrame:SetSize(centralSectionWidth, pageHeight)
    -- 记录 Dock 的“期望高度”（单一权威）：LayoutManager 会按此值在大屏恢复显示行数，
    -- 小屏仅裁剪，不改变该期望。
    MainFrame._ADT_DesiredHeight = pageHeight
    -- 固定停靠：由我们统一控制定位与尺寸，不再恢复历史尺寸
    MainFrame:SetToplevel(true)
    
    -- 禁止玩家拖动移动（固定右侧停靠）
    MainFrame:SetMovable(false)
    -- 修复：主框体不吃鼠标，避免其“透明区域”向左越界拦截 LeftPanel 点击。
    -- 世界交互的屏蔽改由局部 MouseBlocker 负责（仅覆盖右侧可见区域）。
    MainFrame:EnableMouse(false)
    if MainFrame.SetPropagateMouseClicks then MainFrame:SetPropagateMouseClicks(false) end
    if MainFrame.SetPropagateMouseMotion then MainFrame:SetPropagateMouseMotion(false) end
    MainFrame:RegisterForDrag() -- 清空注册（保持无拖拽）
    MainFrame:SetScript("OnDragStart", nil)
    MainFrame:SetScript("OnDragStop", nil)
    MainFrame:SetClampedToScreen(true)

    -- 顶部大 Header（对标 HouseEditor Storage 视觉）
    do
        local headerHeight = Def.HeaderHeight or 68
        local Header = CreateFrame("Frame", nil, MainFrame)
        MainFrame.Header = Header
        -- Header 仅覆盖右侧内容区：左缘始终贴 MainFrame 本身，不再参考模板 LeftSection
        Header:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 0, 0)
        Header:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", 0, 0)
        Header:SetHeight(headerHeight)

        -- Header 局部背景（只填充 Header 高度，避免再次制造“大范围背景”）
        -- 背景填充层（BACKGOUND）：与内容区同底色，保证与下方 CenterBG 过渡自然
        local fill = Header:CreateTexture(nil, "BACKGROUND")
        MainFrame.HeaderBackgroundFill = fill
        fill:SetAtlas("housing-basic-panel-background")
        fill:SetPoint("TOPLEFT", Header, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", Header, "BOTTOMRIGHT", 0, 0)

        -- 装饰性顶端弧形（ARTWORK）：仅覆盖 Header 内部，不越界
        local bg = Header:CreateTexture(nil, "ARTWORK")
        MainFrame.HeaderBackground = bg
        bg:SetAtlas("house-chest-header-bg")
        bg:SetAllPoints(Header)

        local title = Header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        MainFrame.HeaderTitle = title
        title:SetPoint("LEFT", Header, "LEFT", Def.HeaderTitleOffsetX or 22, Def.HeaderTitleOffsetY or -10)
        title:SetJustifyH("LEFT")
        if Def.ShowHeaderTitle then
            title:SetText(ADT.L["Addon Full Name"])
            title:Show()
        else
            title:SetText("")
            title:Hide()
        end

        -- 向下顺延主体区域：将左右分栏的顶部锚到 Header 底部
        if MainFrame.LeftSection then
            MainFrame.LeftSection:ClearAllPoints()
            -- 左侧分类容器顶对 Header 底部，高度稍后按内容动态设置
            MainFrame.LeftSection:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 0, -headerHeight)
        end

        if MainFrame.RightSection then
            -- 右侧面板已废弃：保持隐藏且不参与布局
            MainFrame.RightSection:Hide()
            MainFrame.RightSection:ClearAllPoints()
            MainFrame.RightSection:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", 0, 0)
            MainFrame.RightSection:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
            MainFrame.RightSection:SetWidth(0)
        end

        -- 根因治理：移除“右侧鼠标阻挡层”。
        -- 统一原则：Dock 主框体自身禁鼠；所有可交互行为仅来自其子控件。
        -- 因此不再创建 MouseBlocker，避免任何越界遮挡 LeftPanel 的风险。
        if MainFrame.MouseBlocker then
            MainFrame.MouseBlocker:Hide()
            MainFrame.MouseBlocker:SetScript("OnMouseDown", nil)
            MainFrame.MouseBlocker:SetScript("OnMouseUp", nil)
            MainFrame.MouseBlocker:EnableMouse(false)
            MainFrame.MouseBlocker = nil
        end

        -- Header 工具按钮：齿轮（Atlas：decor-controls-settings-*）
        do
            local cfg = (ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.GearButton) or {}
            local size = tonumber(cfg.size) or (Def.ButtonSize or 28)
            local btn = CreateFrame('Button', nil, Header)
            MainFrame._ADT_GearButton = btn
            btn:SetSize(size, size)
            -- 层级与 FrameLevel 可由配置调整
            if cfg.strata then btn:SetFrameStrata(cfg.strata) end
            local baseLvl = Header:GetFrameLevel() or 0
            local biasLvl = tonumber(cfg.levelBias) or 2
            btn:SetFrameLevel(baseLvl + biasLvl)
            btn:SetNormalAtlas('decor-controls-settings-default')
            btn:SetPushedAtlas('decor-controls-settings-pressed')
            btn:SetHighlightAtlas('decor-controls-settings-active')
            btn:GetHighlightTexture():SetAlpha(0.35)

            -- 选中覆盖层：表现“折叠已开启”
            local sel = btn:CreateTexture(nil, 'OVERLAY')
            btn.ActiveOverlay = sel
            sel:SetAllPoints(btn)
            sel:SetAtlas('decor-controls-settings-active')
            sel:SetAlpha(1.0)
            sel:Hide()

            -- 简化版：始终锚到 Header 的右上角，固定偏移。
            -- 说明：DecorCount 先后会被我们 graft 到 Header 右侧（偏移约 -12），
            -- 齿轮固定 -44，视觉上稳定地位于 DecorCount 左侧，无需等待时序。
            local function AnchorToDecorCount()
                btn:ClearAllPoints()
                local p  = cfg.point or 'RIGHT'
                local rp = cfg.relPoint or p
                local x  = tonumber(cfg.offsetX) or -44
                local y  = tonumber(cfg.offsetY) or -2
                btn:SetPoint(p, Header, rp, x, y)
                btn:Show(); btn:SetAlpha(1)
                return true
            end

            -- 一次到位，无需轮询
            AnchorToDecorCount()

            btn:SetScript('OnClick', function()
                if ADT and ADT.DockUI and ADT.DockUI.ToggleCollapsed then
                    ADT.DockUI.ToggleCollapsed()
                end
                if ADT and ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.button') end
            end)

            -- KISS：不显示鼠标提示（防止覆盖 DecorCount 视觉/避免干扰）
            btn:SetScript('OnEnter', nil)
            btn:SetScript('OnLeave', nil)

            -- 初始根据 DB 同步一次外观
            if ADT and ADT.DockUI and ADT.DockUI.ApplyCollapsedAppearance then
                C_Timer.After(0, ADT.DockUI.ApplyCollapsedAppearance)
            end

            -- 对外：当官方 DecorCount 出现或移动后，允许请求我们重新贴紧它
            ADT.DockUI.ReanchorHeaderWidgets = function()
                if not (MainFrame and MainFrame.Header and MainFrame._ADT_GearButton) then return end
                AnchorToDecorCount()
            end
        end
    end

    -- 禁止缩放：移除右下角抓手，并锁定最小尺寸约束仅用于内部自适应
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

        MainFrame:SetResizable(false)
        if MainFrame.SetResizeBounds then MainFrame:SetResizeBounds(minW, minH) end
        -- 隐藏并禁用原抓手
        if MainFrame.ResizeGrip then MainFrame.ResizeGrip:Hide() end
    end

    -- 固定停靠函数：右侧对齐，顶部与左侧 StoragePanel 对齐
    function MainFrame:ApplyDockPlacement()
        local parent = UIParent
        if HouseEditorFrame and HouseEditorFrame:IsShown() then
            parent = HouseEditorFrame
        end

        local topY = parent:GetTop() or 0
        local yOffset
        -- 若布局管理器提供了纵向覆写，则以其为单一权威，
        -- 避免 UpdateAutoWidth / AnchorWatcher 反复把 Dock 拉回顶部。
        if self._ADT_VerticalOffsetOverride ~= nil then
            yOffset = tonumber(self._ADT_VerticalOffsetOverride) or 0
        else
            local targetTop = topY
            if HouseEditorFrame and HouseEditorFrame.StoragePanel and HouseEditorFrame.StoragePanel:GetTop() then
                targetTop = HouseEditorFrame.StoragePanel:GetTop()
            end
            yOffset = (targetTop or topY) - topY
        end

        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -Def.ScreenRightMargin, yOffset)
        -- 静态左窗需要跟随重新贴边
        if USE_STATIC_LEFT_PANEL and self.UpdateStaticLeftPlacement then
            C_Timer.After(0, function() if self:IsShown() then self:UpdateStaticLeftPlacement() end end)
        end
    end

    -- 自动宽度：根据当前可见内容的字符串宽度，动态放宽中央区域
    function MainFrame:UpdateAutoWidth()
        local sidew = tonumber(self.LeftSection and self.LeftSection:GetWidth()) or tonumber(self.sideSectionWidth) or ComputeSideSectionWidth() or 180
        -- 取消外层左右额外留白；模板已提供 Label 左28/右28 的内部留白。
        local margin = 0

        local maxNeeded = 0
        local sv = self.ModuleTab and self.ModuleTab.ScrollView
        if sv and sv._templates then
            local function accumulate(poolKey, getter)
                local pool = sv._templates[poolKey]
                if not pool then return end
                for _, obj in pool:EnumerateActive() do
                    local w
                    if getter then w = getter(obj) end
                    if not w and obj.GetDesiredWidth then w = obj:GetDesiredWidth() end
                    if not w then
                        -- 兜底：尝试常见字段
                        local fs = (obj.Label or obj.Name)
                        if fs and fs.GetStringWidth then w = (fs:GetStringWidth() or 0) end
                    end
                    if type(w) == 'number' then maxNeeded = math.max(maxNeeded, math.ceil(w)) end
                end
            end
            accumulate("Entry")
            accumulate("DecorItem")
            accumulate("Header")
            accumulate("KeybindEntry")
        end

        -- 合并 SubPanel 的宽度需求（由 SubPanel 自行测量并上报）
        local subNeed = 0
        do
            local sub = self.SubPanel or (self.EnsureSubPanel and self:EnsureSubPanel())
            if sub and sub.GetDesiredCenterWidth then
                subNeed = tonumber(sub:GetDesiredCenterWidth()) or 0
            end
        end

        -- 至少保证一个合理的最小值（配置驱动）
        local minCenter = 240
        if ADT and ADT.GetHousingCFG then
            local C = ADT.GetHousingCFG()
            if C and C.Layout and type(C.Layout.dockMinCenterWidth) == 'number' then
                minCenter = math.max(0, math.floor(C.Layout.dockMinCenterWidth))
            end
        end
        local wantedCenter = math.max(minCenter, maxNeeded, subNeed)
        -- 视口最大宽度限制（避免超出屏幕）
        local parent = self:GetParent() or UIParent
        local viewport = (parent.GetWidth and parent:GetWidth() or 1600) - Def.ScreenRightMargin - 4
        local maxTotal = viewport
        if ADT and ADT.GetHousingCFG then
            local C = ADT.GetHousingCFG()
            local r = C and C.Layout and C.Layout.dockMaxTotalWidthRatio
            if type(r) == 'number' and r > 0 and r <= 1 then
                maxTotal = math.floor(viewport * r)
            end
        end
        -- Dock 主体宽度 = 中央区需求（不再把左侧栏并入自身宽度），避免出现“看似更大”的透明命中区域
        local targetTotal = wantedCenter
        if targetTotal > maxTotal then targetTotal = maxTotal end
        targetTotal = math.floor(targetTotal + 0.5)
        local currentTotal = math.floor((self:GetWidth() or 0) + 0.5)
        if targetTotal ~= currentTotal then
            self:SetWidth(targetTotal)
        end
        self.sideSectionWidth = sidew
        self._widthIsCentralOnly = true

        -- 同步中央区域内各条目实际宽度（单一权威：由 MainFrame/LeftSection 推导）
        self:_SyncCentralTemplateWidths(true)

        -- 更新锚点确保紧贴右缘
        self:ApplyDockPlacement()
    end
    
    -- 重要：FrameContainer 仅用于布局与滚轮，不应拦截鼠标点击/悬停。
    -- 否则会导致左侧滑出列表无法收到 OnEnter/OnClick。
    MainFrame.FrameContainer:EnableMouse(false)
    MainFrame.FrameContainer:EnableMouseMotion(false)
    MainFrame.FrameContainer:EnableMouseWheel(true)
    MainFrame.FrameContainer:SetScript("OnMouseWheel", function(self, delta) end)
    -- 收缩 FrameContainer：避免在 /fstack 中出现一个覆盖右上角的大透明框体。
    -- 说明：FrameContainer 仅作为模板键转发的占位容器；实际可见内容都由 Header/CentralSection/MainFrame 创建并重新锚定。
    -- 因此把 FrameContainer 改为 1x1 的不可交互框体，放在 MainFrame 左上角即可。
    do
        local FC = MainFrame.FrameContainer
        if FC then
            FC:ClearAllPoints()
            FC:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 0, 0)
            FC:SetSize(1, 1)
            -- 注意：不要设置父容器 Alpha，否则其子元素（CentralSection/ModuleTab）会被一并透明，导致“内容存在但不可见”。
            -- 仅缩小尺寸、禁用鼠标即可避免 /fstack 出现覆盖全屏的大框。
        end
    end
    -- TabButtonContainer 已从模板移除，无需显式关闭



    local baseFrameLevel = MainFrame:GetFrameLevel()

    local LeftSection = MainFrame.LeftSection
    local CentralSection = MainFrame.CentralSection
    local RightSection = MainFrame.RightSection
    local Tab1 = MainFrame.ModuleTab

    -- 顶部标签布局：模板 LeftSection 仅用于提供锚点；
    -- 实际可见左窗由 LeftPanel.Build 创建的 LeftSlideContainer 实现。
    if LeftSection then
        LeftSection:SetWidth(sideSectionWidth)
        if LeftSection.EnableMouse then LeftSection:EnableMouse(false) end
        if LeftSection.EnableMouseMotion then LeftSection:EnableMouseMotion(false) end
    end
    
    -- 移除整个右侧区域：不再占据任何宽度，也不创建任何子内容
    if RightSection then
        RightSection:Hide()
        RightSection:SetWidth(0)
        RightSection:ClearAllPoints()
        RightSection:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", 0, 0)
        RightSection:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    end

    -- CentralSection：顶部必须“紧贴 Header 底部”作为锚点，
    -- 不能再与 LeftSection 顶部对齐（那样会把内容顶到 Header 区域内部）。
    CentralSection:ClearAllPoints()
    CentralSection:SetPoint("TOPLEFT", MainFrame.Header or MainFrame, "BOTTOMLEFT", 0, 0)
    CentralSection:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    if CentralSection.EnableMouse then CentralSection:EnableMouse(false) end
    if CentralSection.EnableMouseMotion then CentralSection:EnableMouseMotion(false) end


    -- LeftSection：改为调用 LeftPanel 模块统一构建（唯一权威，移除旧内联实现）
    do
        local DockLeft = ADT.DockLeft
        if DockLeft and DockLeft.Build then
            DockLeft.Build(MainFrame, sideSectionWidth)
        end
    end

    -- 右侧木质边框范围（仅包裹右侧区域，避免覆盖左窗）
    do
        local bf = MainFrame.BorderFrame
        if bf and MainFrame.Header then
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", MainFrame.Header, "TOPLEFT", 0, 0)
            bf:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- 右侧整栏已移除；下面创建中央区域与其背景
    do  -- CentralSection（设置列表所在区域）
        -- KISS：不再创建“统一右侧背景”（RightUnifiedBackground）。
        -- 该大面积贴图会在 /fstack 中对应到 MainFrame，从而被误认为“幽灵面板”。
        -- 我们仅保留 CentralSection 自身的局部背景即可。
        if MainFrame.RightUnifiedBackground then
            MainFrame.RightUnifiedBackground:Hide()
            MainFrame.RightUnifiedBackground = nil
        end

        -- 中央区域独立背景
        if MainFrame.CenterBackground then MainFrame.CenterBackground:Hide() end
        local CenterBG = MainFrame:CreateTexture(nil, "BACKGROUND")
        MainFrame.CenterBackground = CenterBG
        CenterBG:SetAtlas("housing-basic-panel-background")
        CenterBG:SetPoint("TOPLEFT", CentralSection, "TOPLEFT", 0, 0)
        CenterBG:SetPoint("BOTTOMRIGHT", CentralSection, "BOTTOMRIGHT", 0, Def.CenterBGInsetBottom or 2)

        -- 暂不显示自研滚动条，后续将切换为暴雪 ScrollBox 体系
        MainFrame.ModuleTab.ScrollBar = nil

        local ScrollView = API.CreateListView(Tab1)
        MainFrame.ModuleTab.ScrollView = ScrollView
        -- 列表视图顶端 = CentralSection 顶端（亦即 Header 底部）
        -- 给一段向内间距（Def.ScrollViewInsetTop），避免文字紧贴分隔线。
        ScrollView:SetPoint("TOPLEFT", CentralSection, "TOPLEFT", 0, - (Def.ScrollViewInsetTop or 6))
        ScrollView:SetPoint("BOTTOMRIGHT", CentralSection, "BOTTOMRIGHT", 0, (Def.ScrollViewInsetBottom or 2))
        ScrollView:SetStepSize(Def.ButtonSize * 2)
        ScrollView:OnSizeChanged()
        ScrollView:EnableMouseBlocker(true)
        ScrollView:SetBottomOvershoot(Def.CategoryGap)
        -- 不显示滚动条
        ScrollView:SetAlwaysShowScrollBar(false)
        ScrollView:SetShowNoContentAlert(true)
        ScrollView:SetNoContentAlertText(CATALOG_SHOP_NO_SEARCH_RESULTS or "")


        -- 初始右侧可用宽度，随着窗口缩放动态更新
        local function ComputeCenterWidth()
            local w = tonumber(CentralSection:GetWidth()) or 0
            if w <= 0 then
                local total = tonumber(MainFrame:GetWidth()) or 0
                local leftw = tonumber(MainFrame.sideSectionWidth) or 0
                local rightw = tonumber(MainFrame.rightSectionWidth) or leftw
                w = math.max(0, total - leftw - rightw)
            end
            -- 不在此处扣除外层 margin，避免与模板自身内边距叠加导致有效文本宽度过窄。
            w = API.Round(w)
            if w < 120 then w = 120 end
            return w
        end
        -- 梳理：所有列表项在渲染时都会以 GetRightPadding() 作为左侧缩进，
        -- 因而条目真实宽度 = 容器宽度 - 该缩进。统一在此处扣除，确保对齐一致。
        MainFrame.centerButtonWidth = ComputeCenterWidth() - 2 * GetRightPadding()
        Def.centerButtonWidth = MainFrame.centerButtonWidth


        local function EntryButton_Create()
            local obj = CreateSettingsEntry(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
            if obj.HideTextHighlight then obj:HideTextHighlight() end
            return obj
        end

        ScrollView:AddTemplate("Entry", EntryButton_Create)


        local function Header_Create()
            local obj = CreateSettingsHeader(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
            return obj
        end

        ScrollView:AddTemplate("Header", Header_Create)

        -- 小型动作按钮模板（用于“恢复默认”）。
        local function CenterButton_Create()
            local btn = CreateFrame("Button", nil, ScrollView, "UIPanelButtonTemplate")
            btn:SetSize(120, 24)
            return btn
        end

        ScrollView:AddTemplate("CenterButton", CenterButton_Create)


        -- 装饰项模板（用于临时板和最近放置列表）
        local function DecorItem_Create()
            local obj = CreateDecorItemEntry(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, 36)
            return obj
        end

        ScrollView:AddTemplate("DecorItem", DecorItem_Create)

        -- 染色预设条目模板（显示色块序列）
        local DyePresetItemMixin = {}

        function DyePresetItemMixin:SetPresetData(index, preset, categoryInfo)
            self.presetIndex = index
            self.preset = preset
            self.categoryInfo = categoryInfo

            -- 构建色块显示文本
            local colorStr = ""
            if preset and preset.colors then
                for _, colorID in ipairs(preset.colors) do
                    colorStr = colorStr .. self:_makeColorBlock(colorID or 0)
                end
            end

            -- 设置显示：预设序号 + 色块
            local label = string.format("%s %d: %s", ADT.L["Preset"] or "预设", index, colorStr)
            self.Label:SetText(label)
        end

        function DyePresetItemMixin:_makeColorBlock(dyeColorID)
            -- 调用 DyeClipboard 的色块生成方法
            if ADT.DyeClipboard and ADT.DyeClipboard._makeColorBlock then
                return ADT.DyeClipboard:_makeColorBlock(dyeColorID)
            end
            -- 降级：简单色块占位
            return "|TInterface\\BUTTONS\\WHITE8X8:12:12:0:0:8:8:0:8:0:8|t"
        end

        function DyePresetItemMixin:OnEnter()
            self.Background:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            SetTextColor(self.Label, Def.TextColorHighlight)
        end

        function DyePresetItemMixin:OnLeave()
            self.Background:SetColorTexture(0, 0, 0, 0.1)
            SetTextColor(self.Label, Def.TextColorNormal)
        end

        function DyePresetItemMixin:OnClick(button)
            if self.categoryInfo and self.categoryInfo.onItemClick then
                self.categoryInfo.onItemClick(self.presetIndex, button)
                -- 刷新列表
                if button == "RightButton" then
                    C_Timer.After(0.05, function()
                        if MainFrame.ShowDyePresetsCategory then
                            MainFrame:ShowDyePresetsCategory(self.categoryInfo.key)
                        end
                    end)
                end
            end
        end

        local function CreateDyePresetItemEntry(parent)
            local f = CreateFrame("Button", nil, parent)
            Mixin(f, DyePresetItemMixin)
            f:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, 32)
            f:RegisterForClicks("AnyUp")

            -- 背景
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.1)
            f.Background = bg

            -- 标签（显示色块序列）
            local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetJustifyH("LEFT")
            label:SetPoint("LEFT", f, "LEFT", 8, 0)
            label:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            f.Label = label

            f:SetScript("OnEnter", f.OnEnter)
            f:SetScript("OnLeave", f.OnLeave)
            f:SetScript("OnClick", f.OnClick)

            return f
        end

        local function DyePresetItem_Create()
            local obj = CreateDyePresetItemEntry(ScrollView)
            obj:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, 32)
            return obj
        end

        ScrollView:AddTemplate("DyePresetItem", DyePresetItem_Create)

        -- 快捷键条目模板（用于快捷键分类）
        local KeybindEntryMixin = {}

        -- 单一权威：所有显示数据一律从 ADT.Keybinds 现存配置读取
        -- 说明：过去使用构建时快照（actionInfo）导致“滚动复用后回退到旧文本”。
        -- 现改为按 actionName 即时查询，彻底消除快照失真。
        function KeybindEntryMixin:SetKeybindByActionName(actionName)
            self.actionName = actionName
            -- 动作显示名
            local displayName = (ADT.Keybinds and ADT.Keybinds.GetActionDisplayName and ADT.Keybinds:GetActionDisplayName(actionName)) or actionName
            if self.ActionLabel then
                self.ActionLabel:SetText(displayName)
            end
            -- 按键显示名
            local key = ADT.Keybinds and ADT.Keybinds.GetKeybind and ADT.Keybinds:GetKeybind(actionName) or ""
            local keyText = ADT.Keybinds and ADT.Keybinds.GetKeyDisplayName and ADT.Keybinds:GetKeyDisplayName(key) or ""
            if self.KeyLabel then
                if keyText == "" then
                    keyText = ADT.L["Not Set"]
                    SetTextColor(self.KeyLabel, Def.TextColorDisabled or {0.5, 0.5, 0.5})
                else
                    SetTextColor(self.KeyLabel, {1, 0.82, 0}) -- 金色
                end
                self.KeyLabel:SetText(keyText)
            end
            self:UpdateRecordingState(false)
        end
        
        function KeybindEntryMixin:UpdateRecordingState(isRecording)
            self.isRecording = isRecording
            local headerHint = MainFrame._keybindCategoryHint
            if isRecording then
                -- 录制中状态
                if self.KeyLabel then
                    self.KeyLabel:SetText(ADT.L["Press Key"])
                    SetTextColor(self.KeyLabel, {1, 0.82, 0}) -- 金色
                end
                if self.KeyBorder then
                    self.KeyBorder:SetColorTexture(1, 0.82, 0, 1)  -- 金色边框
                end
                -- 在 Header 区域显示提示
                if headerHint then
                    headerHint:SetText(ADT.L["ESC Cancel"])
                    headerHint:SetTextColor(1, 0.82, 0, 1)  -- 金色
                end
            else
                -- 恢复正常状态
                if self.KeyBorder then
                    self.KeyBorder:SetColorTexture(0.3, 0.3, 0.3, 1)  -- 灰色边框
                end
                -- 清除 Header 提示
                if headerHint then
                    headerHint:SetText("")
                end
            end
        end
        
        function KeybindEntryMixin:OnRecordButtonClick()
            if self.isRecording then
                -- 取消录制
                self:UpdateRecordingState(false)
                -- 恢复当前配置显示（而非旧快照）
                self:SetKeybindByActionName(self.actionName)
                MainFrame._recordingKeybindEntry = nil
            else
                -- 开始录制
                -- 先取消其他正在录制的条目
                if MainFrame._recordingKeybindEntry and MainFrame._recordingKeybindEntry ~= self then
                    MainFrame._recordingKeybindEntry:UpdateRecordingState(false)
                    MainFrame._recordingKeybindEntry:SetKeybindByActionName(MainFrame._recordingKeybindEntry.actionName)
                end
                MainFrame._recordingKeybindEntry = self
                self:UpdateRecordingState(true)
            end
        end
        
        function KeybindEntryMixin:OnClearButtonClick()
            if self.actionName and ADT.Keybinds then
                ADT.Keybinds:SetKeybind(self.actionName, "")
                -- 刷新显示（即时读取单一权威配置）
                self:SetKeybindByActionName(self.actionName)
            end
        end
        
        function KeybindEntryMixin:OnKeyDown(key)
            if not self.isRecording then return end
            
            -- 忽略单独的修饰键
            if key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT" then return end
            if key == "LCTRL" or key == "RCTRL" or key == "CTRL" then return end
            if key == "LALT" or key == "RALT" or key == "ALT" then return end
            if key == "ESCAPE" then
                -- ESC 取消录制（恢复当前配置显示）
                self:UpdateRecordingState(false)
                self:SetKeybindByActionName(self.actionName)
                MainFrame._recordingKeybindEntry = nil
                return
            end
            
            -- 构建按键字符串
            local modifiers = ""
            if IsControlKeyDown() then modifiers = modifiers .. "CTRL-" end
            if IsShiftKeyDown() then modifiers = modifiers .. "SHIFT-" end
            if IsAltKeyDown() then modifiers = modifiers .. "ALT-" end
            
            local finalKey = modifiers .. key
            
            -- 保存按键
            if self.actionName and ADT.Keybinds then
                ADT.Keybinds:SetKeybind(self.actionName, finalKey)
                -- 刷新显示（从配置读取最新值，避免本地快照）
                self:SetKeybindByActionName(self.actionName)
            end
            
            self:UpdateRecordingState(false)
            MainFrame._recordingKeybindEntry = nil
        end

        function KeybindEntryMixin:GetDesiredWidth()
            -- 动态计算所需宽度：基于实际文本宽度 + 按键框 + 左右内边距
            local KCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.KeybindUI) or {}
            local keyBoxWidth = KCFG.keyBoxWidth or 100
            local actionToKeyGap = KCFG.actionToKeyGap or 8
            local leftPad  = KCFG.rowLeftPad or 8
            local rightPad = KCFG.rowRightPad or 8

            local minText = KCFG.actionLabelWidth or 120
            local textWidth = minText
            if self.ActionLabel and self.ActionLabel.GetStringWidth then
                local actualWidth = self.ActionLabel:GetStringWidth()
                if actualWidth and actualWidth > 0 then
                    textWidth = math.max(minText, actualWidth + 10) -- 额外留白
                end
            end

            return leftPad + textWidth + actionToKeyGap + keyBoxWidth + rightPad
        end

        local function KeybindEntry_Create()
            -- 读取配置（配置驱动，单一权威）
            local KCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.KeybindUI) or {}
            local actionLabelWidth = KCFG.actionLabelWidth or 120
            local keyBoxWidth = KCFG.keyBoxWidth or 100
            local keyBoxHeight = KCFG.keyBoxHeight or 22
            local actionToKeyGap = KCFG.actionToKeyGap or 8
            local rowLeftPad  = KCFG.rowLeftPad or 8
            local rowRightPad = KCFG.rowRightPad or 8
            local borderNormal = KCFG.borderNormal or { r = 0.3, g = 0.3, b = 0.3, a = 1 }
            local borderHover = KCFG.borderHover or { r = 0.8, g = 0.6, b = 0, a = 1 }
            local bgColor = KCFG.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 1 }
            
            local f = CreateFrame("Button", nil, ScrollView)
            Mixin(f, KeybindEntryMixin)
            f:SetSize(MainFrame.centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
            f:EnableMouse(true)
            f:EnableKeyboard(true)
            f:SetPropagateKeyboardInput(true)
            f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            
            -- 背景
            local bg = f:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0.1)
            f.Background = bg
            
            -- 动作名称标签（左侧）
            local actionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            actionLabel:SetJustifyH("LEFT")
            f.ActionLabel = actionLabel

            -- 按键框容器（右对齐，保证右侧留边对称）
            local keyBox = CreateFrame("Button", nil, f)
            keyBox:SetSize(keyBoxWidth, keyBoxHeight)
            keyBox:ClearAllPoints()
            keyBox:SetPoint("RIGHT", f, "RIGHT", -rowRightPad, 0)
            keyBox:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            f.KeyBox = keyBox

            -- 重新锚定动作名称标签：左贴父，右贴按键框左侧，留出间距
            actionLabel:ClearAllPoints()
            actionLabel:SetPoint("LEFT", f, "LEFT", rowLeftPad, 0)
            actionLabel:SetPoint("RIGHT", keyBox, "LEFT", -actionToKeyGap, 0)
            if actionLabel.SetMaxLines then actionLabel:SetMaxLines(1) end
            if actionLabel.SetWordWrap then actionLabel:SetWordWrap(false) end
            
            -- 按键框背景（深色边框）
            local keyBg = keyBox:CreateTexture(nil, "BACKGROUND")
            keyBg:SetAllPoints()
            keyBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
            f.KeyBackground = keyBg
            
            -- 按键框边框
            local keyBorder = keyBox:CreateTexture(nil, "BORDER")
            keyBorder:SetAllPoints()
            keyBorder:SetColorTexture(borderNormal.r, borderNormal.g, borderNormal.b, borderNormal.a)
            keyBorder:SetDrawLayer("BORDER", -1)
            f.KeyBorder = keyBorder
            
            -- 内边框（让背景看起来有边框）
            local keyInner = keyBox:CreateTexture(nil, "ARTWORK")
            keyInner:SetPoint("TOPLEFT", 1, -1)
            keyInner:SetPoint("BOTTOMRIGHT", -1, 1)
            keyInner:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
            f.KeyInner = keyInner
            
            -- 按键文本
            local keyLabel = keyBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            keyLabel:SetPoint("CENTER", keyBox, "CENTER", 0, 0)
            f.KeyLabel = keyLabel
            
            -- 按键框点击：左键录制，右键清除
            keyBox:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    f:OnClearButtonClick()
                else
                    f:OnRecordButtonClick()
                end
            end)
            
            -- 按键框悬停效果（使用 Header 区域的提示）
            keyBox:SetScript("OnEnter", function(self)
                if not f.isRecording then
                    keyBorder:SetColorTexture(borderHover.r, borderHover.g, borderHover.b, borderHover.a)
                    local headerHint = MainFrame._keybindCategoryHint
                    if headerHint then
                        local hintColor = KCFG.hintHover or { r = 0.6, g = 0.8, b = 1 }
                        local hintText = ADT.L["Right Click Clear"]
                        headerHint:SetText(hintText)
                        headerHint:SetTextColor(hintColor.r, hintColor.g, hintColor.b, 1)
                    end
                end
            end)
            
            keyBox:SetScript("OnLeave", function(self)
                if not f.isRecording then
                    keyBorder:SetColorTexture(borderNormal.r, borderNormal.g, borderNormal.b, borderNormal.a)
                    local headerHint = MainFrame._keybindCategoryHint
                    if headerHint then
                        headerHint:SetText("")
                    end
                end
            end)
            
            -- 键盘监听
            f:SetScript("OnKeyDown", function(self, key)
                if self.isRecording then
                    self:SetPropagateKeyboardInput(false)
                    self:OnKeyDown(key)
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)
            
            return f
        end
        
        ScrollView:AddTemplate("KeybindEntry", KeybindEntry_Create)
    end


    -- 取消自定义边框相关占位与调用，改由顶部 UIPanelCloseButton 控制关闭

    -- 中央内容区创建完毕，应用待选标签
    MainFrame:ApplyInitialTabSelection()


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
        if MainFrame.ApplyDockPlacement then MainFrame:ApplyDockPlacement() end
        -- KISS：优先使用“当前内存中的已选分类”，仅在无当前状态时才回退到持久化记录
        local key = MainFrame.currentDecorCategory or MainFrame.currentDyePresetsCategory or MainFrame.currentAboutCategory or MainFrame.currentSettingsCategory or (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey'))
        -- 首次无记录时，显式记录并使用 "Housing" 作为默认分类
        if (not ADT.GetDBValue('LastCategoryKey')) then
            if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', 'Housing') end
            key = 'Housing'
        end
        -- 显式首选“通用”（Housing）作为回退；若无则再选第一个设置类
        if not key then
            local housing = CommandDock:GetCategoryByKey('Housing')
            if housing and housing.categoryType == 'settings' then
                key = 'Housing'
            end
        end
        if ADT and ADT.DebugPrint then
            local cw = MainFrame.CentralSection and MainFrame.CentralSection:GetWidth() or 0
            local ch = MainFrame.CentralSection and MainFrame.CentralSection:GetHeight() or 0
            ADT.DebugPrint(string.format("[SettingsPanel] OnShow: key=%s, center=%.1fx%.1f", tostring(key), cw, ch))
        end
        if USE_TOP_TABS and MainFrame.TopTabOwner and MainFrame.__tabIDFromKey then
            local id = MainFrame.__tabIDFromKey[key] or MainFrame.__tabIDFromKey['Housing'] or 1
            MainFrame.TopTabOwner:SetTab(id)
            return
        end

        -- 旧布局回退逻辑（补齐对染色预设分类的支持）
        local cat = key and CommandDock:GetCategoryByKey(key) or nil
        if cat and cat.categoryType == 'decorList' then
            MainFrame:ShowDecorListCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'dyePresetList' then
            MainFrame:ShowDyePresetsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'about' then
            MainFrame:ShowAboutCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'keybinds' then
            MainFrame:ShowKeybindsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'settings' then
            MainFrame:ShowSettingsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        else
            -- 默认回退到第一个“设置类”分类（若存在 Housing 优先）
            local all = CommandDock:GetSortedModules()
            local firstSettings
            -- Housing 优先
            for _, info in ipairs(all) do
                if info.key == 'Housing' and info.categoryType ~= 'decorList' and info.categoryType ~= 'about' then
                    firstSettings = 'Housing'; break
                end
            end
            -- 通用不存在时，取第一个设置类
            for _, info in ipairs(all) do
                if info.categoryType ~= 'decorList' and info.categoryType ~= 'about' then
                    firstSettings = firstSettings or info.key; break
                end
            end
            if firstSettings then
                MainFrame:ShowSettingsCategory(firstSettings)
                MainFrame:HighlightCategoryByKey(firstSettings)
            else
                MainFrame:RefreshFeatureList()
            end
        end
        if MainFrame.UpdateAutoWidth then MainFrame:UpdateAutoWidth() end
        if (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) and MainFrame.UpdateStaticLeftPlacement then C_Timer.After(0, function() if MainFrame:IsShown() then MainFrame:UpdateStaticLeftPlacement() end end) end
    end)

    -- 单一 OnSizeChanged：当窗口缩放时，仅调整右侧内容宽度
    MainFrame:SetScript("OnSizeChanged", function(self)
        local CentralSection = self.CentralSection
        if not CentralSection or not self.ModuleTab or not self.ModuleTab.ScrollView then return end
        local total = tonumber(self:GetWidth()) or 0
        local leftw = tonumber(self.sideSectionWidth) or 0
        local w = tonumber(CentralSection:GetWidth()) or (total - leftw)
        -- 修正：列表项左侧存在统一缩进 offsetX = GetRightPadding()，
        -- 条目实际可用宽度应扣除该缩进，避免右侧对齐越界。
        local newWidth = API.Round((w or 0)) - 2 * GetRightPadding()
        if newWidth < 120 then newWidth = 120 end
        if newWidth <= 0 then return end

        -- 同步左侧滑出容器宽度与收起偏移
        if self.LeftSlideContainer and self.LeftSection then
            local lw = tonumber(self.LeftSection:GetWidth()) or 0
            if lw > 0 then self.LeftSlideContainer:SetWidth(lw) end
            if self.LeftSlideDriver and self.GetLeftClosedOffset then
                local closed = self.GetLeftClosedOffset()
                if math.abs(self.LeftSlideDriver.target) > 0.5 then
                    self.LeftSlideDriver.target = closed
                    if math.abs(self.LeftSlideDriver.x - closed) < 1 then
                        self.LeftSlideDriver.x = closed
                        if self.LeftSlideDriver.onUpdate then self.LeftSlideDriver.onUpdate(closed) end
                    end
                end
            end
        end
        if self.centerButtonWidth ~= newWidth then
            self.centerButtonWidth = newWidth
            local ScrollView = self.ModuleTab.ScrollView
            ScrollView:CallObjectMethod("Entry", "SetWidth", newWidth)
            ScrollView:CallObjectMethod("Header", "SetWidth", newWidth)
            ScrollView:CallObjectMethod("DecorItem", "SetWidth", newWidth)
            ScrollView:CallObjectMethod("KeybindEntry", "SetWidth", newWidth)
            ScrollView:OnSizeChanged(true)
            if self.ModuleTab.ScrollBar and self.ModuleTab.ScrollBar.UpdateThumbRange then
                self.ModuleTab.ScrollBar:UpdateThumbRange()
            end
        end
    end)

    -- 初次创建后立即固定停靠并做一次自适应宽度
    if MainFrame.ApplyDockPlacement then MainFrame:ApplyDockPlacement() end
    if MainFrame.UpdateAutoWidth then MainFrame:UpdateAutoWidth() end

    -- 监听分辨率/缩放/编辑器模式变化，保持右侧贴边
    local AnchorWatcher = CreateFrame("Frame", nil, MainFrame)
    AnchorWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    AnchorWatcher:RegisterEvent("UI_SCALE_CHANGED")
    AnchorWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    AnchorWatcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    AnchorWatcher:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            if MainFrame and MainFrame.ApplyDockPlacement then MainFrame:ApplyDockPlacement() end
            if MainFrame and MainFrame.UpdateAutoWidth then MainFrame:UpdateAutoWidth() end
        end)
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

-- 订阅“进入编辑器自动打开 Dock”设置，实时应用默认显隐
if ADT and ADT.Settings and ADT.Settings.On then
    ADT.Settings.On('EnableDockAutoOpenInEditor', function()
        if ADT and ADT.DockUI and ADT.DockUI.ApplyPanelsDefaultVisibility then
            ADT.DockUI.ApplyPanelsDefaultVisibility()
        end
    end)
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

        CommandDock:UpdateCurrentSortMethod()
        if self.primaryCategoryPool then
            self:RefreshCategoryList()
        end
    end

    mode = mode or "standalone"
    self.mode = mode
    -- 关闭按钮由 UIPanelCloseButton 提供，无需额外控制
    self:UpdateLayout()
    -- 固定停靠：不再恢复历史位置，统一由 ApplyDockPlacement 控制
    -- 规则调整（KISS）：进入编辑模式即确保 SubPanel 存在且可见；
    -- 不再默认隐藏，避免“关闭 Dock / 退出编辑 / 重进”后子面板缺失。
    self:EnsureSubPanel()
    self:SetSubPanelShown(true)
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
                -- 进入编辑模式：无论是否默认开启，都先创建并显示 Dock 容器，
                -- 再按用户设置隐藏/显示“主体面板”。这样 SubPanel/清单仍可独立工作。
                MainFrame:ShowUI("editor")
                -- 若默认开启，则聚焦到“通用”分类；否则仅保持容器存在
                local v = ADT and ADT.GetDBValue and ADT.GetDBValue('EnableDockAutoOpenInEditor')
                local shouldAutoOpen = (v ~= false)
                if shouldAutoOpen then
                    C_Timer.After(0, function()
                        -- 优先恢复上次停留的分类；若无记录再回退到“通用”。
                        local key = (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey')) or 'Housing'
                        local cat = CommandDock and CommandDock.GetCategoryByKey and CommandDock:GetCategoryByKey(key)
                        if not cat then
                            key = 'Housing'
                            cat = CommandDock and CommandDock.GetCategoryByKey and CommandDock:GetCategoryByKey(key)
                        end
                        if cat then
                            if cat.categoryType == 'decorList' and MainFrame.ShowDecorListCategory then
                                MainFrame:ShowDecorListCategory(key)
                            elseif cat.categoryType == 'about' and MainFrame.ShowAboutCategory then
                                MainFrame:ShowAboutCategory(key)
                            elseif cat.categoryType == 'keybinds' and MainFrame.ShowKeybindsCategory then
                                MainFrame:ShowKeybindsCategory(key)
                            elseif MainFrame.ShowSettingsCategory then
                                MainFrame:ShowSettingsCategory(key)
                            end
                            if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', key) end
                        end
                    end)
                end
                -- 应用默认显隐（只影响 Dock 主体，不影响 SubPanel）
                C_Timer.After(0, function()
                    if ADT and ADT.DockUI and ADT.DockUI.ApplyPanelsDefaultVisibility then
                        ADT.DockUI.ApplyPanelsDefaultVisibility()
                    end
                end)
            end
            -- 调整层级确保在编辑器之上
            if HouseEditorFrame then
                -- 调整：主面板不再提升到 "TOOLTIP"，避免与 LeftPanel（同样在 TOOLTIP）互抢层级。
                -- 使用 "FULLSCREEN_DIALOG" 足以压过编辑器普通层，又能确保 LeftPanel 始终在其之上。
                MainFrame:SetParent(HouseEditorFrame)
                MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
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
