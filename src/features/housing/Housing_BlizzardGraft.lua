-- Housing_BlizzardGraft.lua
-- 目的：
-- 1) 把右上角“装饰计数  已用/上限（house-decor-budget-icon）”嵌入 DockUI 的 Header，替换原标题文字。
-- 2) 把右侧（或右下角）HouseEditor 的“操作说明/键位提示”面板（Instructions 容器）重挂到 DockUI 的下方面板中显示。
-- 3) 在进入家宅编辑器时，常驻显示“放置的装饰”列表（使用暴雪官方模板）。
-- 约束：
-- - 严格依赖 Housing 事件与 API（单一权威）：
--     计数：C_HousingDecor.GetSpentPlacementBudget() / GetMaxPlacementBudget()
--     事件：HOUSING_NUM_DECOR_PLACED_CHANGED, HOUSE_LEVEL_CHANGED
--   （参见：Referrence/API/12.0.0.64774/Blizzard_HouseEditor/Blizzard_HouseEditorTemplates.lua）
-- - 不复制暴雪“说明列表”的业务逻辑，直接重挂其容器（DRY）。

local ADDON_NAME, ADT = ...
if not ADT or not ADT.CommandDock then return end

local CommandDock = ADT.CommandDock
-- 前置声明：供早期函数安全引用（避免隐式全局）
local EL -- 事件承载帧将在文末初始化

local function Debug(msg)
    if ADT and ADT.DebugPrint then ADT.DebugPrint("[Graft] " .. tostring(msg)) end
end

-- 统一从配置脚本读取（唯一权威）
local CFG = assert(ADT and ADT.HousingInstrCFG, "ADT.HousingInstrCFG 缺失：请确认 Housing_Config.lua 先于本文件加载")

-- 统一请求三层重排（LayoutManager 单一权威）
local function RequestLayout(reason)
    local LM = ADT and ADT.HousingLayoutManager
    if LM and LM.RequestLayout then
        LM:RequestLayout(reason or "Graft")
    end
end

-- 取到 Dock 主框体与 Header
local function GetDock()
    local dock = CommandDock and CommandDock.SettingsPanel
    if not dock or not dock.Header then return nil end
    return dock
end

-- 统一右侧内边距：优先读取 DockUI 的单一权威；无则回退到 CFG 的默认
local function GetUnifiedRightPad()
    local pad
    if ADT and ADT.DockUI and ADT.DockUI.GetRightPadding then
        local ok, v = pcall(ADT.DockUI.GetRightPadding)
        if ok and type(v) == 'number' then pad = v end
    end
    return tonumber(pad) or (CFG.Row.rightPad or 6)
end

--
-- 一、Dock Header 的装饰计数控件
--
local BudgetWidget
local BudgetAnchorHeader -- 仅用于定位的锚点（不作为父级）
local HeaderTitleBackup
-- 前向声明：避免在闭包中捕获到全局未定义的 IsHouseEditorShown
--（Lua 的词法作用域要求在首次使用前声明局部变量，否则将解析为全局）
local IsHouseEditorShown
local GetActiveModeFrame -- 前向声明，供早期函数引用
local GetCustomizePanes   -- 前向声明：供 AnchorDyePopout 提前调用

-- 更新：按需微调“放置的装饰”官方面板（仅布局/交互禁用），不改其数据与刷新逻辑。

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
    local header = BudgetAnchorHeader or (GetDock() and GetDock().Header)
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
    BudgetAnchorHeader = Header
    -- 备份标题，以便离开编辑器时恢复
    if dock.HeaderTitle and not HeaderTitleBackup then
        HeaderTitleBackup = dock.HeaderTitle:GetText()
    end

    -- 重要：不把预算控件设为 Header 的子级，避免 Dock 隐藏时一同隐藏。
    -- 仅以 Header 作为锚点进行定位；父级改为 UIParent。
    BudgetWidget = CreateFrame("Frame", nil, UIParent)
    -- 初始化锚点，后续用 RepositionBudgetVertically() 精确垂直居中
    BudgetWidget:ClearAllPoints()
    BudgetWidget:SetPoint("CENTER", Header, "CENTER", 0, 0)
    BudgetWidget:SetHeight(36)
    BudgetWidget:SetWidth(240)
    -- 初次创建时保持透明，等锚点与文本准备好后再显现（防止视觉“飞入”）
    if BudgetWidget.SetAlpha then BudgetWidget:SetAlpha(0) end
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

-- KISS：不再自绘 BudgetWidget，直接使用暴雪官方 DecorCount，
-- 仅做“位置 + 缩放 + 层级”处理，且不改变其 parent 与显隐逻辑。
local function _GetAnyDecorCount()
    local active = GetActiveModeFrame()
    if active and active.DecorCount then return active.DecorCount end
    local hf = _G.HouseEditorFrame
    if not hf then return nil end
    for _, key in ipairs({"ExpertDecorModeFrame","BasicDecorModeFrame","CustomizeModeFrame","CleanupModeFrame","LayoutModeFrame"}) do
        local frm = hf[key]
        if frm and frm.DecorCount then return frm.DecorCount end
    end
    return nil
end

-- 对外导出：供 DockUI 在 Header 内锚定齿轮按钮时查询 DecorCount 位置
ADT.HousingGraft = ADT.HousingGraft or {}
function ADT.HousingGraft.GetAnyDecorCount()
    return _GetAnyDecorCount()
end

-- 对齐函数：必须位于任何使用它的钩子之前（避免前向引用为 nil）
local function _AnchorDecorCount(dc, header)
    if not (dc and header) then return end
    local cfg = (ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.DecorCount) or {}
    local p  = cfg.point or "RIGHT"
    local rp = cfg.relPoint or p
    local x  = tonumber(cfg.offsetX) or -12
    local y  = tonumber(cfg.offsetY) or 0
    dc:ClearAllPoints()
    dc:SetPoint(p, header, rp, x, y)
    pcall(function()
        if dc.SetScale then dc:SetScale(tonumber(cfg.scale) or 1.0) end
        if dc.SetIgnoreParentAlpha then dc:SetIgnoreParentAlpha(cfg.ignoreParentAlpha ~= false) end
        if dc.SetIgnoreParentScale then dc:SetIgnoreParentScale(cfg.ignoreParentScale ~= false) end
        local strata = (type(cfg.strata)=="string" and cfg.strata) or (header:GetFrameStrata() or "FULLSCREEN_DIALOG")
        dc:SetFrameStrata(strata)
        local bias = tonumber(cfg.levelBias) or 10
        dc:SetFrameLevel((header:GetFrameLevel() or 10) + bias)
        if dc.SetAlpha then dc:SetAlpha(1) end
    end)

    -- 装饰计数位置变更后，通知 Dock 重新锚定 Header 内部的小部件（齿轮按钮等）
    if ADT and ADT.DockUI and ADT.DockUI.ReanchorHeaderWidgets then
        pcall(ADT.DockUI.ReanchorHeaderWidgets)
    end
end

-- 钩住所有子模式的 DecorCount：无论当前激活哪种模式，出现就对齐一次
local ALL_MODE_KEYS = {"ExpertDecorModeFrame","BasicDecorModeFrame","CustomizeModeFrame","CleanupModeFrame","LayoutModeFrame","ExteriorCustomizationModeFrame"}

-- 提前定义对齐函数，保证在任何调用发生前已经就绪
-- 上方已定义 _AnchorDecorCount；此处删除重复定义，避免覆盖时序问题。

local function EnsureDecorCountHooks()
    local hf = _G.HouseEditorFrame; if not hf then return end
    local dock = GetDock(); if not (dock and dock.Header) then return end
    for _, key in ipairs(ALL_MODE_KEYS) do
        local frm = hf[key]
        local dc = frm and frm.DecorCount
        if dc and not dc._ADT_AnchorInstalled then
            dc._ADT_AnchorInstalled = true
            -- 首次与每次显示都贴合到 Header
            dc:HookScript("OnShow", function(self) _AnchorDecorCount(self, dock.Header) end)
            -- 暴雪模板在 Layout/UpdateCount 后也可能调整尺寸/位置；这里跟进一次
            if hooksecurefunc then
                pcall(function() hooksecurefunc(dc, "Layout", function(self) _AnchorDecorCount(self, dock.Header) end) end)
                pcall(function() hooksecurefunc(dc, "UpdateCount", function(self) _AnchorDecorCount(self, dock.Header) end) end)
            end
            if dc:IsShown() then _AnchorDecorCount(dc, dock.Header) end
        end
    end
end

-- （已提前定义 _AnchorDecorCount ）

local function ShowBudgetInHeader()
    local dock = GetDock()
    if not dock or not dock.Header then return end
    EnsureDecorCountHooks()
    local dc = _GetAnyDecorCount()
    if not dc then return end
    if dc._ADTForceHidden then dc._ADTForceHidden = nil end
    _AnchorDecorCount(dc, dock.Header)
    if dc.Show then dc:Show() end
    if ADT and ADT.DockUI and ADT.DockUI.ReanchorHeaderWidgets then
        pcall(ADT.DockUI.ReanchorHeaderWidgets)
    end
    -- 首帧和后续尺寸变化都再对齐一次（不加循环，仅一次性延后）
    C_Timer.After(0, function() if dc and dock and dock.Header then _AnchorDecorCount(dc, dock.Header) end end)
    -- 一次性挂钩：当 DecorCount 再次 Show 时，重新对齐
    if not dc._ADT_AnchorHooked then
        dc._ADT_AnchorHooked = true
        dc:HookScript("OnShow", function(self)
            local d = GetDock(); if d and d.Header then _AnchorDecorCount(self, d.Header) end
        end)
    end
    Debug("已定位官方 DecorCount 到 Dock.Header")
end

local function RestoreHeaderTitle()
    local dock = GetDock()
    if not dock then return end
    -- 不再隐藏/替换 Header 标题；保持原始行为
    if dock.HeaderTitle and HeaderTitleBackup then
        dock.HeaderTitle:SetText(HeaderTitleBackup)
    end
end

-- 不再隐藏官方 DecorCount；若可用，直接定位并显示
local function HideOfficialDecorCountNow()
    ShowBudgetInHeader()
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

-- 高度自适应改由 SubPanel 统一测量与驱动；此处仅发出“请求自适配”。
local function _ADT_QueueResize()
    if not IsHouseEditorShown() then return end
    if ADT and ADT.DockUI and ADT.DockUI.RequestSubPanelAutoResize then
        ADT.DockUI.RequestSubPanelAutoResize()
    end
end

-- KISS 重构：删除所有样式劫持函数，保留暴雪原生样式

GetActiveModeFrame = function()
    if _G.HouseEditorFrame_GetFrame then
        local f = _G.HouseEditorFrame_GetFrame()
        if f and f.GetActiveModeFrame then
            return f:GetActiveModeFrame()
        end
    end
    return nil
end

--
-- 三、“放置的装饰”面板：交互锁定 + 由 LayoutManager 统一定位
local function GetPlacedDecorListFrame()
    local LM = ADT and ADT.HousingLayoutManager
    if LM and LM.GetPlacedDecorListFrame then
        return LM:GetPlacedDecorListFrame()
    end
    return nil
end

-- 通用：将任意框体贴合到 Dock.SubPanel 下方（若无 SubPanel 则贴 Dock 下边），并做等宽与高度保护
-- 注意：垂直间距由 CFG.Layout.verticalGapPx 统一权威提供。
local function AnchorFrameBelowDock(frame, cfg)
    if not frame or not frame.GetHeight then return end

    local dock = GetDock()
    if not dock then return end

    local anchor = dock.SubPanel or (dock.EnsureSubPanel and dock:EnsureSubPanel()) or dock
    if anchor and anchor.IsShown and not anchor:IsShown() then
        anchor = dock
    end

    local dxL = assert(cfg and cfg.anchorLeftCompensation)
    local dxR = assert(cfg and cfg.anchorRightCompensation)
    local dy  = (CFG and CFG.Layout and CFG.Layout.verticalGapPx) or 0

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT", dxL, -dy)
    frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", dxR, -dy)

    -- 层级：与 Dock 一致并略高，避免被遮挡
    pcall(function()
        local targetStrata = dock:GetFrameStrata() or "DIALOG"
        frame:SetFrameStrata(targetStrata)
        frame:SetFrameLevel((dock:GetFrameLevel() or 10) + 10)
    end)

    -- 绝不越出屏幕底部
    frame:SetClampedToScreen(true)
    local uiBottom = UIParent and (UIParent.GetBottom and UIParent:GetBottom()) or 0
    local topY = (anchor and anchor.GetBottom and anchor:GetBottom()) or (dock and dock:GetBottom()) or 0
    local available = math.max(120, (topY - dy - uiBottom) - 8) -- 8px 安全边距
    local curH = frame:GetHeight() or 300
    if curH > available + 0.5 then frame:SetHeight(available) end
end

local function EnsurePlacedListHooks()
    local list = GetPlacedDecorListFrame()
    if not list or list._ADT_Anchored then return end

    -- 一次性：禁用拖拽与关闭按钮（防止 StartMoving 报错 & 用户误关）
    local function LockInteractions()
        pcall(function()
            list:SetMovable(false)
            list:SetUserPlaced(false)
        end)
        if list.DragBar then
            list.DragBar:EnableMouse(false)
            list.DragBar:SetScript("OnMouseDown", nil)
            list.DragBar:SetScript("OnMouseUp", nil)
            list.DragBar.isMovingTarget = false
        end
        if list.CloseButton then
            list.CloseButton:Hide()
            list.CloseButton:EnableMouse(false)
            list.CloseButton:SetScript("OnClick", nil)
        end
    end
    LockInteractions()

    -- 动态自适应：显示期间开启一个轻量轮询（~5Hz），
    -- 防止暴雪内部在我们校准之后再次改变尺寸导致越界。
    local function StartWatcher()
        if list._ADT_resizerTicker then return end
        list._ADT_resizerTicker = C_Timer.NewTicker(0.2, function()
            if not list:IsShown() then return end
            RequestLayout("PlacedListWatcher")
        end)
    end
    local function StopWatcher()
        if list._ADT_resizerTicker then list._ADT_resizerTicker:Cancel(); list._ADT_resizerTicker = nil end
    end

    -- 首次显示：立即校准 + 启动 watcher
    list:HookScript("OnShow", function()
        LockInteractions()
        RequestLayout("PlacedListShow")
        C_Timer.After(0.05, function() RequestLayout("PlacedListShowDelay") end)
        StartWatcher()
    end)
    list:HookScript("OnSizeChanged", function() C_Timer.After(0, function() RequestLayout("PlacedListSizeChanged") end) end)
    list:HookScript("OnHide", function() StopWatcher() end)

    -- 主面板/子面板大小变化时也刷新一次（多源冗余保证）
    local dock = GetDock()
    if dock then
        if dock.HookScript then
            dock:HookScript("OnSizeChanged", function() C_Timer.After(0, function() RequestLayout("DockSizeChanged") end) end)
        end
        if dock.SubPanel and dock.SubPanel.HookScript then
            dock.SubPanel:HookScript("OnSizeChanged", function() C_Timer.After(0, function() RequestLayout("SubPanelSizeChanged") end) end)
            dock.SubPanel:HookScript("OnShow",       function() C_Timer.After(0, function() RequestLayout("SubPanelShow") end) end)
        end
    end
    list._ADT_Anchored = true
end

--
-- 四、染色弹窗（DyeSelectionPopout）：贴合 Dock.SubPanel 下方
--
local function GetDyePopoutFrame()
    return _G.DyeSelectionPopout
end

-- 统一：从某个“屏幕上的 Y 基准（通常是目标框体的顶/底）”向下可用高度，
-- 将 frame 的高度压缩到不超过该可用空间。
local function _ADT_ClampHeightFromTop(frame, topY)
    if not (frame and topY) then return end
    frame:SetClampedToScreen(true)
    local uiBottom = UIParent and (UIParent.GetBottom and UIParent:GetBottom()) or 0
    local safePad = (CFG and CFG.DyePopout and CFG.DyePopout.safetyBottomPad) or 8
    local available = math.max(120, (topY - uiBottom) - safePad)
    local curH = frame:GetHeight() or 0
    -- 记录“自然高度”（未被我们裁剪前的最大值），用于空间恢复时回弹。
    if (not frame._ADT_naturalHeight) or curH > (frame._ADT_naturalHeight + 0.5) then
        frame._ADT_naturalHeight = curH
    end
    local naturalH = frame._ADT_naturalHeight or curH

    -- 若自然高度超出可用空间，则裁剪到 available。
    if naturalH > available + 0.5 then
        if curH ~= available then frame:SetHeight(available) end
        frame._ADT_wasClamped = true
        return
    end

    -- 若此前被裁剪过，且当前空间足够，则回弹到自然高度。
    if frame._ADT_wasClamped and naturalH > curH + 0.5 and naturalH <= available + 0.5 then
        frame:SetHeight(naturalH)
    end
end

local function AnchorDyePopout()
    local pop = GetDyePopoutFrame()
    if not pop then return end

    -- 优先：贴在“当前显示的自定义面板”的左侧；无法获取时退化到 Dock 下沿策略
    local paneDecor, paneRoom = GetCustomizePanes()
    local pane = (paneDecor and paneDecor:IsShown()) and paneDecor
              or (paneRoom and paneRoom:IsShown()) and paneRoom
              or nil

    if pane then
        -- 顶部对齐 + 左侧相切
        local dx = -((CFG and CFG.DyePopout and CFG.DyePopout.horizontalGap) or 0) -- 以“相切”为 0，正值向内留白
        local dy = (CFG and CFG.DyePopout and CFG.DyePopout.verticalTopNudge) or 0
        pop:ClearAllPoints()
        pop:SetPoint("TOPRIGHT", pane, "TOPLEFT", dx, dy)

        -- 置于自定义面板之上，避免被遮挡
        pcall(function()
            local strata = pane:GetFrameStrata() or "DIALOG"
            pop:SetFrameStrata(strata)
            pop:SetFrameLevel((pane:GetFrameLevel() or 10) + 20)
        end)

        -- 先触发一次染色板自身布局，避免首帧/竞态下高度过小导致误裁剪。
        pcall(function()
            if pop.MarkDirty then pop:MarkDirty() end
            if pop.Layout then pop:Layout() end
            if pop.UpdateLayout then pop:UpdateLayout() end
        end)

        -- 自顶向下压缩，避免越出屏幕底部
        local topY = pane.GetTop and pane:GetTop()
        if topY then _ADT_ClampHeightFromTop(pop, topY) end
        return
    end

    -- 回落（无自定义面板显示时）：仍采用 Dock.SubPanel 下沿定位
    AnchorFrameBelowDock(pop, CFG.PlacedList)
end

local function EnsureDyePopoutHooks()
    local pop = GetDyePopoutFrame()
    if not pop or pop._ADT_Anchored then return end

    -- 短期 watcher：打开后 ~1s 内反复贴合/回弹，等待布局与 Dock 缩放稳定。
    local function StartWatcher()
        if pop._ADT_resizerTicker then pop._ADT_resizerTicker:Cancel(); pop._ADT_resizerTicker=nil end
        local checks = 0
        pop._ADT_resizerTicker = C_Timer.NewTicker(0.05, function(t)
            if not pop:IsShown() then t:Cancel(); pop._ADT_resizerTicker=nil; return end
            AnchorDyePopout()
            checks = checks + 1
            if checks >= 20 then t:Cancel(); pop._ADT_resizerTicker=nil end
        end)
    end
    local function StopWatcher()
        if pop._ADT_resizerTicker then pop._ADT_resizerTicker:Cancel(); pop._ADT_resizerTicker=nil end
    end

    -- 首次显示：先瞬时透明 + 立即贴合，再下一帧复位透明度，避免“先在原位闪现一帧再飞过去”
    pop:HookScript("OnShow", function(self)
        local prevA = (self.GetAlpha and self:GetAlpha()) or 1
        if self.SetAlpha then self:SetAlpha(0) end
        AnchorDyePopout()
        StartWatcher()
        C_Timer.After(0, function()
            AnchorDyePopout()
            if self.SetAlpha then self:SetAlpha(prevA) end
        end)
    end)
    pop:HookScript("OnSizeChanged", function() C_Timer.After(0, AnchorDyePopout) end)
    pop:HookScript("OnHide", function(self)
        StopWatcher()
        self._ADT_wasClamped = nil
        self._ADT_naturalHeight = nil
    end)

    -- Dock 或 SubPanel 变化时也刷新
    local dock = GetDock()
    if dock then
        if dock.HookScript then
            dock:HookScript("OnSizeChanged", function() C_Timer.After(0, function() if pop:IsShown() then AnchorDyePopout() end end) end)
        end
        if dock.SubPanel and dock.SubPanel.HookScript then
            dock.SubPanel:HookScript("OnSizeChanged", function() C_Timer.After(0, function() if pop:IsShown() then AnchorDyePopout() end end) end)
            dock.SubPanel:HookScript("OnShow",       function() C_Timer.After(0, function() if pop:IsShown() then AnchorDyePopout() end end) end)
        end
    end

    pop._ADT_Anchored = true
end

--
-- 五、定制面板（DecorCustomizationsPane/RoomComponentCustomizationsPane）：同样贴合 Dock.SubPanel 下方
--
GetCustomizePanes = function()
    local LM = ADT and ADT.HousingLayoutManager
    if LM and LM.GetCustomizePanes then
        return LM:GetCustomizePanes()
    end
    return nil, nil
end

-- 基于 Dock 宽度，计算“定制面板”的内容固定宽度（fixedWidth），避免依赖面板自身宽度
-- 说明：首次打开时 RoomComponentPane 在 :Show() 前就会执行 :Layout()，
-- 若此时仍是模板默认 fixedWidth=340，会造成首帧内容未对齐；
-- 这里直接以 Dock.SubPanel 的实际宽度作为权威来源计算 fixedWidth，
-- 消除与锚点/显示顺序相关的竞态。
local function _ADT_SyncPaneFixedWidthToDock(p)
    if not (p and p.SetFixedWidth) then return end
    local lp = tonumber(p.leftPadding) or 0
    local rp = tonumber(p.rightPadding) or 0
    local function apply(targetContentW)
        if not targetContentW or targetContentW <= 0 then return end
        local cw = math.max(1, targetContentW)
        if math.abs((p.fixedWidth or 0) - cw) > 0.5 then
            p:SetFixedWidth(cw)
            -- 关键修复：SetRoomComponentInfo 在 :Show() 之前会先调用 :Layout()，
            -- 这里必须在同步 fixedWidth 后主动触发布局，
            -- 而 VerticalLayoutFrame 使用的是 :Layout()（无 UpdateLayout）。
            if p.Layout then pcall(p.Layout, p) end
        end
    end
    -- 优先在“已锚定后”的时序直接以面板自身宽度为准（最稳妥）。
    local ownW = p.GetWidth and p:GetWidth()
    if ownW and ownW > 0 then
        return apply(ownW - lp - rp)
    end
    -- 早于 Show/布局时（如 SetRoomComponentInfo 早触发），退化到 Dock.SubPanel 的宽度估算。
    local dock = GetDock(); if not dock then return end
    local anchor = dock.SubPanel or (dock.EnsureSubPanel and dock:EnsureSubPanel()) or dock
    if not (anchor and anchor.GetWidth) then return end
    local dxL = assert(CFG and CFG.PlacedList and CFG.PlacedList.anchorLeftCompensation)
    local dxR = assert(CFG and CFG.PlacedList and CFG.PlacedList.anchorRightCompensation)
    local anchorW = anchor:GetWidth() or 0
    if anchorW <= 0 then return end
    apply(anchorW + (dxR or 0) - (dxL or 0) - lp - rp)
end

-- 轻量“跟随观察器”：面板可见期间短时监听宽度变化，确保与 SubPanel 动态缩放完全同步。
local function _ADT_EnsurePaneResizeWatcher(p)
    if not p or p._ADT_watcherTicker then return end
    local checks = 0
    p._ADT_watcherTicker = C_Timer.NewTicker(0.05, function(t)
        if not p:IsShown() then t:Cancel(); p._ADT_watcherTicker=nil; return end
        _ADT_SyncPaneFixedWidthToDock(p)
        checks = checks + 1
        -- 1. 在打开后一段时间内（~1s）持续跟随
        -- 2. 若外部仍在缩放，事件钩子也会触发；这里仅作为兜底补偿。
        if checks >= 20 then t:Cancel(); p._ADT_watcherTicker=nil end
    end)
end

local function AnchorCustomizePane()
    local paneDecor, paneRoom = GetCustomizePanes()
    if paneDecor and paneDecor:IsShown() then
        -- 仅同步 fixedWidth；纵向锚点由 LayoutManager 统一裁决
        _ADT_SyncPaneFixedWidthToDock(paneDecor)
    end
    if paneRoom and paneRoom:IsShown() then
        _ADT_SyncPaneFixedWidthToDock(paneRoom)
    end
    RequestLayout("CustomizePaneSync")
end

local function LockPaneDragging(p)
    if not p then return end
    pcall(function()
        p:SetMovable(false)
        p:SetUserPlaced(false)
        p:RegisterForDrag() -- 清空
        p:SetScript("OnDragStart", nil)
        p:SetScript("OnDragStop", nil)
    end)
end

local function EnsureCustomizePaneHooks()
    local paneDecor, paneRoom = GetCustomizePanes()
    if not (paneDecor or paneRoom) then return end

    for _, p in ipairs({paneDecor, paneRoom}) do
        if p and not p._ADT_Anchored then
            LockPaneDragging(p)
            -- 首次显示：透明→立即贴合→同步 fixedWidth→下一帧复位透明度，避免初次“飞入/未对齐”
            p:HookScript("OnShow", function(self)
                local prevA = (self.GetAlpha and self:GetAlpha()) or 1
                if self.SetAlpha then self:SetAlpha(0) end
                AnchorCustomizePane()
                _ADT_SyncPaneFixedWidthToDock(self)
                _ADT_EnsurePaneResizeWatcher(self)
                C_Timer.After(0, function()
                    AnchorCustomizePane()
                    _ADT_SyncPaneFixedWidthToDock(self)
                    if self.SetAlpha then self:SetAlpha(prevA) end
                end)
            end)
            p:HookScript("OnHide", function(self)
                if self._ADT_watcherTicker then self._ADT_watcherTicker:Cancel(); self._ADT_watcherTicker=nil end
            end)
            p:HookScript("OnSizeChanged", function() C_Timer.After(0, AnchorCustomizePane) end)
            p._ADT_Anchored = true
        end
    end

    local dock = GetDock()
    if dock then
        local function queueSync()
            C_Timer.After(0, function()
                AnchorCustomizePane()
                local d, r = GetCustomizePanes()
                if d and d:IsShown() then _ADT_SyncPaneFixedWidthToDock(d) end
                if r and r:IsShown() then _ADT_SyncPaneFixedWidthToDock(r) end
                if d and d:IsShown() then _ADT_EnsurePaneResizeWatcher(d) end
                if r and r:IsShown() then _ADT_EnsurePaneResizeWatcher(r) end
            end)
        end
        if dock.HookScript then
            dock:HookScript("OnSizeChanged", queueSync)
        end
        if dock.SubPanel and dock.SubPanel.HookScript then
            dock.SubPanel:HookScript("OnSizeChanged", queueSync)
            dock.SubPanel:HookScript("OnShow",       queueSync)
        end
        -- 关键：SubPanel 的 Content 区域宽度会随 DockUI 的统一左右留白动态调整；
        -- 仅监听 SubPanel 尺寸不足以捕捉“仅留白变化”的场景，这里补挂 Content 的 OnSizeChanged。
        local content = dock.SubPanel and dock.SubPanel.Content
        if content and content.HookScript then
            content:HookScript("OnSizeChanged", queueSync)
        end
    end

    -- 当进入“自定义模式”时，确保再次贴合
    if _G.HouseEditorCustomizeModeMixin then
        hooksecurefunc(HouseEditorCustomizeModeMixin, "OnShow", function()
            EnsureCustomizePaneHooks(); C_Timer.After(0, AnchorCustomizePane)
        end)
        hooksecurefunc(HouseEditorCustomizeModeMixin, "ShowSelectedDecorInfo", function()
            EnsureCustomizePaneHooks(); C_Timer.After(0, AnchorCustomizePane)
        end)
        hooksecurefunc(HouseEditorCustomizeModeMixin, "ShowSelectedRoomComponentInfo", function()
            EnsureCustomizePaneHooks(); C_Timer.After(0, AnchorCustomizePane)
        end)
    end
end

-- 首开不居中根因：SetRoomComponentInfo() 会在 Show 之前立即调用 :Layout()，
-- 此时 fixedWidth 仍为模板默认值（340）。在其执行后再同步 fixedWidth 并重排一次即可。
if _G.RoomComponentPaneMixin and not _G.RoomComponentPaneMixin._ADT_FixedWidthHooked then
    _G.RoomComponentPaneMixin._ADT_FixedWidthHooked = true
    hooksecurefunc(RoomComponentPaneMixin, "SetRoomComponentInfo", function(self)
        if not self then return end
        -- 在布局前强制以 Dock 宽度同步 fixedWidth，消除首开竞态
        _ADT_SyncPaneFixedWidthToDock(self)
        -- 再下一帧复核一次，覆盖 Dock/SubPanel 在本帧内发生的尺寸变化
        C_Timer.After(0, function() _ADT_SyncPaneFixedWidthToDock(self); _ADT_EnsurePaneResizeWatcher(self) end)
    end)
end

-- 额外：染色面板在部分客户端语言/缩放下也可能出现首帧错位，做同样的 fixedWidth 同步保护（若其支持）
if _G.HousingDyePaneMixin and not _G.HousingDyePaneMixin._ADT_FixedWidthHooked then
    _G.HousingDyePaneMixin._ADT_FixedWidthHooked = true
    hooksecurefunc(HousingDyePaneMixin, "SetDecorInfo", function(self)
        if not self then return end
        _ADT_SyncPaneFixedWidthToDock(self)
        C_Timer.After(0, function() _ADT_SyncPaneFixedWidthToDock(self); _ADT_EnsurePaneResizeWatcher(self) end)
    end)
end

-- 说明：12.0 后不再强制打开“放置的装饰”清单，
-- 但文件中仍有延迟调用点引用 ShowPlacedListIfExpertActive。
-- 为避免 C_Timer.After 传入 nil 回调导致报错，这里提供温和实现：
-- 仅在清单已由官方逻辑显示时进行一次锚点处理，不改变其显示状态。
local function ShowPlacedListIfExpertActive()
    local list = GetPlacedDecorListFrame()
    if not list then return end
    if not IsHouseEditorShown() then return end
    if list.IsShown and list:IsShown() then
        -- 仅在已显示时请求三层重排；不改变其显示状态。
        RequestLayout("PlacedListExpertActive")
    end
end

-- 判断是否处于“专家编辑模式”
-- 绑定到前向声明的同名局部变量，而不是重新声明新的 local
function IsHouseEditorShown()
    if _G.HouseEditorFrame_IsShown then
        return _G.HouseEditorFrame_IsShown()
    end
    local f = _G.HouseEditorFrame
    return f and f:IsShown()
end

local function AdoptInstructionsIntoDock()

    
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
        Debug("未找到 Instructions 容器，等待下一帧")
        return
    end
    
    -- 将 HoverHUD 挂到暴雪原生 Instructions 容器
    if ADT and ADT.Housing and ADT.Housing.ReparentHoverHUD then
        pcall(ADT.Housing.ReparentHoverHUD, ADT.Housing, instr)
    end
    
    -- 记录当前 Instructions（用于后续判断）
    AdoptState.instr = instr
    
    -- 显示预算
    ShowBudgetInHeader()
    Debug("已将 HoverHUD 挂到暴雪原生 Instructions 容器（KISS模式）")
end

local function RestoreInstructions()
    -- KISS 重构：无需恢复，因为我们没有移动暴雪容器
    AdoptState.instr = nil
    AdoptState.originalParent = nil
    AdoptState.restored = true
    Debug("RestoreInstructions called (KISS模式，无需恢复)")
end

--
-- 三、统一入口：HouseEditor 打开/关闭与模式变化时同步
--
EL = CreateFrame("Frame")

local function TrySetupHooks()
    if not _G.HouseEditorFrameMixin or EL._hooksInstalled then return end
    -- 钩住显示/隐藏与模式切换
    pcall(function()
        hooksecurefunc(HouseEditorFrameMixin, "OnShow", function()
            -- 直接隐藏官方按钮并在 Header 放置代理按钮（避免任何重挂跳动）
            pcall(function() if ADT and ADT.DockUI and ADT.DockUI.AttachPlacedListButton then ADT.DockUI.AttachPlacedListButton() end end)
            EnsurePlacedListHooks()
            EnsureDyePopoutHooks(); AnchorDyePopout()
            EnsureCustomizePaneHooks()
            RequestLayout("HouseEditorShow")
            HideOfficialDecorCountNow();
            ShowBudgetInHeader();
            C_Timer.After(0, AdoptInstructionsIntoDock)
            C_Timer.After(0.1, AdoptInstructionsIntoDock)
            C_Timer.After(0.05, ShowPlacedListIfExpertActive)
        end)
        hooksecurefunc(HouseEditorFrameMixin, "OnHide", function()
            RestoreHeaderTitle(); RestoreInstructions();
        end)
        hooksecurefunc(HouseEditorFrameMixin, "OnActiveModeChanged", function()
            pcall(function() if ADT and ADT.DockUI and ADT.DockUI.AttachPlacedListButton then ADT.DockUI.AttachPlacedListButton() end end)
            EnsurePlacedListHooks()
            EnsureDyePopoutHooks(); AnchorDyePopout()
            EnsureCustomizePaneHooks()
            RequestLayout("HouseEditorModeChanged")
            HideOfficialDecorCountNow()
            C_Timer.After(0, AdoptInstructionsIntoDock)
            C_Timer.After(0.1, AdoptInstructionsIntoDock)
            C_Timer.After(0.05, ShowPlacedListIfExpertActive)
        end)
        -- 专家模式 Frame 本体 OnShow：这是最稳的时点，直接确保展示与贴合
        -- 不再 hook 专家模式以强制打开清单（保持官方原样）
        -- 进入专家模式时自动显示官方“放置的装饰”清单（并在 OnShow 时贴合到 Dock.SubPanel 下缘）
        -- 对行控件进行二次清理：若设置了 _ADTForceHideControl 或检测到“选择装饰”文本，则强制隐藏
        -- KISS 重构：删除行级样式钩子（不再修改暴雪原生样式）
        EL._hooksInstalled = true
        Debug("已安装 HouseEditorFrameMixin 钩子")
    end)
end

-- 注册 EventRegistry 回调（额外冗余，优先触发）
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("HouseEditor.StateUpdated", function(_, isActive)
        TrySetupHooks()
        if isActive then
            -- 就位清单与按钮后再显示
            EnsurePlacedListHooks()
            EnsureDyePopoutHooks(); AnchorDyePopout()
            EnsureCustomizePaneHooks()
            RequestLayout("HouseEditorStateUpdated")
            HideOfficialDecorCountNow()
            pcall(function() if ADT and ADT.DockUI and ADT.DockUI.AttachPlacedListButton then ADT.DockUI.AttachPlacedListButton() end end)
            ShowBudgetInHeader();
            C_Timer.After(0, AdoptInstructionsIntoDock)
            C_Timer.After(0.1, AdoptInstructionsIntoDock)
            C_Timer.After(0.05, ShowPlacedListIfExpertActive)
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
            RestoreHeaderTitle();
            RestoreInstructions()
        end
    end, EL)
end

-- 事件：模式变化/加载/登录
EL:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
-- 选中目标变化：行数/内容会改变，需要触发一次自适应高度
EL:RegisterEvent("HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED")
EL:RegisterEvent("HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED")
EL:RegisterEvent("ADDON_LOADED")
EL:RegisterEvent("PLAYER_LOGIN")
EL:SetScript("OnEvent", function(_, event, arg1)
    if event == "HOUSE_EDITOR_MODE_CHANGED" then
        EnsurePlacedListHooks()
        EnsureDyePopoutHooks(); AnchorDyePopout()
        EnsureCustomizePaneHooks()
        RequestLayout("HouseEditorModeChangedEvent")
        HideOfficialDecorCountNow()
        EnsureDecorCountHooks()
        C_Timer.After(0, AdoptInstructionsIntoDock)
        C_Timer.After(0.1, AdoptInstructionsIntoDock)
        C_Timer.After(0.05, ShowPlacedListIfExpertActive)
        C_Timer.After(0.05, _ADT_QueueResize)
        C_Timer.After(0.15, _ADT_QueueResize)
    elseif event == "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED" or event == "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED" then
        -- 选中/取消选中都会改动说明行，分多帧排版
        C_Timer.After(0, _ADT_QueueResize)
        C_Timer.After(0.03, _ADT_QueueResize)
        C_Timer.After(0.1, _ADT_QueueResize)
    elseif event == "ADDON_LOADED" and (arg1 == "Blizzard_HouseEditor" or arg1 == ADDON_NAME) then
        TrySetupHooks()
        if IsHouseEditorShown() then
            EnsurePlacedListHooks()
            EnsureDyePopoutHooks(); AnchorDyePopout()
            EnsureCustomizePaneHooks()
            RequestLayout("AddonLoadedHouseEditor")
            HideOfficialDecorCountNow()
            EnsureDecorCountHooks()
            ShowBudgetInHeader()
            C_Timer.After(0, AdoptInstructionsIntoDock)
            C_Timer.After(0.05, ShowPlacedListIfExpertActive)
        end
    elseif event == "PLAYER_LOGIN" then
        TrySetupHooks()
        C_Timer.After(0.5, function()
            if IsHouseEditorShown() then
                EnsurePlacedListHooks()
                EnsureDyePopoutHooks(); AnchorDyePopout()
                EnsureCustomizePaneHooks()
                RequestLayout("PlayerLoginHouseEditor")
                HideOfficialDecorCountNow()
                EnsureDecorCountHooks()
                ShowBudgetInHeader()
                C_Timer.After(0, AdoptInstructionsIntoDock)
                C_Timer.After(0.05, ShowPlacedListIfExpertActive)
            end
        end)
    end
end)

-- 容错：如果当前就处于家宅编辑器，延迟一次尝试
C_Timer.After(1.0, function()
    TrySetupHooks()
    if IsHouseEditorShown() then
        EnsurePlacedListHooks()
        EnsureDyePopoutHooks(); AnchorDyePopout()
        EnsureCustomizePaneHooks()
        RequestLayout("HouseEditorFallbackInit")
        HideOfficialDecorCountNow()
        EnsureDecorCountHooks()
        ShowBudgetInHeader()
        C_Timer.After(0, AdoptInstructionsIntoDock)
        C_Timer.After(0.05, ShowPlacedListIfExpertActive)
    end
end)
