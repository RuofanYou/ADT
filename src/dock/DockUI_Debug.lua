-- DockUI_Debug.lua
-- DockUI 调试设施（命令行工具）

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock

-- ============================================================================
-- 调试工具函数
-- ============================================================================

local strataIndex = {
    BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3, DIALOG = 4,
    FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7,
}

local function SIdx(s)
    return strataIndex[tostring(s or "")] or -1
end

local function FrameInfo(f)
    if not f then return "<nil>" end
    local n = f.GetName and f:GetName() or "<anon>"
    local s = f.GetFrameStrata and f:GetFrameStrata() or "?"
    local l = f.GetFrameLevel and f:GetFrameLevel() or -1
    local m = f.IsMouseEnabled and f:IsMouseEnabled() and 1 or 0
    local v = f.IsVisible and f:IsVisible() and 1 or 0
    return string.format("%s strata=%s(%d) level=%d mouse=%d vis=%d", n, tostring(s), SIdx(s), l, m, v)
end

-- ============================================================================
-- 实时追踪
-- ============================================================================

local traceTicker, traceOn

local function traceTick()
    if not (ADT and ADT.DebugPrint) then return end
    local MainFrame = CommandDock and CommandDock.SettingsPanel
    local focus = GetMouseFocus and GetMouseFocus() or nil
    local focusName = focus and (focus.GetName and focus:GetName()) or tostring(focus)
    local L = MainFrame and MainFrame.LeftSlideContainer
    local H = MainFrame and MainFrame.LeftSlideHandle
    local R = MainFrame and MainFrame.RightSection
    ADT.DebugPrint(string.format("[DockTrace] focus=%s", tostring(focusName)))
    if L then ADT.DebugPrint("[DockTrace] LeftSlide  "..FrameInfo(L)) end
    if H then ADT.DebugPrint("[DockTrace] LeftHandle "..FrameInfo(H)) end
    if R then ADT.DebugPrint("[DockTrace] RightSect  "..FrameInfo(R)) end
end

function ADT.DockUI.SetTrace(state)
    traceOn = not not state
    if traceOn and not traceTicker then
        traceTicker = C_Timer.NewTicker(0.25, traceTick)
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[DockTrace] 开启 (0.25s)") end
    elseif (not traceOn) and traceTicker then
        traceTicker:Cancel(); traceTicker = nil
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[DockTrace] 关闭") end
    end
end

function ADT.DockUI.Diag(reason)
    if ADT and ADT.DebugPrint then
        ADT.DebugPrint("[DockDiag] reason="..tostring(reason))
        traceTick()
    end
end

-- ============================================================================
-- /adtdockstack - 打印鼠标命中栈
-- ============================================================================

function ADT.DockUI.Stack()
    if not (ADT and ADT.DebugPrint) then return end
    if not GetMouseFoci then
        ADT.DebugPrint("[DockStack] GetMouseFoci 不可用（需要 11.0+）")
        return
    end
    local list = {GetMouseFoci()}
    ADT.DebugPrint("[DockStack] size="..tostring(#list))
    for i, f in ipairs(list) do
        local name = f and (f.GetName and f:GetName()) or tostring(f)
        local s = f and (f.GetFrameStrata and f:GetFrameStrata()) or "?"
        local l = f and (f.GetFrameLevel and f:GetFrameLevel()) or -1
        local m = f and (f.IsMouseEnabled and f:IsMouseEnabled()) and 1 or 0
        ADT.DebugPrint(string.format("[DockStack] %02d %s strata=%s lvl=%d mouse=%d", i, tostring(name), tostring(s), l, m))
    end
end

SLASH_ADT_DOCKSTACK1 = "/adtdockstack"
SlashCmdList["ADT_DOCKSTACK"] = function()
    if ADT and ADT.DockUI and ADT.DockUI.Stack then ADT.DockUI.Stack() end
end

-- ============================================================================
-- /adtghost - 幽灵框体扫描
-- ============================================================================

local function RectOverlap(aL, aR, aT, aB, bL, bR, bT, bB)
    if not (aL and aR and aT and aB and bL and bR and bT and bB) then return false end
    if aL >= aR or bL >= bR or aB >= aT or bB >= bT then return false end
    return not (aR <= bL or aL >= bR or aT <= bB or aB >= bT)
end

local function ScanGhosts()
    local main = CommandDock and CommandDock.SettingsPanel
    if not (main and main.Header and main.LeftSection) then
        ADT.DebugPrint("[Ghost] 主面板未就绪")
        return
    end
    local zoneL, zoneR, zoneT, zoneB
    zoneL = main.LeftSection:GetLeft() or 0
    zoneR = main.LeftSection:GetRight() or 0
    zoneT = (main.Header and main.Header:GetBottom()) or (main:GetTop() or 0)
    zoneB = main:GetBottom() or 0
    ADT.DebugPrint(string.format("[Ghost] LeftZone L/R/T/B = %.1f/%.1f/%.1f/%.1f", zoneL, zoneR, zoneT, zoneB))
    local i, f = 0
    f = EnumerateFrames()
    local hits = 0
    while f do
        i = i + 1
        if f.IsShown and f:IsShown() and f.IsMouseEnabled and f:IsMouseEnabled() then
            local L = f.GetLeft and f:GetLeft()
            local R = f.GetRight and f:GetRight()
            local T = f.GetTop and f:GetTop()
            local B = f.GetBottom and f:GetBottom()
            if RectOverlap(L, R, T, B, zoneL, zoneR, zoneT, zoneB) then
                hits = hits + 1
                local name = (f.GetName and f:GetName()) or tostring(f)
                local strata = (f.GetFrameStrata and f:GetFrameStrata()) or "?"
                local lvl = (f.GetFrameLevel and f:GetFrameLevel()) or -1
                ADT.DebugPrint(string.format("[Ghost] #%d %s strata=%s lvl=%d L/R/T/B=%.1f/%.1f/%.1f/%.1f",
                    hits, tostring(name), tostring(strata), lvl, L or -1, R or -1, T or -1, B or -1))
            end
        end
        f = EnumerateFrames(f)
    end
    if hits == 0 then ADT.DebugPrint("[Ghost] 未发现可拦截鼠标的重叠框体。") end
end

SLASH_ADT_GHOST1 = "/adtghost"
SlashCmdList["ADT_GHOST"] = function()
    pcall(ScanGhosts)
end

-- ============================================================================
-- /adtdockisolate - 隔离模式
-- ============================================================================

local _isolated = false

local function ApplyIsolation(state)
    _isolated = state and true or false
    local m = CommandDock and CommandDock.SettingsPanel
    if not m then return end
    -- 右侧鼠标阻挡层
    if m.MouseBlocker then
        m.MouseBlocker:SetShown(not _isolated)
        m.MouseBlocker:EnableMouse(not _isolated)
    end
    -- 子面板
    if m.SubPanel then
        if m.SetSubPanelShown then
            m:SetSubPanelShown(not _isolated and m.SubPanel:IsShown())
        else
            m.SubPanel:SetShown(not _isolated and m.SubPanel:IsShown())
        end
        if m.SubPanel.BorderFrame then m.SubPanel.BorderFrame:EnableMouse(false) end
    end
    ADT.DebugPrint("[Dock] Isolation="..tostring(_isolated))
end

SLASH_ADT_DOCKISOLATE1 = "/adtdockisolate"
SlashCmdList["ADT_DOCKISOLATE"] = function(msg)
    msg = tostring(msg or ""):lower()
    if msg == "on" or msg == "1" or msg == "true" then
        ApplyIsolation(true)
    elseif msg == "off" or msg == "0" or msg == "false" then
        ApplyIsolation(false)
    else
        ADT.DebugPrint("用法：/adtdockisolate on|off")
    end
end
