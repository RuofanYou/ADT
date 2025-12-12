-- Housing_LayoutManager.lua
-- 目的：
--  - 统一裁决住宅编辑右侧三层 UI（DockUI / SubPanel / 官方清单/自定义面板）的纵向布局
--  - 在小分辨率/高缩放下保证“永不越屏”，并按优先级收缩
--  - 视觉目标：SubPanel 尽量居中，上下与 Dock/官方面板相切
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

local function CalcGaps(Hd, Hs, Hl, gapPx)
    local g1 = (Hd > 0 and Hs > 0) and gapPx or 0
    local g2 = (Hs > 0 and Hl > 0) and gapPx or 0
    return g1, g2
end

local function SumHeights(Hd, Hs, Hl, gapPx)
    local g1, g2 = CalcGaps(Hd, Hs, Hl, gapPx)
    return Hd + Hs + Hl + g1 + g2, g1, g2
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

    -- 期望高度（内容驱动）
    local desiredDockH = tonumber(dock:GetHeight() or 0) or 0

    local sub = GetSubPanel(dock)
    local desiredSubH = 0
    if sub and sub.IsShown and sub:IsShown() then
        desiredSubH = tonumber(sub._ADT_DesiredHeight or sub:GetHeight() or 0) or 0
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

    -- 超屏按优先级收缩：SubPanel → 官方面板 → Dock
    local sum, g1, g2 = SumHeights(Hd, Hs, Hl, gapPx)
    local overflow = sum - H
    if overflow > 0 then
        local cutSub = math.min(overflow, Hs)
        Hs = Hs - cutSub
        overflow = overflow - cutSub
    end
    if overflow > 0 then
        local cutList = math.min(overflow, Hl)
        Hl = Hl - cutList
        overflow = overflow - cutList
    end
    if overflow > 0 then
        local reducibleDock = math.max(0, Hd - dockCritical)
        local cutDock = math.min(overflow, reducibleDock)
        Hd = Hd - cutDock
        overflow = overflow - cutDock
    end
    if overflow > 0 then
        -- 仍溢出：强制收敛到“Dock 最小临界 + 其他全 0”
        Hs = 0
        Hl = 0
        Hd = dockCritical
    end

    sum, g1, g2 = SumHeights(Hd, Hs, Hl, gapPx)
    Debug(string.format("applied Hd=%.1f Hs=%.1f Hl=%.1f sum=%.1f overflow=%.1f", Hd, Hs, Hl, sum, sum - H))

    -- 位置裁决
    local DockTopY, DockBottomY, SubTopY, SubBottomY, ListTopY, ListBottomY
    if Hs > 0 then
        local bias = tonumber(cfg.subPanelCenterBiasPx) or 0
        local centerY = (TopY + BottomY) * 0.5 + bias
        SubTopY = centerY + Hs * 0.5
        SubBottomY = centerY - Hs * 0.5

        DockBottomY = SubTopY + g1
        DockTopY = DockBottomY + Hd

        ListTopY = SubBottomY - g2
        ListBottomY = ListTopY - Hl
    else
        DockTopY = TopY
        DockBottomY = DockTopY - Hd
        local gapDL = (Hd > 0 and Hl > 0) and gapPx or 0
        ListTopY = DockBottomY - gapDL
        ListBottomY = ListTopY - Hl
        SubTopY, SubBottomY = DockBottomY, DockBottomY
    end

    -- 微量安全平移（理论上 sum<=H 时无需，但保留避免浮点/取整误差）
    local dy = 0
    if DockTopY > TopY then dy = dy - (DockTopY - TopY) end
    if ListBottomY < BottomY then dy = dy + (BottomY - ListBottomY) end
    if dy ~= 0 then
        DockTopY = DockTopY + dy; DockBottomY = DockBottomY + dy
        SubTopY = SubTopY + dy; SubBottomY = SubBottomY + dy
        ListTopY = ListTopY + dy; ListBottomY = ListBottomY + dy
    end

    return {
        rootTop = TopY,
        rootBottom = BottomY,
        rawRootTop = rawRootTop,
        rawRootBottom = rawRootBottom,
        dock = { topY = DockTopY, height = Hd },
        sub  = { height = Hs },
        list = { height = Hl },
        gaps = { g1 = g1, g2 = g2, gapPx = gapPx },
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

    -- 2) SubPanel：仅裁剪高度，不强制显隐（避免与内部逻辑竞争）
    local sub = GetSubPanel(dock)
    if sub and sub.SetHeight then
        local Hs = layout.sub.height
        -- 与 Dock 下缘保持相切/留白：纵向间距由 LayoutManager 单一裁决
        if sub.ClearAllPoints and dock.CentralSection then
            sub:ClearAllPoints()
            sub:SetPoint("TOPLEFT", dock.CentralSection, "BOTTOMLEFT", 0, -layout.gaps.g1)
            sub:SetPoint("TOPRIGHT", dock, "BOTTOMRIGHT", 0, -layout.gaps.g1)
        end
        if math.abs((sub:GetHeight() or 0) - Hs) > 0.5 then
            sub:SetHeight(Hs)
        end
    end

    -- 3) 官方面板：锚到 SubPanel（若高度>0）否则锚 Dock；高度由 LayoutManager 裁决
    local cfg = ADT.GetHousingCFG().PlacedList
    local gapBelow = (layout.list.height > 0 and layout.gaps.gapPx) or 0

    local anchor = dock
    if sub and (layout.sub.height > 0 or (sub.IsShown and sub:IsShown())) then
        anchor = sub
        gapBelow = (layout.list.height > 0 and layout.gaps.g2) or 0
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
        dock:HookScript("OnSizeChanged", function() LayoutManager:RequestLayout("DockSizeChanged") end)
    end

    local sub = dock and GetSubPanel(dock)
    if sub and not sub._ADT_LayoutHooked then
        sub._ADT_LayoutHooked = true
        sub:HookScript("OnShow", function() LayoutManager:RequestLayout("SubShow") end)
        sub:HookScript("OnHide", function() LayoutManager:RequestLayout("SubHide") end)
        sub:HookScript("OnSizeChanged", function() LayoutManager:RequestLayout("SubSizeChanged") end)
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
