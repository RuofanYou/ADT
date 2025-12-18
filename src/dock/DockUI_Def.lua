-- DockUI_Def.lua
-- DockUI 配置常量与共享定义（单一权威）

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

-- 初始化 DockUI 命名空间
ADT.DockUI = ADT.DockUI or {}

-- ============================================================================
-- 核心配置常量
-- ============================================================================
local Def = {
    BackgroundFile = "Interface/AddOns/AdvancedDecorationTools/Art/CommandDock/CommonFrameWithHeader.tga",
    ButtonSize = 28,
    CategoryHeight = 22,
    WidgetGap = 14,
    PageHeight = 380,
    CategoryGap = 10,
    TabButtonHeight = 40,

    -- 颜色定义
    TextColorNormal = {215/255, 192/255, 163/255},
    TitleColorPaleGold = {0.95, 0.86, 0.55},
    TextColorHighlight = {1, 1, 1},
    TextColorNonInteractable = {148/255, 124/255, 102/255},
    TextColorDisabled = {0.5, 0.5, 0.5},
    TextColorReadable = {163/255, 157/255, 147/255},

    -- 右侧内容区域布局
    RightContentPaddingLeft = 14,
    CategoryLabelToCountGap = 8,
    CountTextWidthReserve = 22,
    EntryLabelLeftInset = 28,
    HeaderLeftNudge = 8,
    AboutTextExtraLeft = 0,

    -- 高亮条配置
    HighlightTextPaddingLeft = 10,
    HighlightRightInset = 2,
    HighlightMinHeight = 18,
    HighlightTextPadX = 6,
    HighlightRightBias = -2,

    -- 右侧停靠配置
    ScreenRightMargin = 0,
    StaticRightAttachOffset = 0,
    LeftPanelPadTop = 14,
    LeftPanelPadBottom = 14,

    -- Header/顶部区域配置
    HeaderHeight = 68,
    ShowHeaderTitle = false,
    HeaderTitleOffsetX = 22,
    HeaderTitleOffsetY = -10,
    CloseBtnOffsetX = -1,
    CloseBtnOffsetY = -1,

    -- PlacedListButton 配置
    PlacedListBtnPoint = "LEFT",
    PlacedListBtnRelPoint = "LEFT",
    PlacedListBtnOffsetX = 40,
    PlacedListBtnOffsetY = -1,
    PlacedListBtnRaiseAboveBorder = 1,

    -- 滚动区域边距
    ScrollViewInsetTop = 2,
    ScrollViewInsetBottom = 18,
    RightBGInsetRight = 0,
    RightBGInsetBottom = 0,
    CenterBGInsetBottom = 0,

    -- 空状态配置
    EmptyStateTopGap = 6,

    -- 左侧分类按钮配置
    CategoryButtonLabelOffset = 9,
    CategoryCountRightInset = 2,

    -- 子面板动效配置
    SubPanelFX = {
        enabled = true,
        originPoint = "TOP",
        showDuration = 0.18,
        hideDuration = 0.16,
        smoothingIn = "OUT",
        smoothingOut = "IN",
        scaleMin = 0.001,
        scaleMax = 1.0,
        fade = true,
        fadeFrom = 0.0,
        fadeTo = 1.0,
        emptyQuietSec = 0.12,
    },
}

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 单一权威：右侧内容起始的左内边距
local function GetRightPadding()
    return Def.WidgetGap
end

-- ============================================================================
-- 导出
-- ============================================================================
ADT.DockUI.Def = Def
ADT.DockUI.GetRightPadding = GetRightPadding

-- 全局访问器：解决子模块无法访问 DockUI.lua 中局部变量 MainFrame 的问题
-- 所有子模块通过此函数获取 MainFrame 引用
function ADT.DockUI.GetMainFrame()
    return ADT.CommandDock and ADT.CommandDock.SettingsPanel
end

-- 快捷别名
function ADT.DockUI.GetCommandDock()
    return ADT.CommandDock
end
