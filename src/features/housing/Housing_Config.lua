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
        -- SubPanel 最小高度：用于“只有一两行信息”时避免出现大面积空白。
        -- 160 对应旧版布局的保守值；当前 SubPanel 已支持自适应高度，因此下调为更贴合内容的像素值。
        subPanelMinHeight = 96,
        subPanelMaxHeight = 720,
        -- SubPanel 正文判空相关阈值（单一权威）
        contentAlphaThreshold = 0.01, -- alpha ≤ 阈值视为不可见（用于排除装饰/占位）
        leafMinAreaPx = 2,            -- 叶子节点最小边长（像素），过小视为无效区域
        -- ============ 右侧三层纵向布局（LayoutManager 单一权威） ============
        -- DockUI 最小高度（像素）：必须保证 Header + 基本交互可见
        dockMinHeightPx = 160,
        -- DockUI 最小临界高度（像素）：再小会破坏交互；溢出时 Dock 不得低于该值
        dockMinHeightCriticalPx = 160,
        -- DockUI 最大高度占屏幕比例（0~1）：仅作为 max-height 防爆，不做主分配
        dockMaxHeightViewportRatio = 0.32,
        -- SubPanel 最大高度占屏幕比例（0~1）
        subPanelMaxHeightViewportRatio = 0.40,
        -- 官方面板最小高度（像素）：默认允许为 0
        blizzardMinHeightPx = 0,
        -- 三层之间的统一垂直间距（像素，默认 0 表示相切）
        verticalGapPx = 0,
        -- 视口安全边距（像素）
        topSafeMarginPx = 0,
        bottomSafeMarginPx = 8,
        -- 说明：布局已改为“Dock 固定右上 + SubPanel 向下堆叠”，不再使用“SubPanel 居中偏置”。
        -- ============ 新增：宽度约束（Dock/子面板统一权威） ============
        -- 中央区域（不含左侧分类栏）的最小宽度，避免短文案把面板压窄导致换行/省略。
        -- 对应 DockUI.UpdateAutoWidth 中的 minCenter。
        dockMinCenterWidth = 300,
        -- Dock 主体“总宽度”相对当前视口宽度的最大占比（0~1）。
        -- 设为 0 或 nil 表示不以比例限制，仅受屏幕边距与内容驱动。
        dockMaxTotalWidthRatio = 0.5,
        -- 子面板在计算“所需中心宽度”时的硬上限占比（防极端超长 token 拉爆）。
        -- 仅用于 SubPanel 内部测量，不直接决定 Dock 总宽。
        subPanelMaxViewportRatio = 0.80,
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
    -- 颜色（单一权威）：用于 HoverHUD 信息行的语义配色
    -- 说明：统一提供 ARGB Hex（|cAARRGGBB）的 8 位十六进制，不带前缀 |c。
    -- 设计准则（2025 UI）：
    -- - Label 使用“柔和中性色”；
    -- - 数值使用语义色：好=绿、警告=琥珀、危险/不可用=红；
    -- - 次要分隔符使用更淡的中性灰以降低竞争；
    Colors = {
        labelMuted     = "FFCCCCCC", -- 次要标签/说明
        separatorMuted = "FFAAAAAA", -- 分隔符，如 “|”、“/”、“：”
        valueGood      = "FF2AD46F", -- 良好/可用（库存>0、染色已满）
        valueWarn      = "FFFFC233", -- 部分/进行中（染色部分已用）
        valueBad       = "FFFF6B6B", -- 不可用/告警（库存=0）
        valueNeutral   = "FFB8C0CC", -- 中性数值（如 0/0、未染色）
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
        -- 垂直间距由 Layout.verticalGapPx 统一裁决（单一权威）
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
    -- 染料弹窗（DyeSelectionPopout）锚点与边界（单一权威）
    DyePopout = {
        -- 与“自定义面板”左侧相切时的水平留白：0 表示严丝合缝；大于 0 则留出间距
        horizontalGap = 0,
        -- 顶部对齐的额外 Y 微调（正值向下，负值向上）
        verticalTopNudge = 0,
        -- 防止越出屏幕底部的安全边距
        safetyBottomPad = 8,
    },

    -- 住宅“库存/上限”计数（暴雪 DecorCount）在 Dock.Header 内的定位与尺寸（单一权威）
    DecorCount = {
        -- 锚点：将官方 DecorCount 贴到 Dock.Header 的哪个点位
        point    = "CENTER",
        relPoint = "CENTER",
        offsetX  = -10,
        offsetY  = -2,
        -- 缩放：整体缩放比（不改变父级/显隐）
        scale    = 0.65,
        -- 层级：为避免被木框/背景半透明影响，默认提升到最前层
        strata   = "TOOLTIP",      -- 可选：FULLSCREEN_DIALOG / DIALOG / TOOLTIP ...
        levelBias = 10,            -- 在 Header 基础上额外提升的 FrameLevel
        -- 是否忽略父级透明/缩放（避免被父级 alpha/scale 影响视觉）
        ignoreParentAlpha = true,
        ignoreParentScale = true,
    },

    -- 暴雪“放置的装饰清单”按钮（PlacedDecorListButton）在 Dock.Header 内的定位（单一权威）
    PlacedListButton = {
        point    = "RIGHT",
        relPoint = "RIGHT",
        offsetX  = -30,
        offsetY  = -3,
        scale    = 1.0,
        strata   = nil,      -- nil=跟随 Dock 主体；也可指定 "FULLSCREEN_DIALOG" 等
        levelBias = 0,       -- 基于 Header 的提升量
        levelBiasOverBorder = 1, -- 若存在 Dock.BorderFrame，则在其之上再提升的量
    },

    -- Header 齿轮按钮（折叠/展开 Dock 主体）的定位与尺寸（单一权威）
    GearButton = {
        -- 统一锚到 Dock.Header 的右上角附近，保持与关闭按钮、DecorCount 的相对关系稳定
        point    = "LEFT",
        relPoint = "LEFT",
        offsetX  = 30,
        offsetY  = -3,
        -- 尺寸（像素）：若未设置，则回落到 DockUI 的 Def.ButtonSize
        size     = 28,
        -- 层级（可选）：nil 表示跟随 Header；若需要可指定 "FULLSCREEN_DIALOG"/"TOOLTIP" 等
        strata   = nil,
        -- 基于 Header 的 FrameLevel 偏移（正数抬高）
        levelBias = 2,
    },
    -- Dock 列表（Clipboard/Recent）的库存数字与名称间距（配置驱动，分类可独立）
    DockDecorList = {
        -- 通用默认（各分类未覆写则继承本组）
        Common = {
            countRightInset = 20,   -- 库存数字距右边框的内缩像素
            nameToCountGap  = 8,   -- 名称与库存数字之间的间距
            countWidth      = 32,  -- 库存数字区域固定宽度（影响测宽与文本锚点）
        },
        -- 两个装饰列表型分类可分别调整
        Clipboard = {
            -- 不写表示继承 Common
            -- 示例：countRightInset = 8, nameToCountGap = 6, countWidth = 28
        },
        Recent = {
            -- 示例：countRightInset = 6, nameToCountGap = 10
        },
    },
    -- 轴悬停提示（AxisHoverHint）视觉与行为（配置驱动，单一权威）
    AxisHint = {
        -- 字体像素大小
        fontPx = 16,
        -- 光标相对偏移（屏幕空间，像素）
        cursorOffsetX = 12,
        cursorOffsetY = 16,
        -- 颜色（ARGB）
        colors = {
            X = "FFFF5A5A", -- 红
            Y = "FF2ECC71", -- 绿
            Z = "FF3498DB", -- 蓝
            Fallback = "FFFFFFFF",
        },
        -- 透明度（0~1）
        alpha = 1.0,
        -- 分层：在编辑器内置 UI 之上渲染
        strata = "TOOLTIP",
        -- 淡入/出节奏（继承通用 Fading，可单独覆盖）
        fadeInInstant = true,
        fadeInRate  = 10,
        fadeOutRate = 4,
        -- 哪些子模式显示提示：Rotate/Translate
        submodes = { Rotate = true, Translate = true },
    },
    -- Dock 选项条目/左侧分类 悬停高亮（三段贴片）参数：配置驱动，单一权威
    DockHighlight = {
        -- 三段贴片颜色（RGBA，0~1）
        color = { r = 0.96, g = 0.84, b = 0.32, a = 0.15 },
        -- 覆盖按钮的内收边距（像素；正数向内收）
        insetLeft   = 0,
        insetRight  = 0,
        insetTop    = -0,
        insetBottom = -0,
        -- 淡入控制：enabled=false 时立即显示
        fade = {
            enabled   = true,
            inDuration = 0.15,   -- 秒
        },
    },
    -- 快捷键设置 UI（KeybindUI）布局与样式参数（配置驱动，单一权威）
    KeybindUI = {
        -- 动作名称列宽度
        actionLabelWidth = 120,
        -- 按键框尺寸
        keyBoxWidth   = 100,
        keyBoxHeight  = 22,
        -- 按键框与动作名之间的间距
        actionToKeyGap = 8,
        -- 列表行内左右内边距（与行内视觉对称相关）
        rowLeftPad  = 8,
        rowRightPad = 8,
        -- Header 区域提示文本偏移（相对 Header 右侧）
        headerHintOffsetX = -50,   -- 负值向左
        headerHintOffsetY = 120,    -- 正值向上
        -- 边框颜色（RGBA 0~1）
        borderNormal    = { r = 0.3, g = 0.3, b = 0.3, a = 1 },
        borderHover     = { r = 0.8, g = 0.6, b = 0, a = 1 },
        borderRecording = { r = 1, g = 0.82, b = 0, a = 1 },
        -- 背景颜色
        bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 1 },
        -- 按键文本颜色（正常 / 未设置 / 录制中）
        keyTextNormal   = { r = 1, g = 0.82, b = 0 },      -- 金色
        keyTextEmpty    = { r = 0.5, g = 0.5, b = 0.5 },   -- 灰色
        keyTextRecording = { r = 1, g = 0.82, b = 0 },     -- 金色
        -- Header 提示文本颜色（悬停 / 录制中）
        hintHover     = { r = 0.6, g = 0.8, b = 1 },       -- 浅蓝色
        hintRecording = { r = 1, g = 0.82, b = 0 },        -- 金色
    },
    -- 快捷栏 QuickbarUI 的定位与间距（配置驱动，单一权威）
    QuickbarUI = {
        -- 说明：Quickbar 始终相对 UIParent 定位；不在配置中暴露“父级 Frame”。
        -- 锚点：通常贴底（BOTTOM/BOTTOM），如需靠上/居中可改为其他点位。
        anchor = {
            point    = "BOTTOM",  -- Quickbar 自身锚点
            relPoint = "BOTTOM",  -- 相对 UIParent 的锚点
            x        = 0,          -- 水平偏移（像素；正值→向右）
            bottomMargin = 5,      -- 底边距（像素；正值→向上）。当 point/relPoint 不是 BOTTOM 时同样作为 Y 偏移使用
        },
        -- 暴雪 ModesBar 与 Quickbar 之间的垂直间距（Quickbar 顶到 ModesBar 底）
        modeBarGap = 1,
        -- 动作栏整体缩放：与设置面板“动作栏大小”一致（配置驱动，单一权威）
        scaleBySize = {
            large  = 1.35,
            medium = 1.00,
            small  = 0.65,
        },
        -- 槽位内文本（右上角按键、右下角库存）内收像素：统一权威
        SlotTextInsets = {
            keyRight  = 6,  -- 按键文本距右侧内收
            keyTop    = 6,  -- 按键文本距顶部内收
            qtyRight  = 6,  -- 库存数字距右侧内收
            qtyBottom = 6,  -- 库存数字距底部内收
        },
    },

    -- “最近放置”快捷槽（RecentSlot）视觉参数（配置驱动，单一权威）
    RecentSlot = {
        -- 槽位尺寸与与 Quickbar 间距
        sizePx    = 80,
        spacingPx = 8,
        -- 顶部标签（“最近放置”）
        Label = {
            point    = "TOP",
            relPoint = "TOP",
            offsetX  = 0,
            offsetY  = -4,
            fontTemplate = "GameFontNormalSmall",
            fontPx       = 12,
            fontFlags    = nil,
            color = { r = 0.9, g = 0.75, b = 0.3, a = 1 }, -- 金色
        },
        -- 右下角库存数量
        Quantity = {
            point    = "BOTTOMRIGHT",
            relPoint = "BOTTOMRIGHT",
            offsetX  = -6,
            offsetY  = 6,
            fontTemplate = "GameFontNormalSmall",
            fontPx       = 12,
            fontFlags    = nil,
            colorNormal = { r = 1, g = 1, b = 1, a = 1 },
            colorZero   = { r = 1, g = 0.3, b = 0.3, a = 1 },
        },
    },
}

-- 导出为全局唯一权威
ADT.HousingInstrCFG = CFG

-- 便捷访问器（避免外部直接覆写表结构）
function ADT.GetHousingCFG()
    return ADT.HousingInstrCFG
end
