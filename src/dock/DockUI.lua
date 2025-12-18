
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
    -- 提升：LeftSection/CentralSection 等布局容器仅引用模板键
    local frameKeys = {"LeftSection", "CentralSection", "ModuleTab", "ChangelogTab", "TopTabOwner"}
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
    
    -- 使用 Housing 风格边框（木框九宫格 + 藤蔓角落装饰）
    -- 配置驱动：从 Housing_Config.lua 的 DockBorder 读取参数
    -- 注意：BorderFrame 层级很高(+100)，不能在此放背景
    local BCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.DockBorder) or {}
    local wfCfg = BCFG.WoodFrame or {}
    local cornerBase = BCFG.CornerBaseSize or { width = 54, height = 42 }
    local cornerScale = BCFG.CornerScale or 1.2
    local tlOff = BCFG.CornerTL or { x = -4, y = 2 }
    local trOff = BCFG.CornerTR or { x = 4, y = 2 }
    local blOff = BCFG.CornerBL or { x = -4, y = -2 }
    local brOff = BCFG.CornerBR or { x = 4, y = -2 }
    
    -- 主体：housing-wood-frame 九宫格边框（BORDER 层）
    local woodFrame = BorderFrame:CreateTexture(nil, "BORDER")
    woodFrame:SetPoint("TOPLEFT", BorderFrame, "TOPLEFT", 0, 0)
    woodFrame:SetPoint("BOTTOMRIGHT", BorderFrame, "BOTTOMRIGHT", 0, 0)
    woodFrame:SetAtlas(wfCfg.atlas or "housing-wood-frame")
    local margins = wfCfg.sliceMargins or 16
    woodFrame:SetTextureSliceMargins(margins, margins, margins, margins)
    woodFrame:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    BorderFrame.WoodFrame = woodFrame

    -- 四个角落藤蔓装饰（ARTWORK 层，覆盖木框角落）
    local cw = API.Round(cornerBase.width * cornerScale)
    local ch = API.Round(cornerBase.height * cornerScale)
    
    -- 左上角 TL
    local cornerTL = BorderFrame:CreateTexture(nil, "ARTWORK")
    cornerTL:SetAtlas("housing-dashboard-filigree-corner-TL")
    cornerTL:SetSize(cw, ch)
    cornerTL:SetPoint("TOPLEFT", BorderFrame, "TOPLEFT", tlOff.x, tlOff.y)
    BorderFrame.CornerTL = cornerTL

    -- 右上角 TR
    local cornerTR = BorderFrame:CreateTexture(nil, "ARTWORK")
    cornerTR:SetAtlas("housing-dashboard-filigree-corner-TR")
    cornerTR:SetSize(cw, ch)
    cornerTR:SetPoint("TOPRIGHT", BorderFrame, "TOPRIGHT", trOff.x, trOff.y)
    BorderFrame.CornerTR = cornerTR

    -- 左下角 BL
    local cornerBL = BorderFrame:CreateTexture(nil, "ARTWORK")
    cornerBL:SetAtlas("housing-dashboard-filigree-corner-BL")
    cornerBL:SetSize(cw, ch)
    cornerBL:SetPoint("BOTTOMLEFT", BorderFrame, "BOTTOMLEFT", blOff.x, blOff.y)
    BorderFrame.CornerBL = cornerBL

    -- 右下角 BR
    local cornerBR = BorderFrame:CreateTexture(nil, "ARTWORK")
    cornerBR:SetAtlas("housing-dashboard-filigree-corner-BR")
    cornerBR:SetSize(cw, ch)
    cornerBR:SetPoint("BOTTOMRIGHT", BorderFrame, "BOTTOMRIGHT", brOff.x, brOff.y)
    BorderFrame.CornerBR = cornerBR

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

    -- EL event listener moved to DockUI_Controller.lua
end
local SearchBox
local CategoryHighlight
local ActiveCategoryInfo = {}

-- 动态收敛左侧分类容器高度

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





-- 条目工厂（OptionToggleMixin、CreateSettingsEntry、CreateSettingsHeader、CreateDecorItemEntry）
-- 已迁移到 DockUI_EntryFactory.lua（单一权威）

-- 高亮容器逻辑已迁移到 DockUI_Highlight.lua（单一权威）




-- 子面板的实现已迁移至 src/dock/SubPanel.lua




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


-- 右侧预览区已完全移除（原 Right Section）


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
        if self.UpdateAutoWidth then self:UpdateAutoWidth() end
    end

    -- 仅显示一个“设置类”分类（不与其它分类混排）

    -- ============================================================================
    -- Show*Category 方法委托给独立页面模块渲染
    -- 优先使用分类键直接查找页面，回退到类型查找
    -- ============================================================================
    
    function MainFrame:ShowSettingsCategory(categoryKey)
        -- 优先用分类键查找独立页面模块
        local page = ADT.DockPages:Get(categoryKey) or ADT.DockPages:Get("settings")
        if page and page.Render then page:Render(self, categoryKey) end
    end
    
    function MainFrame:ShowDecorListCategory(categoryKey)
        local page = ADT.DockPages:Get(categoryKey) or ADT.DockPages:Get("decorList")
        if page and page.Render then page:Render(self, categoryKey) end
    end
    
    function MainFrame:ShowDyePresetsCategory(categoryKey)
        local page = ADT.DockPages:Get(categoryKey) or ADT.DockPages:Get("dyePresetList")
        if page and page.Render then page:Render(self, categoryKey) end
    end
    
    function MainFrame:ShowAboutCategory(categoryKey)
        local page = ADT.DockPages:Get(categoryKey) or ADT.DockPages:Get("about")
        if page and page.Render then page:Render(self, categoryKey) end
    end
    
    function MainFrame:ShowKeybindsCategory(categoryKey)
        local page = ADT.DockPages:Get(categoryKey) or ADT.DockPages:Get("keybinds")
        if page and page.Render then page:Render(self, categoryKey) end
    end
    
    function MainFrame:RefreshCategoryList()
        if not self.primaryCategoryPool then return end
        self.primaryCategoryPool:ReleaseAll()
        for index, categoryInfo in ipairs(CommandDock:GetSortedModules()) do
            local categoryButton = self.primaryCategoryPool:Acquire()
            categoryButton:SetCategory(categoryInfo.key, categoryInfo.categoryName, categoryInfo.anyNewFeature)
            categoryButton:SetPoint("TOPLEFT", self.LeftSlideContainer, self.primaryCategoryPool.offsetX, self.primaryCategoryPool.leftListFromY - (index - 1) * (Def.CategoryHeight or Def.ButtonSize))
        end
        self:UpdateLeftSectionHeight()
        if (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) and self.UpdateStaticLeftPlacement then self:UpdateStaticLeftPlacement() end
    end
    
    function MainFrame:UpdateSettingsEntries()
        self.ModuleTab.ScrollView:CallObjectMethod("Entry", "UpdateState")
    end
    
    function MainFrame:ShowSettingsView()
        self.currentDecorCategory = nil
        self.currentAboutCategory = nil
        self.currentDyePresetsCategory = nil
        self:RefreshFeatureList()
    end
end


local function CreateUI()
    local pageHeight = Def.PageHeight
    
    -- 紧凑布局：左侧宽度按“分类文本宽度”动态计算
    local sideSectionWidth = ComputeSideSectionWidth()
    MainFrame.sideSectionWidth = sideSectionWidth
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
        -- Header 仅覆盖右侧内容区：左缘始终贴 MainFrame 本身
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
    local Tab1 = MainFrame.ModuleTab

    -- 顶部标签布局：模板 LeftSection 仅用于提供锚点；
    -- 实际可见左窗由 LeftPanel.Build 创建的 LeftSlideContainer 实现。
    if LeftSection then
        LeftSection:SetWidth(sideSectionWidth)
        if LeftSection.EnableMouse then LeftSection:EnableMouse(false) end
        if LeftSection.EnableMouseMotion then LeftSection:EnableMouseMotion(false) end
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


        -- 初始中央区域可用宽度，随着窗口缩放动态更新
        local function ComputeCenterWidth()
            local w = tonumber(CentralSection:GetWidth()) or 0
            if w <= 0 then
                local total = tonumber(MainFrame:GetWidth()) or 0
                local leftw = tonumber(MainFrame.sideSectionWidth) or 0
                w = math.max(0, total - leftw)
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

        -- 染色预设条目模板和快捷键条目模板已迁移到 DockUI_Templates.lua（单一权威）
        -- 调用模板注册函数
        if ADT.DockUI.RegisterScrollViewTemplates then
            ADT.DockUI.RegisterScrollViewTemplates(ScrollView, MainFrame.centerButtonWidth)
        end
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

-- OnShow category restore logic moved to DockUI_Controller.lua

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

    -- AnchorWatcher/数据变化回调已迁移到 DockUI_Controller.lua
    -- 调用 Controller 的 PostCreate 初始化
    if ADT.DockUI.InitControllerPostCreate then
        ADT.DockUI.InitControllerPostCreate()
    end
end

-- View layer: UpdateLayout and ShowUI (Controller will call these)
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
    self:UpdateLayout()
    self:EnsureSubPanel()
    self:SetSubPanelShown(true)
    self:Show()
end

function MainFrame:HandleEscape()
    self:Hide()
    return false
end

-- Event listeners moved to DockUI_Controller.lua

