-- Housing_BlizzardGraft.lua
-- 目的：
-- 1) 把右上角“装饰计数  已用/上限（house-decor-budget-icon）”嵌入 DockUI 的 Header，替换原标题文字。
-- 2) 把右侧（或右下角）HouseEditor 的“操作说明/键位提示”面板（Instructions 容器）重挂到 DockUI 的下方面板中显示。
-- 约束：
-- - 严格依赖 Housing 事件与 API（单一权威）：
--     计数：C_HousingDecor.GetSpentPlacementBudget() / GetMaxPlacementBudget()
--     事件：HOUSING_NUM_DECOR_PLACED_CHANGED, HOUSE_LEVEL_CHANGED
--   （参见：Referrence/API/12.0.0.64774/Blizzard_HouseEditor/Blizzard_HouseEditorTemplates.lua）
-- - 不复制暴雪“说明列表”的业务逻辑，直接重挂其容器（DRY）。

local ADDON_NAME, ADT = ...
if not ADT or not ADT.CommandDock then return end

local CommandDock = ADT.CommandDock

local function Debug(msg)
    if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] " .. tostring(msg)) end
end

-- ===========================
-- 配置（单一权威，可按需调节）
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
        minHeight = 8,   -- 行最小高度（默认 45 过高）
        hSpacing  = 8,    -- 左右两列之间的间距（默认 10）
        vSpacing  = -10,    -- 不同行之间的垂直间距（容器级）
        vPadEach  = 1,    -- 每行上下额外内边距（topPadding/bottomPadding）
    },
    -- 右侧“按键气泡”
    Control = {
        height      = 24,  -- 整个 Control 容器高度（默认 45）
        bgHeight    = 22,  -- 背景九宫格的高度（默认 40）
        textPad     = 22,  -- 气泡左右总留白，原逻辑约 26
        minScale    = 0.70, -- 进一步收缩按钮文本的下限
    },
    -- 字体缩放
    Typography = {
        instructionScale = 0.78, -- 左列说明文字缩放
        controlScaleBase = 0.78, -- 右列按钮文字基础缩放（在 Fit 中可能继续变小）
        minFontSize      = 9,    -- 任何字体的最小像素
    },
}

-- 对外暴露：供 ADT 自建的 Instruction 行（HoverHUD）读取统一样式
ADT.HousingInstrCFG = CFG

-- 取到 Dock 主框体与 Header
local function GetDock()
    local dock = CommandDock and CommandDock.SettingsPanel
    if not dock or not dock.Header then return nil end
    return dock
end

--
-- 一、Dock Header 的装饰计数控件
--
local BudgetWidget
local HeaderTitleBackup
-- 前向声明：避免在闭包中捕获到全局未定义的 IsHouseEditorShown
--（Lua 的词法作用域要求在首次使用前声明局部变量，否则将解析为全局）
local IsHouseEditorShown

-- 让预算控件在自身容器内居中：计算“图标 + 间距 + 文本”的组合宽度，
-- 将图标的 LEFT 锚点向右偏移一半剩余空间。
local function LayoutBudgetWidget()
    if not BudgetWidget or not BudgetWidget.Icon or not BudgetWidget.Text then return end
    local gap = 6
    local iconW = BudgetWidget.Icon:GetWidth() or 0
    local textW = 0
    if BudgetWidget.Text.GetStringWidth then
        textW = math.ceil(BudgetWidget.Text:GetStringWidth() or 0)
    end
    local groupW = iconW + gap + textW
    local availW = BudgetWidget:GetWidth() or groupW
    local left = math.floor(math.max(0, (availW - groupW) * 0.5))

    BudgetWidget.Icon:ClearAllPoints()
    BudgetWidget.Icon:SetPoint("LEFT", BudgetWidget, "LEFT", left, 0)
    BudgetWidget.Text:ClearAllPoints()
    BudgetWidget.Text:SetPoint("LEFT", BudgetWidget.Icon, "RIGHT", gap, 0)
end

-- 计算并设置“从 Header 顶边”向下的像素，使 BudgetWidget 的垂直中心与 Header 垂直中心重合。
local function RepositionBudgetVertically()
    if not BudgetWidget then return end
    local header = BudgetWidget:GetParent()
    if not header or not header.GetHeight then return end
    local h = header:GetHeight() or 68
    local selfH = BudgetWidget:GetHeight() or 36
    local offset = math.floor((h - selfH) * 0.5 + 0.5)
    BudgetWidget:ClearAllPoints()
    BudgetWidget:SetPoint("TOP", header, "TOP", 0, -offset)
end

local function UpdateBudgetText()
    if not BudgetWidget or not BudgetWidget.Text then return end
    local used = C_HousingDecor and C_HousingDecor.GetSpentPlacementBudget and C_HousingDecor.GetSpentPlacementBudget() or 0
    local maxv = C_HousingDecor and C_HousingDecor.GetMaxPlacementBudget and C_HousingDecor.GetMaxPlacementBudget() or 0
    if used and maxv then
        if _G.HOUSING_DECOR_PLACED_COUNT_FMT then
            BudgetWidget.Text:SetText(string.format(_G.HOUSING_DECOR_PLACED_COUNT_FMT, used, maxv))
        else
            BudgetWidget.Text:SetText(used .. "/" .. maxv)
        end
    end
    -- 同步布局至居中
    LayoutBudgetWidget()
    RepositionBudgetVertically()
    -- Tooltip 文本与暴雪一致：室内/室外有不同描述
    if BudgetWidget then
        local base = _G.HOUSING_DECOR_BUDGET_TOOLTIP
        if _G.C_Housing and C_Housing.IsInsideHouse and _G.HOUSING_DECOR_BUDGET_TOOLTIP_INDOOR then
            base = (C_Housing.IsInsideHouse() and _G.HOUSING_DECOR_BUDGET_TOOLTIP_INDOOR) or _G.HOUSING_DECOR_BUDGET_TOOLTIP_OUTDOOR or base
        end
        if base then
            BudgetWidget.tooltipText = string.format(base, used or 0, maxv or 0)
        end
    end
end

local function EnsureBudgetWidget()
    local dock = GetDock()
    if not dock then return end

    -- 创建一次即可
    if BudgetWidget then return end

    local Header = dock.Header
    -- 备份标题，以便离开编辑器时恢复
    if dock.HeaderTitle and not HeaderTitleBackup then
        HeaderTitleBackup = dock.HeaderTitle:GetText()
    end

    BudgetWidget = CreateFrame("Frame", nil, Header)
    -- 初始化锚点，后续用 RepositionBudgetVertically() 精确垂直居中
    BudgetWidget:ClearAllPoints()
    BudgetWidget:SetPoint("CENTER", Header, "CENTER", 0, 0)
    BudgetWidget:SetHeight(36)
    BudgetWidget:SetWidth(240)
    BudgetWidget:SetScript("OnEnter", function(self)
        if not self.tooltipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip_AddHighlightLine(GameTooltip, self.tooltipText)
        GameTooltip:Show()
    end)
    BudgetWidget:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local icon = BudgetWidget:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", BudgetWidget, "LEFT", 0, 0)
    icon:SetAtlas("house-decor-budget-icon")
    icon:SetSize(34, 34) -- 放大 ~20%
    BudgetWidget.Icon = icon

    local text = BudgetWidget:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetText("0/0")
    BudgetWidget.Text = text
    -- 放大字体 ~20%
    pcall(function()
        local path, size, flags = text:GetFont()
        if path and size then text:SetFont(path, math.floor(size * 1.2 + 0.5), flags) end
    end)

    -- 初始布局：确保内容在容器内居中
    LayoutBudgetWidget(); RepositionBudgetVertically()

    -- 用 FrameUtil 注册事件，保持与暴雪模板一致
    BudgetWidget.updateEvents = {"HOUSING_NUM_DECOR_PLACED_CHANGED", "HOUSE_LEVEL_CHANGED"}
    BudgetWidget:SetScript("OnEvent", function() UpdateBudgetText() end)
    BudgetWidget:SetScript("OnShow", function(self)
        if FrameUtil and FrameUtil.RegisterFrameForEvents then
            FrameUtil.RegisterFrameForEvents(self, self.updateEvents)
        else
            for _, e in ipairs(self.updateEvents) do self:RegisterEvent(e) end
        end
        UpdateBudgetText()
        RepositionBudgetVertically()
        LayoutBudgetWidget()
    end)

    -- Header 尺寸变化时（如语言或 UI 缩放变动），保持垂直居中
    if Header and Header.HookScript then
        Header:HookScript("OnSizeChanged", function()
            if BudgetWidget and BudgetWidget:IsShown() then
                RepositionBudgetVertically(); LayoutBudgetWidget()
            end
        end)
    end
    BudgetWidget:SetScript("OnHide", function(self)
        if FrameUtil and FrameUtil.UnregisterFrameForEvents then
            FrameUtil.UnregisterFrameForEvents(self, self.updateEvents)
        else
            for _, e in ipairs(self.updateEvents) do self:UnregisterEvent(e) end
        end
    end)
end

local function ShowBudgetInHeader()
    local dock = GetDock()
    if not dock then return end
    EnsureBudgetWidget()
    if dock.HeaderTitle then
        dock.HeaderTitle:Hide()
    end
    if BudgetWidget then
        BudgetWidget:Show()
        UpdateBudgetText()
    end
    Debug("Header 计数已显示到 Dock")
    -- 维护计数刷新与可见性
    if not BudgetWidget._ticker then
        BudgetWidget._ticker = C_Timer.NewTicker(1.0, function(t)
            if not IsHouseEditorShown() then t:Cancel(); BudgetWidget._ticker=nil; return end
            UpdateBudgetText()
            if dock.HeaderTitle and dock.HeaderTitle:IsShown() then
                dock.HeaderTitle:Hide()
            end
            if BudgetWidget and not BudgetWidget:IsShown() then
                BudgetWidget:Show()
            end
        end)
    end
end

local function RestoreHeaderTitle()
    local dock = GetDock()
    if not dock then return end
    if BudgetWidget then
        BudgetWidget:Hide()
        if BudgetWidget._ticker then BudgetWidget._ticker:Cancel(); BudgetWidget._ticker=nil end
    end
    if dock.HeaderTitle and HeaderTitleBackup then
        dock.HeaderTitle:SetText(HeaderTitleBackup)
        dock.HeaderTitle:Show()
    end
end

--
-- 二、重挂 HouseEditor 的 Instructions 面板至 Dock 下方面板
--
local AdoptState = {
    originalParent = nil,
    restored = true,
    instr = nil,
    mirror = nil,
    selectRow = nil,
}

-- 统一：说明区自适应高度计算与重排队列（文件级本地函数，供各处调用）
local function _ADT_ComputeInstrNaturalHeight(instr)
    if not instr then return 0 end
    local h = (instr.GetHeight and instr:GetHeight()) or 0
    if not h or h <= 1 then
        local topMost, bottomMost
        for _, child in ipairs({instr:GetChildren()}) do
            if child and (not child.IsShown or child:IsShown()) then
                local ct = child.GetTop and child:GetTop()
                local cb = child.GetBottom and child:GetBottom()
                if ct and cb then
                    topMost = topMost and math.max(topMost, ct) or ct
                    bottomMost = bottomMost and math.min(bottomMost, cb) or cb
                end
            end
        end
        if topMost and bottomMost then
            h = math.max(0, topMost - bottomMost)
        end
    end
    return h or 0
end

local function _ADT_TargetSubHeight()
    local dock = GetDock()
    if not dock then return end
    local sub = dock.SubPanel or (dock.EnsureSubPanel and dock:EnsureSubPanel())
    if not sub then return end
    local headerH = (sub.Header and sub.Header.GetHeight and sub.Header:GetHeight()) or 0
    local paddingTop     = CFG.Layout.contentTopPadding
    local headerTopNudge = CFG.Layout.headerTopNudge
    local gapBelowHeader = CFG.Layout.headerToInstrGap
    local paddingBottom  = CFG.Layout.contentBottomPadding
    local instrH = _ADT_ComputeInstrNaturalHeight(AdoptState and AdoptState.instr)
    local target = math.floor(paddingTop + headerTopNudge + headerH + gapBelowHeader + instrH + paddingBottom + 0.5)
    target = math.max(CFG.Layout.subPanelMinHeight, math.min(CFG.Layout.subPanelMaxHeight, target))
    return target
end

local function _ADT_QueueResize()
    if not (AdoptState and AdoptState.instr) then return end
    if AdoptState._resizeTicker then return end
    AdoptState._resizeTicker = C_Timer.NewTicker(0.01, function(t)
        if not IsHouseEditorShown() then t:Cancel(); AdoptState._resizeTicker=nil; return end
        if AdoptState.instr and AdoptState.instr.UpdateLayout then AdoptState.instr:UpdateLayout() end
        local dock = GetDock(); if dock and _ADT_TargetSubHeight then
            local h = _ADT_TargetSubHeight()
            if h then dock:SetSubPanelHeight(h) end
        end
        AdoptState._resizeCount = (AdoptState._resizeCount or 0) + 1
        if AdoptState._resizeCount >= 2 then
            t:Cancel(); AdoptState._resizeTicker=nil; AdoptState._resizeCount=nil
        end
    end)
end

--
-- 说明面板排版：字体缩放（让暴雪信息文字更“秀气”，适配下方面板宽度）
--

local function _ADT_ScaleFont(fs, scale)
    if not (fs and fs.GetFont and fs.SetFont) then return end
    local path, size, flags = fs:GetFont()
    if not size or size <= 0 then return end
    if not fs._ADTOrigFont then
        fs._ADTOrigFont = {path=path, size=size, flags=flags}
    end
    local newSize = math.max(CFG.Typography.minFontSize, math.floor(size * scale + 0.5))
    if newSize ~= size then fs:SetFont(path, newSize, flags) end
end

-- 前置声明，避免调用顺序问题
local _ADT_AlignControl

local function _ADT_ApplyTypographyToRow(row)
    if not row then return end
    -- 行最小高度与左右列间距 + 行内上下内边距
    row.minimumHeight = CFG.Row.minHeight
    row.spacing = CFG.Row.hSpacing
    row.topPadding = CFG.Row.vPadEach
    row.bottomPadding = CFG.Row.vPadEach
    local fs = row.InstructionText
    if fs then
        _ADT_ScaleFont(fs, CFG.Typography.instructionScale)
        if fs.SetJustifyV then fs:SetJustifyV("MIDDLE") end
    end
    local ctext = row.Control and row.Control.Text
    if ctext then
        _ADT_ScaleFont(ctext, CFG.Typography.controlScaleBase)
        if ctext.SetJustifyV then ctext:SetJustifyV("MIDDLE") end
    end
    -- 控件高度与背景高度
    if row.Control then
        _ADT_AlignControl(row)
    end
end

-- 前置声明，避免在定义之前被调用
local _ADT_FitControlText

local function _ADT_ApplyTypography(instr)
    if not instr then return end
    -- 统一容器级“行间距”（不同行之间）
    instr.spacing = CFG.Row.vSpacing

    -- 递归应用到说明面板中的所有“行”样式。
    -- 原先只处理到第一层子节点，导致 ADT 自建的说明行（作为容器的子孙
    -- 节点，例如 HoverHUD 里的 SubFrame/附加行）未被缩放与对齐，从而与
    -- 暴雪说明的字号与按钮尺寸不一致。这里改为深度遍历，遇到具备
    -- InstructionText/Control 的帧即视作一行应用统一样式。
    local function applyDeep(frame)
        if not frame then return end
        _ADT_ApplyTypographyToRow(frame)
        _ADT_FitControlText(frame)
        for _, ch in ipairs({frame:GetChildren()}) do
            applyDeep(ch)
        end
    end
    for _, child in ipairs({instr:GetChildren()}) do
        applyDeep(child)
    end
end

-- 对外小型工具：允许其它模块显式请求对某一“行/容器”应用一次样式
-- 注意：仍以本文件的 CFG 为唯一权威，避免出现两套尺寸计算。
ADT.ApplyHousingInstructionStyle = function(target)
    if not target then return end
    -- 行：直接应用；容器：对其所有后代应用
    local function applyDeep(frame)
        if not frame then return end
        _ADT_ApplyTypographyToRow(frame)
        _ADT_FitControlText(frame)
        for _, ch in ipairs({frame:GetChildren()}) do
            applyDeep(ch)
        end
    end
    applyDeep(target)
end

-- 将右侧“按键文本气泡”根据实际可用宽度进一步收缩，避免超出子面板宽度
function _ADT_FitControlText(row)
    if not (row and row.Control and row.Control.Text and AdoptState and AdoptState.instr) then return end
    local instr = AdoptState.instr
    local sub = GetDock() and (GetDock().SubPanel or (GetDock().EnsureSubPanel and GetDock():EnsureSubPanel()))
    local content = sub and sub.Content
    local contentW = content and content:GetWidth()
    if not contentW then return end

    local spacing = row.spacing or CFG.Row.hSpacing or 10
    local leftW = row.InstructionText and row.InstructionText:GetWidth() or 0
    local maxRight = math.max(20, contentW - leftW - spacing - 12) -- 留一点右边距
    local text = row.Control.Text
    if not (text and text:IsShown()) then return end

    -- 计算当前文本宽度（按现字号）
    local strW = math.ceil(text:GetStringWidth() or 0)
    local pad = CFG.Control.textPad
    local need = strW + pad
    if need <= maxRight then
        -- 已经适配，无需再缩放
        row._ADT_lastScale = 1.0
        if row.Control.Background then row.Control.Background:SetWidth(need) end
        row.Control:SetWidth(need); row.Control:SetHeight(CFG.Control.height)
        return
    end

    -- 按可用宽度收缩字号（但不小于 CFG.Control.minScale）
    local path, size, flags = text:GetFont()
    if not size or size <= 0 then return end
    local curScale = row._ADT_lastScale or 1.0
    local targetScale = math.max(CFG.Control.minScale, (maxRight - pad) / math.max(1, strW))
    -- 仅在需要变更时才设置字体，避免无谓重排
    if targetScale < curScale - 0.01 then
        local newSize = math.max(CFG.Typography.minFontSize, math.floor(size * targetScale + 0.5))
        text:SetFont(path, newSize, flags)
        local newW = math.ceil(text:GetStringWidth() or 0) + pad
        if row.Control.Background then row.Control.Background:SetWidth(newW) end
        row.Control:SetWidth(newW); row.Control:SetHeight(CFG.Control.height)
        row._ADT_lastScale = targetScale
    else
        -- 仍需同步背景宽度，避免因先前缩放造成错位
        local w = math.ceil(text:GetStringWidth() or 0) + pad
        if row.Control.Background then row.Control.Background:SetWidth(w) end
        row.Control:SetWidth(w); row.Control:SetHeight(CFG.Control.height)
    end
end

-- 垂直对齐右侧按键气泡，使其与左侧文本行对齐（顶部对齐，避免显得下垂）
function _ADT_AlignControl(row)
    if not (row and row.Control) then return end
    local ctrl = row.Control
    -- 让 Control 容器高度与行最小高度一致，以获得稳定的纵向定位
    ctrl:SetHeight(CFG.Row.minHeight)
    ctrl.align = "center"
    if row.InstructionText then row.InstructionText.align = "center" end
    local bg = ctrl.Background
    if bg then
        bg:SetHeight(CFG.Control.bgHeight)
        bg:ClearAllPoints()
        -- 与 Control 垂直居中对齐，避免上下偏移
        bg:SetPoint("CENTER", ctrl, "CENTER", 0, 0)
    end
    -- 文本仍锚在背景中心，无需额外处理
end

local function _ADT_RestoreTypography(instr)
    if not instr then return end
    for _, child in ipairs({instr:GetChildren()}) do
        local fs = child.InstructionText
        if fs and fs._ADTOrigFont then
            fs:SetFont(fs._ADTOrigFont.path, fs._ADTOrigFont.size, fs._ADTOrigFont.flags)
            fs._ADTOrigFont = nil
        end
        local ctext = child.Control and child.Control.Text
        if ctext and ctext._ADTOrigFont then
            ctext:SetFont(ctext._ADTOrigFont.path, ctext._ADTOrigFont.size, ctext._ADTOrigFont.flags)
            ctext._ADTOrigFont = nil
        end
        if child.UpdateControl then pcall(child.UpdateControl, child) end
        if child.UpdateInstruction then pcall(child.UpdateInstruction, child) end
        if child.MarkDirty then child:MarkDirty() end
    end
    if instr.UpdateLayout then instr:UpdateLayout() end
end

local function GetActiveModeFrame()
    if _G.HouseEditorFrame_GetFrame then
        local f = _G.HouseEditorFrame_GetFrame()
        if f and f.GetActiveModeFrame then
            return f:GetActiveModeFrame()
        end
    end
    return nil
end

-- 绑定到前向声明的同名局部变量，而不是重新声明新的 local
function IsHouseEditorShown()
    if _G.HouseEditorFrame_IsShown then
        return _G.HouseEditorFrame_IsShown()
    end
    local f = _G.HouseEditorFrame
    return f and f:IsShown()
end

local function AdoptInstructionsIntoDock()
    local dock = GetDock()
    if not dock or not dock.EnsureSubPanel then return end

    local active = GetActiveModeFrame()
    local instr = active and active.Instructions
    if not instr then
        -- 兜底：尝试从所有可能的模式容器里找一个正在显示的 Instructions
        local hf = _G.HouseEditorFrame
        if hf then
            for _, key in ipairs({"ExpertDecorModeFrame","BasicDecorModeFrame","LayoutModeFrame","CustomizeModeFrame","CleanupModeFrame","ExteriorCustomizationModeFrame"}) do
                local frm = hf[key]
                if frm and frm:IsShown() and frm.Instructions then
                    active = frm
                    instr = frm.Instructions
                    break
                end
            end
        end
    end
    if not instr then
        Debug("未发现 Instructions 容器，跳过重挂(Active=" .. tostring(active) .. ")")
        dock:SetSubPanelShown(false)
        return
    end

    -- 保存原始父级，便于恢复
    if AdoptState.restored then
        AdoptState.originalParent = instr:GetParent()
        AdoptState.restored = false
    end

    local sub = dock:EnsureSubPanel()
    dock:SetSubPanelShown(true)
    -- 需求变更：右侧 Header 不再显示固定“操作说明”，改由 HoverHUD 动态写入“悬停装饰名称”。
    -- 这里初始化为空字符串，交由 HoverHUD 在悬停时更新。
    if sub and sub.Header then sub.Header:SetText("") end

    -- 优先方案：直接重挂，但不再把容器“贴到底”。
    -- 改动说明：
    -- - 让暴雪的说明面板从 Header 之下开始，避免遮挡“操作说明”标题；
    -- - 只限定宽度与顶部锚点，让 VerticalLayoutFrame 自行计算“自然高度”，供后续自适应使用。
    instr:ClearAllPoints()
    instr:SetParent(sub.Content)
    instr:SetPoint("TOPLEFT",  sub.Header,  "BOTTOMLEFT",  0, -CFG.Layout.headerToInstrGap)
    instr:SetPoint("TOPRIGHT", sub.Header,  "BOTTOMRIGHT", 0, -CFG.Layout.headerToInstrGap)
    if instr.UpdateAllVisuals then instr:UpdateAllVisuals() end
    if instr.UpdateLayout then instr:UpdateLayout() end

    -- 定制化：隐藏“选择装饰/放置装饰”整行 + 去掉所有鼠标图标（保留键位按钮）
    local function _ADT_ShouldHideRowByText(text)
        if not text then return false end
        if _G.HOUSING_DECOR_SELECT_INSTRUCTION and (text == _G.HOUSING_DECOR_SELECT_INSTRUCTION or string.find(text, _G.HOUSING_DECOR_SELECT_INSTRUCTION, 1, true)) then
            return true
        end
        if _G.HOUSING_BASIC_DECOR_PLACE_INSTRUCTION and (text == _G.HOUSING_BASIC_DECOR_PLACE_INSTRUCTION or string.find(text, _G.HOUSING_BASIC_DECOR_PLACE_INSTRUCTION, 1, true)) then
            return true
        end
        return false
    end
    local function stripLine(line)
        if not line or not line.InstructionText or not line.Control then return end
        local text = line.InstructionText:GetText()
        if _ADT_ShouldHideRowByText(text) then
            line._ADTForceHideRow = true
            if text == _G.HOUSING_DECOR_SELECT_INSTRUCTION then AdoptState.selectRow = line end
            if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] Hide row by text: " .. tostring(text)) end
            line:Hide()
            return
        end
        -- 仅隐藏“鼠标图标”本体，不影响左侧文字（如装饰名等）
        local atlas = line.Control.Icon and line.Control.Icon.GetAtlas and line.Control.Icon:GetAtlas()
        if atlas and atlas:find("housing%-hotkey%-icon%-") then
            line._ADTForceHideControl = true
            if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] Hide mouse icon control, atlas=" .. tostring(atlas) .. ", text=" .. tostring(text)) end
            if line.Control.Icon then line.Control.Icon:Hide() end
            if line.Control.Background then line.Control.Background:Hide() end
            line.Control:Hide()
        end
    end

    local children = {instr:GetChildren()}
    for _, ch in ipairs(children) do stripLine(ch) end
    if instr.UpdateLayout then instr:UpdateLayout() end

    -- 如果官方暴露了直接 key，进一步保险
    if instr.SelectInstruction then
        instr.SelectInstruction._ADTForceHideRow = true
        AdoptState.selectRow = instr.SelectInstruction
        if instr.SelectInstruction.HookScript then
            instr.SelectInstruction:HookScript("OnShow", function(self) self:Hide() end)
        end
        instr.SelectInstruction:Hide()
    end
    if instr.PlaceInstruction then
        instr.PlaceInstruction._ADTForceHideRow = true
        if instr.PlaceInstruction.HookScript then
            instr.PlaceInstruction:HookScript("OnShow", function(self) self:Hide() end)
        end
        instr.PlaceInstruction:Hide()
    end
    AdoptState.instr = instr

    -- 保持与 HouseEditor 同样的像素感：忽略父缩放并以 1.0 绘制
    if instr.SetIgnoreParentScale then instr:SetIgnoreParentScale(true) end
    if instr.SetScale then instr:SetScale(1.0) end
    instr:Show()
    -- 尺寸变化：仅排队重新计算高度，避免递归
    if instr.HookScript then
        instr:HookScript("OnSizeChanged", function()
            if AdoptState and AdoptState.instr then _ADT_QueueResize() end
        end)
        instr:HookScript("OnShow", function()
            if AdoptState and AdoptState.instr then _ADT_ApplyTypography(AdoptState.instr); _ADT_QueueResize() end
        end)
    end

    -- 初次排队计算；说明内容在不同模式会异步刷新，多给一帧稳定时间
    _ADT_ApplyTypography(instr)
    _ADT_QueueResize()
    -- 针对登录后立刻切到“专家模式”时偶发未缩放：
    -- 某些行会在后续一两帧由暴雪代码异步刷新（UpdateAllVisuals/UpdateLayout），
    -- 我们这里做一次短暂的“后抖动重应用”，确保样式最终一致。
    if not AdoptState._styleTicker then
        local count = 0
        AdoptState._styleTicker = C_Timer.NewTicker(0.05, function(t)
            if not IsHouseEditorShown() then t:Cancel(); AdoptState._styleTicker=nil; return end
            if AdoptState and AdoptState.instr then _ADT_ApplyTypography(AdoptState.instr); _ADT_QueueResize() end
            count = count + 1
            if count >= 6 then t:Cancel(); AdoptState._styleTicker=nil end
        end)
    end

    -- 同时隐藏右上角官方 DecorCount（我们已在 Header 重绘计数）
    if active and active.DecorCount and active.DecorCount:IsShown() then
        active.DecorCount:Hide()
    end
    -- 确保头部计数常驻
    ShowBudgetInHeader()
    Debug("已重挂 Instructions 到 Dock 下方面板（不再镜像/不再隐藏官方容器）")
end

local function RestoreInstructions()
    if not AdoptState.instr or not AdoptState.originalParent then return end
    local instr = AdoptState.instr
    instr:ClearAllPoints()
    instr:SetParent(AdoptState.originalParent)
    -- 恢复字体尺寸，避免影响官方原位显示
    _ADT_RestoreTypography(instr)
    instr:Show()
    -- 使用其模板默认锚点，不强行恢复具体点位
    AdoptState.instr = nil
    AdoptState.originalParent = nil
    AdoptState.restored = true

    local dock = GetDock()
    if dock and dock.SetSubPanelShown then
        dock:SetSubPanelShown(false)
    end
    -- 不再使用镜像
    if AdoptState.mirror then AdoptState.mirror:Hide() end
    -- 恢复右上角官方 DecorCount
    local active = GetActiveModeFrame()
    if active and active.DecorCount then
        active.DecorCount:Show()
    end
    Debug("已恢复官方 Instructions/计数到原位置")
end

--
-- 三、统一入口：HouseEditor 打开/关闭与模式变化时同步
--
local EL = CreateFrame("Frame")

local function TrySetupHooks()
    if not _G.HouseEditorFrameMixin or EL._hooksInstalled then return end
    -- 钩住显示/隐藏与模式切换
    pcall(function()
        hooksecurefunc(HouseEditorFrameMixin, "OnShow", function()
            ShowBudgetInHeader();
            C_Timer.After(0, AdoptInstructionsIntoDock)
            C_Timer.After(0.1, AdoptInstructionsIntoDock)
        end)
        hooksecurefunc(HouseEditorFrameMixin, "OnHide", function()
            RestoreHeaderTitle(); RestoreInstructions()
        end)
        hooksecurefunc(HouseEditorFrameMixin, "OnActiveModeChanged", function()
            C_Timer.After(0, AdoptInstructionsIntoDock)
        end)
        -- 对行控件进行二次清理：若设置了 _ADTForceHideControl 或检测到“选择装饰”文本，则强制隐藏
        if _G.HouseEditorInstructionMixin then
            hooksecurefunc(HouseEditorInstructionMixin, "UpdateControl", function(self)
                -- 1) 彻底隐藏“选择装饰”行
                local t = self.InstructionText and self.InstructionText.GetText and self.InstructionText:GetText()
                if (self == AdoptState.selectRow) or _ADT_ShouldHideRowByText(t) or self._ADTForceHideRow then
                    if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] UpdateControl hide row: " .. tostring(t)) end
                    self:Hide(); return
                end

                -- 2) 去掉所有“鼠标图标”（例如左键/滚轮等）：
                --    - 保留左侧文字（可能是说明或装饰名）
                --    - 隐藏右侧图标，不展示空白背景气泡
                local icon = self.Control and self.Control.Icon
                local atlas = icon and icon.GetAtlas and icon:GetAtlas()
                if type(atlas) == "string" and atlas:find("housing%-hotkey%-icon%-") then
                    -- 保险：移除配置以免后续刷新又把图标带回来
                    if self.iconAtlas ~= nil then self.iconAtlas = nil end
                    if self.keybindName ~= nil then self.keybindName = nil end
                    if self.controlText ~= nil then self.controlText = nil end
                    if self.Control.Background then self.Control.Background:Hide() end
                    if icon then icon:Hide() end
                    if self.Control then self.Control:Hide() end
                    if self.SetControlWidth then pcall(self.SetControlWidth, self, 0) end
                    if self.MarkDirty then self:MarkDirty() end
                    _ADT_QueueResize();
                    if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] UpdateControl hide mouse icon: atlas=" .. tostring(atlas) .. ", text=" .. tostring(t)) end
                    return
                end

                if self._ADTForceHideControl and self.Control then
                    if self.Control.Background then self.Control.Background:Hide() end
                    if self.Control.Icon then self.Control.Icon:Hide() end
                    self.Control:Hide()
                end
                _ADT_ApplyTypographyToRow(self); _ADT_AlignControl(self); _ADT_FitControlText(self); _ADT_QueueResize()
            end)
            -- 同步在 UpdateInstruction 阶段也做一次兜底（某些路径只更新文本，会绕过 UpdateControl）
            hooksecurefunc(HouseEditorInstructionMixin, "UpdateInstruction", function(self)
                local t = self.InstructionText and self.InstructionText.GetText and self.InstructionText:GetText()
                if _ADT_ShouldHideRowByText(t) or self._ADTForceHideRow then
                    if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] UpdateInstruction hide row: " .. tostring(t)) end
                    self:Hide(); _ADT_QueueResize(); return
                end
                _ADT_ApplyTypographyToRow(self); _ADT_AlignControl(self); _ADT_FitControlText(self); _ADT_QueueResize()
            end)
        end
        -- 同步钩住“容器级”的刷新：任何官方对 Instructions 的 UpdateAllVisuals/UpdateLayout
        -- 结束后再次套用我们的样式，避免时序竞态导致的漏网。
        if _G.HouseEditorInstructionsContainerMixin then
            hooksecurefunc(HouseEditorInstructionsContainerMixin, "UpdateAllVisuals", function(self)
                _ADT_ApplyTypography(self); _ADT_QueueResize()
            end)
            hooksecurefunc(HouseEditorInstructionsContainerMixin, "UpdateLayout", function(self)
                -- UpdateLayout 完成后，右侧键帽宽度可能变化，再走一次贴合
                if self then
                    for _, ch in ipairs({self:GetChildren()}) do _ADT_FitControlText(ch) end
                end
                _ADT_QueueResize()
            end)
        end
        EL._hooksInstalled = true
        Debug("已安装 HouseEditorFrameMixin 钩子")
    end)
end

-- 注册 EventRegistry 回调（额外冗余，优先触发）
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("HouseEditor.StateUpdated", function(_, isActive)
        TrySetupHooks()
        if isActive then
            ShowBudgetInHeader()
            C_Timer.After(0, AdoptInstructionsIntoDock)
            C_Timer.After(0.1, AdoptInstructionsIntoDock)
            -- 启动轮询直到成功采用
            if not EL._adoptTicker then
                local attempts = 0
                EL._adoptTicker = C_Timer.NewTicker(0.25, function(t)
                    attempts = attempts + 1
                    if not IsHouseEditorShown() then t:Cancel(); EL._adoptTicker=nil; return end
                    AdoptInstructionsIntoDock()
                    if AdoptState.instr then t:Cancel(); EL._adoptTicker=nil; Debug("轮询采纳成功") return end
                    if attempts >= 20 then t:Cancel(); EL._adoptTicker=nil; Debug("轮询超时，未能采纳 Instructions") end
                end)
            end
        else
            RestoreHeaderTitle()
            RestoreInstructions()
        end
    end, EL)
end

-- 事件：模式变化/加载/登录
EL:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
EL:RegisterEvent("ADDON_LOADED")
EL:RegisterEvent("PLAYER_LOGIN")
EL:SetScript("OnEvent", function(_, event, arg1)
    if event == "HOUSE_EDITOR_MODE_CHANGED" then
        C_Timer.After(0, AdoptInstructionsIntoDock)
    elseif event == "ADDON_LOADED" and (arg1 == "Blizzard_HouseEditor" or arg1 == ADDON_NAME) then
        TrySetupHooks()
        if IsHouseEditorShown() then
            ShowBudgetInHeader(); C_Timer.After(0, AdoptInstructionsIntoDock)
        end
    elseif event == "PLAYER_LOGIN" then
        TrySetupHooks()
        C_Timer.After(0.5, function()
            if IsHouseEditorShown() then
                ShowBudgetInHeader(); C_Timer.After(0, AdoptInstructionsIntoDock)
            end
        end)
    end
end)

-- 容错：如果当前就处于家宅编辑器，延迟一次尝试
C_Timer.After(1.0, function()
    TrySetupHooks()
    if IsHouseEditorShown() then
        ShowBudgetInHeader(); C_Timer.After(0, AdoptInstructionsIntoDock)
    end
end)
