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
    return dock.SubPanel or (dock.EnsureSubPanel and dock:EnsureSubPanel()) or nil
end

local function GetLayoutCFG()
    local cfg = ADT and ADT.GetHousingCFG and ADT.GetHousingCFG()
    return cfg and cfg.Layout or {}
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
    local anchor = dock
    local gapBelow = (layout.list.height > 0 and layout.gaps.dockToList) or 0
    if sub and (layout.sub.height > 0) then
        anchor = sub
        gapBelow = (layout.list.height > 0 and layout.gaps.subToList) or 0
    end

    local officialFrames = self:GetVisibleOfficialFrames()
    for _, f in ipairs(officialFrames) do
        AnchorOfficialFrame(f, anchor, cfg, gapBelow)
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
