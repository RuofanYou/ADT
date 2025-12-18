-- Housing_LayoutManager.lua
-- 目的：
--  - 统一裁决住宅编辑右侧三层 UI（DockUI / SubPanel / 官方清单/自定义面板）的纵向布局
--  - DockUI 永远停靠在屏幕右上角；高度只随分辨率/缩放变化做裁剪，不随其它内容高频跳动
--  - SubPanel 永远贴在 DockUI 下方；官方面板永远贴在 SubPanel 下方（SubPanel 不可用则贴 DockUI 下方）
--  - 在小分辨率/高缩放下保证“永不越屏”，并按优先级收缩（优先压缩官方面板，再压缩 SubPanel）
-- 约束：
--  - 仅做 UI 布局，不改官方面板数据/刷新逻辑
--  - 参数全部配置驱动（单一权威见 Housing_Config.lua → CFG.Layout）

local ADDON_NAME, ADT = ...
if not ADT then return end

local API = ADT.API
local Clamp = API and API.Clamp or function(v, minV, maxV)
    v = tonumber(v) or 0
    minV = tonumber(minV) or 0
    maxV = tonumber(maxV) or minV
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function Debug(msg)
    if ADT and ADT.DebugPrint then
        ADT.DebugPrint("[Layout] " .. tostring(msg))
    end
end

local LayoutManager = {}
ADT.HousingLayoutManager = LayoutManager

-- ===========================
-- LayoutRoot：稳定的布局根锚点（永远存在）
-- ===========================
local LayoutRoot = CreateFrame("Frame", "ADT_HousingLayoutRoot", UIParent)
LayoutRoot:EnableMouse(false)
LayoutRoot:SetAlpha(0)
LayoutRoot:Show()

local function GetRootParent()
    if HouseEditorFrame and HouseEditorFrame.IsShown and HouseEditorFrame:IsShown() then
        return HouseEditorFrame
    end
    return UIParent
end

function LayoutManager:EnsureRoot()
    local parent = GetRootParent()
    if self._rootParent ~= parent then
        self._rootParent = parent
        LayoutRoot:ClearAllPoints()
        LayoutRoot:SetAllPoints(parent)
        pcall(function()
            LayoutRoot:SetFrameStrata(parent:GetFrameStrata() or "DIALOG")
            LayoutRoot:SetFrameLevel((parent:GetFrameLevel() or 0) + 1)
        end)
        LayoutRoot:Show()
        Debug("LayoutRoot 绑定到 " .. tostring(parent:GetName() or "UIParent"))
    end
    return LayoutRoot
end

-- ===========================
-- 官方面板获取（单一权威）
-- ===========================
function LayoutManager:GetPlacedDecorListFrame()
    local hf = _G.HouseEditorFrame
    local expert = hf and hf.ExpertDecorModeFrame
    return expert and expert.PlacedDecorList or nil
end

function LayoutManager:GetCustomizePanes()
    local hf = _G.HouseEditorFrame
    local customize = hf and hf.CustomizeModeFrame
    local decorPane = customize and customize.DecorCustomizationsPane
    local roomPane  = customize and customize.RoomComponentCustomizationsPane
    return decorPane, roomPane
end

function LayoutManager:GetVisibleOfficialFrames()
    local out = {}
    local list = self:GetPlacedDecorListFrame()
    if list and list.IsShown and list:IsShown() then out[#out+1] = list end
    local decorPane, roomPane = self:GetCustomizePanes()
    if decorPane and decorPane.IsShown and decorPane:IsShown() then out[#out+1] = decorPane end
    if roomPane and roomPane.IsShown and roomPane.IsShown and roomPane:IsShown() then out[#out+1] = roomPane end
    return out
end

-- Dock / SubPanel
local function GetDock()
    return ADT and ADT.CommandDock and ADT.CommandDock.SettingsPanel or nil
end
local function GetSubPanel(dock)
    if not dock then return nil end
    -- 重要：LayoutManager 不主动创建 SubPanel。
    -- SubPanel 的创建应当由其自身业务（如 HoverHUD/提示）驱动；
    -- LayoutManager 只在其“已存在且显示”时纳入布局，避免因 EnsureSubPanel() 早期创建导致宽度为 0 的竞态。
    return dock.SubPanel or nil
end

local function GetLayoutCFG()
    local cfg = ADT and ADT.GetHousingCFG and ADT.GetHousingCFG()
    return cfg and cfg.Layout or {}
end

-- ===========================
-- 宽度锚点：当 SubPanel 不存在/不可用时，仍让暴雪面板与 DockUI 的“中央区域”保持等宽
-- 说明：
--  - SubPanel 的真实宽度来源是 Dock.CentralSection（BOTTOMLEFT）→ Dock（BOTTOMRIGHT）
--  - 若 SubPanel 不存在，则用一个 1px 高度的“内容锚点”复制同样的水平范围，作为官方面板的宽度裁决源
-- ===========================
local function GetDockCentralWidthPx(dock)
    if not (dock and dock.GetWidth) then return nil end
    local totalW = tonumber(dock:GetWidth() or 0) or 0
    if totalW <= 0 then return nil end

    local sideW = 0
    if dock.LeftSection and dock.LeftSection.GetWidth then
        sideW = tonumber(dock.LeftSection:GetWidth() or 0) or 0
    end
    if sideW <= 0 then
        sideW = tonumber(dock.sideSectionWidth or 0) or 0
    end

    local centralW = totalW - math.max(0, sideW)
    if centralW <= 0 then return nil end
    return centralW
end

function LayoutManager:GetOfficialPanelFrameWidthPx()
    local dock = GetDock()
    if not dock then return nil end

    local cfg = ADT and ADT.GetHousingCFG and ADT.GetHousingCFG()
    local placedCfg = cfg and cfg.PlacedList or nil
    if not placedCfg then return nil end
    local dxL = tonumber(placedCfg.anchorLeftCompensation or 0) or 0
    local dxR = tonumber(placedCfg.anchorRightCompensation or 0) or 0

    -- 优先：可见 SubPanel 的实际宽度（最贴近“真实渲染结果”）
    local sub = dock.SubPanel
    if sub and sub.IsShown and sub:IsShown() and sub.GetWidth then
        local w = tonumber(sub:GetWidth() or 0) or 0
        if w > 0 then return w + dxR - dxL end
    end

    -- 否则：由 Dock 的“总宽 - 左栏宽”推导中央区域宽度
    local centralW = GetDockCentralWidthPx(dock)
    if not centralW then return nil end
    return centralW + dxR - dxL
end

function LayoutManager:SyncPaneFixedWidthToDock(p)
    if not (p and p.SetFixedWidth) then return end
    local lp = tonumber(p.leftPadding) or 0
    local rp = tonumber(p.rightPadding) or 0

    -- 已锚定且可测量：以面板自身宽度为准（最稳）
    local ownW = (p.GetWidth and tonumber(p:GetWidth() or 0)) or 0
    local frameW = (ownW and ownW > 0) and ownW or (self:GetOfficialPanelFrameWidthPx() or 0)
    if not frameW or frameW <= 0 then return end

    local cw = math.max(1, frameW - lp - rp)
    if math.abs((p.fixedWidth or 0) - cw) > 0.5 then
        p:SetFixedWidth(cw)
        -- VerticalLayoutFrame 使用 :Layout()，这里同步触发布局以消除“首帧默认 340”竞态
        if p.Layout then pcall(p.Layout, p) end
    end
end

function LayoutManager:EnsureDockContentAnchor(dock)
    if not dock then return nil end
    if self._dockContentAnchor and self._dockContentAnchorOwner == dock then
        return self._dockContentAnchor
    end

    local a = CreateFrame("Frame", nil, dock)
    a:EnableMouse(false)
    a:SetAlpha(0)
    a:SetHeight(1)
    a:Show()
    self._dockContentAnchor = a
    self._dockContentAnchorOwner = dock
    return a
end

function LayoutManager:UpdateDockContentAnchor(dock)
    if not dock then return nil end
    local a = self:EnsureDockContentAnchor(dock)
    if not a then return nil end
    local left = (dock.CentralSection and dock.CentralSection.GetBottom and dock.CentralSection.GetLeft) and dock.CentralSection or dock

    a:ClearAllPoints()
    -- 与 SubPanel 的水平裁决保持一致：LEFT 跟随 CentralSection，RIGHT 跟随 Dock
    a:SetPoint("BOTTOMLEFT",  left, "BOTTOMLEFT",  0, 0)
    a:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", 0, 0)
    a:Show()
    return a
end

local function CalcStackGaps(Hd, Hs, Hl, gapPx)
    local dockToSub = (Hd > 0 and Hs > 0) and gapPx or 0
    local subToList = (Hs > 0 and Hl > 0) and gapPx or 0
    local dockToList = (Hd > 0 and Hs <= 0 and Hl > 0) and gapPx or 0
    return dockToSub, subToList, dockToList
end

local function SumStackHeights(Hd, Hs, Hl, gapPx)
    local dockToSub, subToList, dockToList = CalcStackGaps(Hd, Hs, Hl, gapPx)
    return Hd + Hs + Hl + dockToSub + subToList + dockToList, dockToSub, subToList, dockToList
end

-- ===========================
-- 核心：计算最终高度与位置
-- ===========================
function LayoutManager:ComputeLayout()
    local dock = GetDock()
    if not (dock and dock.GetHeight) then return nil end

    local cfg = GetLayoutCFG()
    local root = self:EnsureRoot()
    local screenH = root.GetHeight and root:GetHeight() or (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 0

    local rawRootTop = root.GetTop and root:GetTop() or screenH
    local rawRootBottom = root.GetBottom and root:GetBottom() or 0
    local topSafe = tonumber(cfg.topSafeMarginPx) or 0
    local bottomSafe = tonumber(cfg.bottomSafeMarginPx) or 8
    local TopY = rawRootTop - topSafe
    local BottomY = rawRootBottom + bottomSafe
    local H = math.max(0, TopY - BottomY)

    local gapPx = tonumber(cfg.verticalGapPx) or 0

    -- 期望高度（内容驱动，但必须稳定）：
    -- Dock 期望高度由 DockUI 在创建时记录为 _ADT_DesiredHeight（单一权威）。
    -- 若缺失，则仅在首次计算时采样一次当前高度，避免“裁剪后的高度反过来变成新期望”造成抖动。
    local desiredDockH = tonumber(dock._ADT_DesiredHeight)
    if not desiredDockH or desiredDockH <= 0 then
        desiredDockH = tonumber(dock:GetHeight() or 0) or 0
        if desiredDockH > 0 then
            dock._ADT_DesiredHeight = desiredDockH
        end
    end

    -- 折叠模式：Dock 期望高度改为 Header 高度（KISS）
    do
        local isCollapsed = ADT and ADT.DockUI and ADT.DockUI.IsCollapsed and ADT.DockUI.IsCollapsed()
        if isCollapsed then
            local hh = (dock.Header and dock.Header.GetHeight and dock.Header:GetHeight()) or 0
            if hh <= 0 and ADT and ADT.DockUI and ADT.DockUI.Def then
                hh = tonumber(ADT.DockUI.Def.HeaderHeight) or hh
            end
            if hh and hh > 0 then desiredDockH = hh end
        end
    end

    local sub = GetSubPanel(dock)
    local desiredSubH = 0
    if sub and sub.IsShown and sub:IsShown() then
        desiredSubH = tonumber(sub._ADT_DesiredHeight)
        if not desiredSubH or desiredSubH <= 0 then
            desiredSubH = tonumber(sub:GetHeight() or 0) or 0
            if desiredSubH > 0 then
                sub._ADT_DesiredHeight = desiredSubH
            end
        end
    end

    local officialFrames = self:GetVisibleOfficialFrames()
    local desiredListH = 0
    for _, f in ipairs(officialFrames) do
        local h = tonumber(f.GetHeight and f:GetHeight() or 0) or 0
        if h > desiredListH then desiredListH = h end
    end

    Debug(string.format("desired Hd=%.1f Hs=%.1f Hl=%.1f screenH=%.1f H=%.1f", desiredDockH, desiredSubH, desiredListH, screenH, H))

    -- 套 min/max（Dock）
    local dockMin = tonumber(cfg.dockMinHeightPx) or 160
    local dockCritical = tonumber(cfg.dockMinHeightCriticalPx) or dockMin
    local dockMaxRatio = tonumber(cfg.dockMaxHeightViewportRatio) or 0.32
    local dockMaxPx = math.floor(screenH * dockMaxRatio + 0.5)
    if dockMaxPx < dockMin then dockMaxPx = dockMin end
    local Hd = Clamp(desiredDockH, dockMin, dockMaxPx)
    -- 视口过小/极端缩放：Dock 自身也必须保证不越屏
    if H > 0 then
        Hd = math.min(Hd, H)
        if H >= dockCritical then
            Hd = math.max(Hd, dockCritical)
        end
    end

    -- 套 min/max（SubPanel）
    local subMin = tonumber(cfg.subPanelMinHeight) or 160
    local subAbsMax = tonumber(cfg.subPanelMaxHeight) or 720
    local subMaxRatio = tonumber(cfg.subPanelMaxHeightViewportRatio) or 0.40
    local subMaxPx = math.floor(screenH * subMaxRatio + 0.5)
    subMaxPx = math.min(subAbsMax, subMaxPx)
    if subMaxPx < subMin then subMaxPx = subMin end
    local Hs = (desiredSubH > 0) and Clamp(desiredSubH, subMin, subMaxPx) or 0

    -- 套 min/max（官方面板，默认不扩展，只裁剪）
    local blizMin = tonumber(cfg.blizzardMinHeightPx) or 0
    local Hl = (desiredListH > 0) and math.max(blizMin, desiredListH) or 0

    -- Stack 模式（KISS）：Dock 固定在 TopY；SubPanel 永远在 Dock 下方；官方面板永远在 SubPanel 下方。
    -- 约束：Dock 不因 SubPanel/官方面板的高度变化而移动（避免竞态争夺 Dock 位置）。
    local DockTopY = TopY
    local DockBottomY = DockTopY - Hd

    -- 可用高度（Dock 下方）
    local belowH = math.max(0, DockBottomY - BottomY)

    -- 依序分配（KISS）：先 SubPanel，再官方面板。
    -- 目的：SubPanel 永远紧接 Dock；空间不足时优先牺牲官方面板。
    do
        if Hs > 0 then
            local dockToSubGap = gapPx
            local subFit = math.max(0, belowH - dockToSubGap)
            Hs = math.min(Hs, subFit)
            if Hs <= 0 then
                Hs = 0
            end
        end

        if Hs > 0 then
            local dockToSubGap = gapPx
            local remaining = math.max(0, belowH - dockToSubGap - Hs)
            if Hl > 0 then
                local subToListGap = gapPx
                local listFit = math.max(0, remaining - subToListGap)
                Hl = math.min(Hl, listFit)
                if Hl <= 0 then Hl = 0 end
            end
        else
            if Hl > 0 then
                local dockToListGap = gapPx
                local listFit = math.max(0, belowH - dockToListGap)
                Hl = math.min(Hl, listFit)
                if Hl <= 0 then Hl = 0 end
            end
        end
    end

    local sum, dockToSubGap, subToListGap, dockToListGap = SumStackHeights(Hd, Hs, Hl, gapPx)
    Debug(string.format("applied Hd=%.1f Hs=%.1f Hl=%.1f sum=%.1f overflow=%.1f", Hd, Hs, Hl, sum, sum - H))

    return {
        rootTop = TopY,
        rootBottom = BottomY,
        rawRootTop = rawRootTop,
        rawRootBottom = rawRootBottom,
        dock = { topY = DockTopY, height = Hd },
        sub  = { height = Hs },
        list = { height = Hl },
        gaps = { dockToSub = dockToSubGap, subToList = subToListGap, dockToList = dockToListGap, gapPx = gapPx },
    }
end

local function AnchorOfficialFrame(frame, anchor, cfg, gapPx)
    if not (frame and anchor and frame.ClearAllPoints and frame.SetPoint) then return end
    local dxL = assert(cfg and cfg.anchorLeftCompensation)
    local dxR = assert(cfg and cfg.anchorRightCompensation)
    local gap = gapPx or 0
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT", dxL, -gap)
    frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", dxR, -gap)
end

-- ===========================
-- 应用布局（唯一权威）
-- ===========================
function LayoutManager:ApplyLayout(reason)
    if self._inApply then return end
    self._inApply = true

    local layout = self:ComputeLayout()
    if not layout then self._inApply = nil; return end

    local dock = GetDock()
    if not dock then self._inApply = nil; return end

    -- 1) Dock：设置高度 + 通过 verticalOffsetOverride 走 ApplyDockPlacement
    local Hd = layout.dock.height
    if dock.GetHeight and math.abs((dock:GetHeight() or 0) - Hd) > 0.5 then
        dock:SetHeight(Hd)
    end
    dock._ADT_VerticalOffsetOverride = (layout.dock.topY - layout.rawRootTop)
    if dock.ApplyDockPlacement then
        dock:ApplyDockPlacement()
    else
        -- 极端早期：直接锚 LayoutRoot
        dock:ClearAllPoints()
        dock:SetPoint("TOPRIGHT", LayoutRoot, "TOPRIGHT", 0, dock._ADT_VerticalOffsetOverride)
    end

    -- 2) SubPanel：永远贴在 Dock 下方；仅裁剪高度，不强制显隐（避免与内部逻辑竞争）
    local sub = GetSubPanel(dock)
    if sub and sub.SetHeight then
        local Hs = layout.sub.height
        -- 与 Dock 下缘保持相切/留白：纵向间距由 LayoutManager 单一裁决
        if sub.ClearAllPoints and dock.CentralSection then
            sub:ClearAllPoints()
            sub:SetPoint("TOPLEFT", dock.CentralSection, "BOTTOMLEFT", 0, -layout.gaps.dockToSub)
            sub:SetPoint("TOPRIGHT", dock, "BOTTOMRIGHT", 0, -layout.gaps.dockToSub)
        end
        if math.abs((sub:GetHeight() or 0) - Hs) > 0.5 then
            sub:SetHeight(Hs)
        end
    end

    -- 3) 官方面板：永远锚到 SubPanel（若高度>0）否则锚 Dock；高度由 LayoutManager 裁决
    local cfg = ADT.GetHousingCFG().PlacedList
    local anchor = self:UpdateDockContentAnchor(dock) or dock
    local gapBelow = (layout.list.height > 0 and layout.gaps.dockToList) or 0
    if sub and (layout.sub.height > 0) then
        anchor = sub
        gapBelow = (layout.list.height > 0 and layout.gaps.subToList) or 0
    end

    local officialFrames = self:GetVisibleOfficialFrames()
    for _, f in ipairs(officialFrames) do
        AnchorOfficialFrame(f, anchor, cfg, gapBelow)
        -- 自定义面板（Decor/RoomComponent）需要同步 fixedWidth，否则会被模板默认值（340）卡住
        if f.SetFixedWidth then
            self:SyncPaneFixedWidthToDock(f)
        end
        if f.SetHeight then
            local Hl = layout.list.height
            if Hl <= 1 then
                f:SetHeight(1)
                f:Hide()
            else
                f:SetHeight(Hl)
            end
        end
    end

    Debug("ApplyLayout: reason=" .. tostring(reason))
    self._inApply = nil
end

-- ===========================
-- 触发与防抖
-- ===========================
function LayoutManager:RequestLayout(reason)
    if self._inApply then return end
    if self._pending then return end
    self._pending = true
    C_Timer.After(0, function()
        self._pending = nil
        LayoutManager:EnsureHooks()
        LayoutManager:ApplyLayout(reason)
    end)
end

function LayoutManager:EnsureHooks()
    local dock = GetDock()
    if dock and not dock._ADT_LayoutHooked then
        dock._ADT_LayoutHooked = true
        dock:HookScript("OnShow", function() LayoutManager:RequestLayout("DockShow") end)
        dock:HookScript("OnHide", function() LayoutManager:RequestLayout("DockHide") end)
        -- 重要：不监听 Dock 的 OnSizeChanged。
        -- Dock 内部会因内容/字体测量反复触发 UpdateAutoWidth → ApplyDockPlacement，
        -- 若此处再抢占布局，会导致高频重排甚至抖动。
        -- 但“官方面板等宽”必须跟随 Dock 的动态宽度，因此只在 UpdateAutoWidth 完成后请求一次布局（带防抖）。
        if dock.UpdateAutoWidth and hooksecurefunc and not dock._ADT_UpdateAutoWidthHooked then
            dock._ADT_UpdateAutoWidthHooked = true
            hooksecurefunc(dock, "UpdateAutoWidth", function()
                LayoutManager:RequestLayout("DockAutoWidth")
            end)
        end
    end

    local sub = dock and GetSubPanel(dock)
    if sub and not sub._ADT_LayoutHooked then
        sub._ADT_LayoutHooked = true
        sub:HookScript("OnShow", function() LayoutManager:RequestLayout("SubShow") end)
        sub:HookScript("OnHide", function() LayoutManager:RequestLayout("SubHide") end)
        -- 同理：不监听 SubPanel 的 OnSizeChanged，避免与其内部自适应高度竞态。
    end
end

-- 视口变化监听（独立帧，关注点分离）
local Watcher = CreateFrame("Frame", nil, UIParent)
Watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
Watcher:RegisterEvent("UI_SCALE_CHANGED")
Watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
Watcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
Watcher:SetScript("OnEvent", function()
    LayoutManager:RequestLayout("ViewportChanged")
end)

-- 初次加载次帧跑一次（防止先于 HouseEditorFrame 创建时取不到尺寸）
C_Timer.After(0, function() LayoutManager:RequestLayout("Init") end)
