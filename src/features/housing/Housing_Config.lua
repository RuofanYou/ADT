-- Housing_Config.lua
-- 目的：为“说明文本 + 按键气泡”的样式提供单一权威配置来源。
-- 规范：
-- - 使用 AddOn 命名空间在同一插件内共享（参见 Warcraft Wiki: Using the AddOn namespace）。
-- - 不做 JSON/外部文件读取（WoW 插件运行时无文件 I/O；配置须以内嵌 Lua 形式提供）。

local ADDON_NAME, ADT = ...
if not ADT then return end

-- ===========================
-- 样式配置（单一权威）
-- ===========================
local CFG = {
    -- Dock 子面板与 Header 的间距、边距以及高度限制
    Layout = {
        headerToInstrGap = 8,  -- Header 与说明列表之间的垂直间距
        contentTopPadding = 14,
        headerTopNudge   = 10, -- Header 相对 Content 的下移偏移
        contentBottomPadding = 10,
        subPanelMinHeight = 160,
        subPanelMaxHeight = 720,
    },
    -- 每一“行”说明（HouseEditorInstructionTemplate）的视觉参数
    Row = {
        -- 行高与间距需要兼顾多语言与字号缩放，否则会造成键帽文本挤压/堆叠。
        minHeight = 22,   -- 行最小高度：与 24px 键帽高度协调
        hSpacing  = 8,    -- 左右两列之间的间距（默认 10）
        vSpacing  = 2,    -- 不同行之间的垂直间距（容器级）
        vPadEach  = 1,    -- 每行上下额外内边距（topPadding/bottomPadding）
        -- 左侧与 SubPanel.Content 对齐：默认采用 DockUI 的统一左右留白（GetRightPadding），
        -- 以便与 Header.Divider 左/右缩进保持一致；若需更贴边，可改为 0。
        leftPad   = nil,       -- nil 表示使用 DockUI 统一留白；设为数字则显式覆盖
        textLeftNudge = 0,     -- 仅信息文字的额外 X 偏移（单位像素，正值→向右，负值→向左）
        textYOffset   = 0,     -- 仅信息文字的额外 Y 偏移（单位像素，正值→向上，负值→向下）
        -- 右侧仍与 DockUI 的统一右内边距一致
        rightPad  = 6,
    },
    -- 右侧“按键气泡”
    Control = {
        height      = 24,  -- 整个 Control 容器高度（默认 45）
        bgHeight    = 22,  -- 背景九宫格的高度（默认 40）
        textPad     = 22,  -- 气泡左右总留白，原逻辑约 26
        minScale    = 0.70, -- 进一步收缩按钮文本的下限
        -- 视觉右侧微调：按键气泡的九宫格右端存在外延/光晕，看起来会更靠边；
        -- 为了让“视觉上的右侧留白”与左侧文本留白一致，这里额外收回 4px。
        rightEdgeBias = 12,
    },
    -- 字体（像素级，单一权威）
    -- 说明：弃用“缩放系数”写法，改为显式像素值，便于美术/策划直接按像素调整。
    Typography = {
        instructionFontPx = 16, -- 左列信息文字字号（像素）
        controlFontPx     = 13, -- 右列键帽文字字号（像素）
        minFontSize       = 9,  -- 任意字体允许的最小像素（用于自动收缩下限）
    },
    -- 子面板展开/收起动画（配置驱动，单一权威）
    SubPanelAnim = {
        -- 展开/收起的总时长（秒）
        inDuration  = 0.18,
        outDuration = 0.18,
        -- 缩放最小值（避免 0 造成某些版本下的数值异常）
        minScale    = 0.001,
        -- 平滑曲线（Animation:SetSmoothing 的参数）：可选 IN/OUT/IN_OUT
        smoothing   = "OUT",
        -- 是否同时做 Alpha 的淡入/淡出
        withAlpha   = true,
    },
    -- 暴雪“放置的装饰清单”对齐 DockUI 的配置（单一权威）
    PlacedList = {
        -- 说明：官方清单木质边框相对 Frame 有约 ±4px 的外扩；
        -- 为与 DockUI 右侧面板/子面板的“0 外扩”对齐，这里仅在锚点上做等量补偿。
        anchorLeftCompensation  = 6,   -- 清单锚到 SubPanel 时，LEFT 方向的 +像素偏移
        anchorRightCompensation = -6,  -- 清单锚到 SubPanel 时，RIGHT 方向的 -像素偏移
        -- 清单顶部与 SubPanel 底部之间的垂直间距（像素，正值=向下留白）
        verticalGap = 6,
    },
    -- 悬停提示淡入/淡出节奏（配置驱动，单一权威）
    Fading = {
        -- 悬停开始：立即满不透明，避免“刚出现半透明”的错觉
        fadeInInstant = true,
        -- 如需动画淡入，将 fadeInInstant 设为 false，并用下列速率（每秒增量）
        fadeInRate  = 10,
        -- 淡出速度（每秒衰减量），与上面独立可配
        fadeOutRate = 3,
        -- 注意：淡出延时由调用方传入，不在此固化固定秒数
    },
}

-- 导出为全局唯一权威
ADT.HousingInstrCFG = CFG

-- 便捷访问器（避免外部直接覆写表结构）
function ADT.GetHousingCFG()
    return ADT.HousingInstrCFG
end
