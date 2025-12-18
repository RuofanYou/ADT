-- DockUI_Collapse.lua
-- DockUI 折叠/展开与面板显隐逻辑

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local GetDBBool = ADT.GetDBBool

-- ============================================================================
-- 工具函数
-- ============================================================================

local function SetShownSafe(f, shown)
    if not f then return end
    if shown then f:Show() else f:Hide() end
end

local function ReadCollapsed()
    if GetDBBool then return GetDBBool('DockCollapsed') end
    return (ADT and ADT.GetDBValue and ADT.GetDBValue('DockCollapsed')) and true or false
end

-- ============================================================================
-- 折叠/展开逻辑
-- ============================================================================

function ADT.DockUI.IsCollapsed()
    return not not ReadCollapsed()
end

function ADT.DockUI.SetCollapsed(state)
    local v = not not state
    local CommandDock = ADT.CommandDock
    -- 进入折叠前，记录当前所处分类
    if v then
        local main = CommandDock and CommandDock.SettingsPanel
        if main then
            local key = main.currentDecorCategory or main.currentDyePresetsCategory or main.currentAboutCategory or main.currentSettingsCategory
            if not key and ADT and ADT.GetDBValue then
                key = ADT.GetDBValue('LastCategoryKey')
            end
            ADT.DockUI._lastCategoryKey = key
        end
    end

    if ADT and ADT.SetDBValue then ADT.SetDBValue('DockCollapsed', v, true) end
    ADT.DockUI.ApplyCollapsedAppearance()
    if ADT and ADT.HousingLayoutManager and ADT.HousingLayoutManager.RequestLayout then
        ADT.HousingLayoutManager:RequestLayout('DockCollapsedChanged')
    end
end

function ADT.DockUI.ToggleCollapsed()
    ADT.DockUI.SetCollapsed(not ReadCollapsed())
end

-- 根据当前 DB 状态应用显隐
function ADT.DockUI.ApplyCollapsedAppearance()
    local CommandDock = ADT.CommandDock
    local main = CommandDock and CommandDock.SettingsPanel
    if not main then return end
    local collapsed = ReadCollapsed()
    -- 关键修复：当“默认开启设置面板”被关闭（或用户主动隐藏主体面板）时，
    -- 此函数不应再次根据折叠状态把主体各区块显示出来。
    -- 之前的实现会在 ApplyPanelsDefaultVisibility() 之后被调用，
    -- 由于这里无条件按“折叠状态”改写显隐，导致进入编辑器时面板又被显示。
    -- 现在按 ADT.DockUI._mainPanelsVisible 作为总开关：为 false 时，
    -- 直接隐藏主体相关元素并返回，保持 SubPanel 独立工作。
    local mainPanelsVisible = not not ADT.DockUI._mainPanelsVisible
    if not mainPanelsVisible then
        SetShownSafe(main.LeftSlideContainer, false)
        SetShownSafe(main.LeftPanelContainer, false)
        SetShownSafe(main.CenterBackground, false)
        SetShownSafe(main.RightUnifiedBackground, false)
        if main.ModuleTab then SetShownSafe(main.ModuleTab, false) end
        if main.CentralSection then SetShownSafe(main.CentralSection, false) end
        -- 头部与边框也一并隐藏，避免“已关闭默认开启”仍出现齿轮与木框
        SetShownSafe(main.Header, false)
        if main.BorderFrame then SetShownSafe(main.BorderFrame, false) end
        return
    end
    local Def = ADT.DockUI.Def

    -- 左侧独立层
    SetShownSafe(main.LeftSlideContainer, not collapsed)
    SetShownSafe(main.LeftPanelContainer, not collapsed)

    -- 右侧主体
    SetShownSafe(main.CenterBackground, not collapsed)
    SetShownSafe(main.RightUnifiedBackground, not collapsed)
    if main.ModuleTab then SetShownSafe(main.ModuleTab, not collapsed) end
    if main.CentralSection then SetShownSafe(main.CentralSection, not collapsed) end

    -- Header 与 Border 在主体可见时始终可见
    SetShownSafe(main.Header, true)
    if main.BorderFrame then
        main.BorderFrame:ClearAllPoints()
        if collapsed and main.Header then
            main.BorderFrame:SetPoint("TOPLEFT", main.Header, "TOPLEFT", 0, 0)
            main.BorderFrame:SetPoint("BOTTOMRIGHT", main.Header, "BOTTOMRIGHT", 0, 0)
        else
            main.BorderFrame:SetAllPoints(main)
        end
        SetShownSafe(main.BorderFrame, true)
    end

    -- 立即把 Dock 高度收敛到 Header
    if collapsed and main.SetHeight and main.Header and main.Header.GetHeight then
        local hh = tonumber(main.Header:GetHeight() or 0) or 0
        if hh > 0 then main:SetHeight(hh) end
    end

    -- 齿轮按钮选中态
    if main._ADT_GearButton and main._ADT_GearButton.ActiveOverlay then
        main._ADT_GearButton.ActiveOverlay:SetShown(collapsed)
    end

    -- 展开后刷新
    if not collapsed then
        local function _refresh()
            local m = ADT and ADT.CommandDock and ADT.CommandDock.SettingsPanel
            if not m then return end
            local sv = m.ModuleTab and m.ModuleTab.ScrollView
            if sv and sv.OnSizeChanged then sv:OnSizeChanged(true) end
            if m._SyncCentralTemplateWidths then m:_SyncCentralTemplateWidths(true) end
            if m.ModuleTab and m.ModuleTab.ScrollBar and m.ModuleTab.ScrollBar.UpdateThumbRange then
                m.ModuleTab.ScrollBar:UpdateThumbRange()
            end
            local key = m.currentDecorCategory or m.currentDyePresetsCategory or m.currentAboutCategory or m.currentSettingsCategory
            if key and ADT and ADT.CommandDock and ADT.CommandDock.GetCategoryByKey then
                local cat = ADT.CommandDock:GetCategoryByKey(key)
                if cat then
                    if cat.categoryType == 'decorList' and m.ShowDecorListCategory then
                        m:ShowDecorListCategory(key)
                    elseif cat.categoryType == 'dyePresetList' and m.ShowDyePresetsCategory then
                        m:ShowDyePresetsCategory(key)
                    elseif cat.categoryType == 'about' and m.ShowAboutCategory then
                        m:ShowAboutCategory(key)
                    elseif cat.categoryType == 'keybinds' and m.ShowKeybindsCategory then
                        m:ShowKeybindsCategory(key)
                    elseif m.ShowSettingsCategory then
                        m:ShowSettingsCategory(key)
                    end
                end
            end
        end
        C_Timer.After(0, _refresh)
        C_Timer.After(0.05, _refresh)
        C_Timer.After(0.15, _refresh)
    end
end

-- ============================================================================
-- 面板显隐控制
-- ============================================================================

-- 单一权威：外部仅调用这一个入口控制 Dock 主体是否可见
function ADT.DockUI.SetMainPanelsVisible(shown)
    local CommandDock = ADT.CommandDock
    local main = CommandDock and CommandDock.SettingsPanel
    if not main then return end
    local vis = not not shown

    -- 左侧
    SetShownSafe(main.LeftSlideContainer, vis)
    SetShownSafe(main.LeftPanelContainer, vis)

    -- 右侧
    SetShownSafe(main.Header, vis)
    SetShownSafe(main.RightUnifiedBackground, vis)
    SetShownSafe(main.CenterBackground, vis)
    if main.ModuleTab then SetShownSafe(main.ModuleTab, vis) end
    if main.CentralSection then SetShownSafe(main.CentralSection, vis) end
    if main.BorderFrame then SetShownSafe(main.BorderFrame, vis) end

    ADT.DockUI._mainPanelsVisible = vis

    if vis then
        C_Timer.After(0, function()
            local m = ADT and ADT.CommandDock and ADT.CommandDock.SettingsPanel
            if not m then return end
            local sv = m.ModuleTab and m.ModuleTab.ScrollView
            if sv and sv.OnSizeChanged then sv:OnSizeChanged(true) end
            if m._SyncCentralTemplateWidths then m:_SyncCentralTemplateWidths(true) end
            if m.ModuleTab and m.ModuleTab.ScrollBar and m.ModuleTab.ScrollBar.UpdateThumbRange then
                m.ModuleTab.ScrollBar:UpdateThumbRange()
            end
        end)
    end
end

function ADT.DockUI.AreMainPanelsVisible()
    return not not ADT.DockUI._mainPanelsVisible
end

function ADT.DockUI.ApplyPanelsDefaultVisibility()
    local CommandDock = ADT.CommandDock
    local main = CommandDock and CommandDock.SettingsPanel
    if not main then return end
    local v = ADT and ADT.GetDBValue and ADT.GetDBValue('EnableDockAutoOpenInEditor')
    local shouldShowMainPanels = (v ~= false)
    ADT.DockUI.SetMainPanelsVisible(shouldShowMainPanels)
    if ADT and ADT.DockUI and ADT.DockUI.ApplyCollapsedAppearance then
        ADT.DockUI.ApplyCollapsedAppearance()
    end
end

-- ============================================================================
-- SubPanel 自适应高度请求（占位包装器）
-- ============================================================================

if not ADT.DockUI.RequestSubPanelAutoResize then
    ADT.DockUI.RequestSubPanelAutoResize = function()
        local CommandDock = ADT.CommandDock
        local main = CommandDock and CommandDock.SettingsPanel
        local sub = main and (main.SubPanel or (main.EnsureSubPanel and main:EnsureSubPanel()))
        local caller = sub and sub._ADT_RequestAutoResize
        if type(caller) == "function" then
            caller()
            return
        end
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
