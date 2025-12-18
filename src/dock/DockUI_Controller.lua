-- DockUI_Controller.lua
-- Controller 层：事件监听、用户交互响应、分类切换、数据变化刷新
-- 从 DockUI.lua 拆分，遵循 MVC 架构

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local UI = ADT.DockUI

-- ============================================================================
-- 暴雪按钮采纳事件监听（从 DockUI.lua 迁移）
-- ============================================================================

local function _IsExpertMode()
    local HEM = C_HouseEditor and C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode()
    return HEM == (Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.ExpertDecor)
end

local function SetupPlacedListButtonWatcher()
    local EL = CreateFrame("Frame")
    EL:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    EL:RegisterEvent("ADDON_LOADED")
    EL:RegisterEvent("PLAYER_LOGIN")
    EL:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_HouseEditor" then
            if UI.AttachPlacedListButton then UI.AttachPlacedListButton() end
        elseif event == "PLAYER_LOGIN" then
            if UI.AttachPlacedListButton then UI.AttachPlacedListButton() end
        elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
            if C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() and _IsExpertMode() then
                if UI.AttachPlacedListButton then UI.AttachPlacedListButton() end
            else
                if UI.RestorePlacedListButton then UI.RestorePlacedListButton() end
            end
        end
    end)
end

-- 立即设置暴雪按钮监听（不需要等待 MainFrame）
SetupPlacedListButtonWatcher()

-- ============================================================================
-- 分类切换事件（View 触发，Controller 处理）
-- ============================================================================

-- 分类选择回调（由 LeftPanel.OnClick 触发）
function UI.OnCategorySelected(categoryKey, categoryType)
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then return end
    
    if categoryType == 'decorList' then
        if MainFrame.ShowDecorListCategory then
            MainFrame:ShowDecorListCategory(categoryKey)
        end
    elseif categoryType == 'dyePresetList' then
        if MainFrame.ShowDyePresetsCategory then
            MainFrame:ShowDyePresetsCategory(categoryKey)
        end
    elseif categoryType == 'about' then
        if MainFrame.ShowAboutCategory then
            MainFrame:ShowAboutCategory(categoryKey)
        end
    elseif categoryType == 'keybinds' then
        if MainFrame.ShowKeybindsCategory then
            MainFrame:ShowKeybindsCategory(categoryKey)
        end
    else
        if MainFrame.ShowSettingsCategory then
            MainFrame:ShowSettingsCategory(categoryKey)
        end
    end
    
    -- 高亮当前分类
    if MainFrame.HighlightCategoryByKey then
        MainFrame:HighlightCategoryByKey(categoryKey)
    end
    
    -- 记录最后选中的分类
    if ADT and ADT.SetDBValue then
        ADT.SetDBValue('LastCategoryKey', categoryKey)
    end
    
    -- 播放切换音效
    if ADT and ADT.UI and ADT.UI.PlaySoundCue then
        ADT.UI.PlaySoundCue('ui.tab.switch')
    end
end

-- ============================================================================
-- OnShow 分类恢复逻辑（从 DockUI.lua 迁移）
-- ============================================================================

local function SetupOnShowHandler()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame or not MainFrame.ModuleTab then return end
    
    local Tab1 = MainFrame.ModuleTab
    
    Tab1:SetScript("OnShow", function()
        if MainFrame.ApplyDockPlacement then MainFrame:ApplyDockPlacement() end
        
        -- KISS：优先使用"当前内存中的已选分类"，仅在无当前状态时才回退到持久化记录
        local key = MainFrame.currentDecorCategory 
            or MainFrame.currentDyePresetsCategory 
            or MainFrame.currentAboutCategory 
            or MainFrame.currentSettingsCategory 
            or (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey'))
        
        -- 首次无记录时，显式记录并使用 "Housing" 作为默认分类
        if (not ADT.GetDBValue('LastCategoryKey')) then
            if ADT and ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', 'Housing') end
            key = 'Housing'
        end
        
        -- 显式首选"通用"（Housing）作为回退；若无则再选第一个设置类
        if not key then
            local housing = CommandDock:GetCategoryByKey('Housing')
            if housing and housing.categoryType == 'settings' then
                key = 'Housing'
            end
        end
        
        if ADT and ADT.DebugPrint then
            local cw = MainFrame.CentralSection and MainFrame.CentralSection:GetWidth() or 0
            local ch = MainFrame.CentralSection and MainFrame.CentralSection:GetHeight() or 0
            ADT.DebugPrint(string.format("[Controller] OnShow: key=%s, center=%.1fx%.1f", tostring(key), cw, ch))
        end
        
        -- 顶部标签系统（如启用）
        local USE_TOP_TABS = MainFrame.USE_TOP_TABS or false
        if USE_TOP_TABS and MainFrame.TopTabOwner and MainFrame.__tabIDFromKey then
            local id = MainFrame.__tabIDFromKey[key] or MainFrame.__tabIDFromKey['Housing'] or 1
            MainFrame.TopTabOwner:SetTab(id)
            return
        end

        -- 根据分类类型切换到对应页面
        local cat = key and CommandDock:GetCategoryByKey(key) or nil
        if cat and cat.categoryType == 'decorList' then
            MainFrame:ShowDecorListCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'dyePresetList' then
            MainFrame:ShowDyePresetsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'about' then
            MainFrame:ShowAboutCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'keybinds' then
            MainFrame:ShowKeybindsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        elseif cat and cat.categoryType == 'settings' then
            MainFrame:ShowSettingsCategory(key)
            MainFrame:HighlightCategoryByKey(key)
        else
            -- 默认回退到第一个"设置类"分类（若存在 Housing 优先）
            local all = CommandDock:GetSortedModules()
            local firstSettings
            for _, info in ipairs(all) do
                if info.key == 'Housing' and info.categoryType ~= 'decorList' and info.categoryType ~= 'about' then
                    firstSettings = 'Housing'
                    break
                end
            end
            for _, info in ipairs(all) do
                if info.categoryType ~= 'decorList' and info.categoryType ~= 'about' then
                    firstSettings = firstSettings or info.key
                    break
                end
            end
            if firstSettings then
                MainFrame:ShowSettingsCategory(firstSettings)
                MainFrame:HighlightCategoryByKey(firstSettings)
            else
                MainFrame:RefreshFeatureList()
            end
        end
        
        if MainFrame.UpdateAutoWidth then MainFrame:UpdateAutoWidth() end
        
        -- 静态左窗跟随定位
        if (ADT.DockLeft and ADT.DockLeft.IsStatic and ADT.DockLeft.IsStatic()) 
           and MainFrame.UpdateStaticLeftPlacement then
            C_Timer.After(0, function()
                if MainFrame:IsShown() then
                    MainFrame:UpdateStaticLeftPlacement()
                end
            end)
        end
    end)
end

-- ============================================================================
-- AnchorWatcher：分辨率/缩放变化事件（从 DockUI.lua 迁移）
-- ============================================================================

local function SetupAnchorWatcher()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then return end
    
    local AnchorWatcher = CreateFrame("Frame", nil, MainFrame)
    AnchorWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    AnchorWatcher:RegisterEvent("UI_SCALE_CHANGED")
    AnchorWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    AnchorWatcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    AnchorWatcher:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            if MainFrame and MainFrame.ApplyDockPlacement then
                MainFrame:ApplyDockPlacement()
            end
            if MainFrame and MainFrame.UpdateAutoWidth then
                MainFrame:UpdateAutoWidth()
            end
        end)
    end)
end

-- ============================================================================
-- 数据变化回调（Clipboard/History）（从 DockUI.lua 迁移）
-- ============================================================================

local function SetupDataChangeCallbacks()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then return end
    
    -- Clipboard 数据变化时刷新
    if ADT.Clipboard then
        local origOnChanged = ADT.Clipboard.OnChanged
        ADT.Clipboard.OnChanged = function(self)
            if origOnChanged then origOnChanged(self) end
            -- 如果当前显示的是临时板分类，则刷新列表
            if MainFrame:IsShown() and MainFrame.currentDecorCategory == 'Clipboard' then
                MainFrame:ShowDecorListCategory('Clipboard')
            end
            -- 刷新分类列表的数量角标
            MainFrame:RefreshCategoryList()
        end
    end

    -- History 数据变化时刷新
    if ADT.History then
        local origOnHistoryChanged = ADT.History.OnHistoryChanged
        ADT.History.OnHistoryChanged = function(self)
            if origOnHistoryChanged then origOnHistoryChanged(self) end
            -- 如果当前显示的是最近放置分类，则刷新列表
            if MainFrame:IsShown() and MainFrame.currentDecorCategory == 'History' then
                MainFrame:ShowDecorListCategory('History')
            end
            -- 刷新分类列表的数量角标
            MainFrame:RefreshCategoryList()
        end
    end
end

-- ============================================================================
-- 设置订阅（从 DockUI.lua 迁移）
-- ============================================================================

local function SetupSettingsSubscriptions()
    -- 订阅"进入编辑器自动打开 Dock"设置，实时应用默认显隐
    if ADT and ADT.Settings and ADT.Settings.On then
        ADT.Settings.On('EnableDockAutoOpenInEditor', function()
            if ADT and ADT.DockUI and ADT.DockUI.ApplyPanelsDefaultVisibility then
                ADT.DockUI.ApplyPanelsDefaultVisibility()
            end
        end)
    end
end

-- ============================================================================
-- ESC 关闭逻辑（从 DockUI.lua 迁移）
-- ============================================================================

local function SetupEscapeHandler()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then return end
    
    -- HandleEscape is defined in DockUI.lua (View layer)
    
    -- ESC 关闭功能（按 ESC 关闭面板）
    local CloseDummy = CreateFrame("Frame", "ADTSettingsPanelSpecialFrame", UIParent)
    CloseDummy:Hide()
    table.insert(UISpecialFrames, CloseDummy:GetName())

    CloseDummy:SetScript("OnHide", function()
        if MainFrame:HandleEscape() then
            CloseDummy:Show()
        end
    end)

    MainFrame:HookScript("OnShow", function()
        if MainFrame.mode == "standalone" then
            CloseDummy:Show()
        end
    end)

    MainFrame:HookScript("OnHide", function()
        CloseDummy:Hide()
    end)
end

-- ============================================================================
-- EditorWatcher：编辑模式自动打开/关闭（从 DockUI.lua 迁移）
-- ============================================================================

local function SetupEditorWatcher()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then return end
    
    local EditorWatcher = CreateFrame("Frame")
    local wasEditorActive = false
    
    local function UpdateEditorState()
        local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
        
        if isActive then
            if not wasEditorActive then
                -- 进入编辑模式：无论是否默认开启，都先创建并显示 Dock 容器，
                -- 再按用户设置隐藏/显示"主体面板"。这样 SubPanel/清单仍可独立工作。
                MainFrame:ShowUI("editor")
                
                -- 若默认开启，则聚焦到"通用"分类；否则仅保持容器存在
                local v = ADT and ADT.GetDBValue and ADT.GetDBValue('EnableDockAutoOpenInEditor')
                local shouldAutoOpen = (v ~= false)
                if shouldAutoOpen then
                    C_Timer.After(0, function()
                        -- 优先恢复上次停留的分类；若无记录再回退到"通用"。
                        local key = (ADT and ADT.GetDBValue and ADT.GetDBValue('LastCategoryKey')) or 'Housing'
                        local cat = CommandDock and CommandDock.GetCategoryByKey and CommandDock:GetCategoryByKey(key)
                        if not cat then
                            key = 'Housing'
                            cat = CommandDock and CommandDock.GetCategoryByKey and CommandDock:GetCategoryByKey(key)
                        end
                        if cat then
                            if cat.categoryType == 'decorList' and MainFrame.ShowDecorListCategory then
                                MainFrame:ShowDecorListCategory(key)
                            elseif cat.categoryType == 'about' and MainFrame.ShowAboutCategory then
                                MainFrame:ShowAboutCategory(key)
                            elseif cat.categoryType == 'keybinds' and MainFrame.ShowKeybindsCategory then
                                MainFrame:ShowKeybindsCategory(key)
                            elseif MainFrame.ShowSettingsCategory then
                                MainFrame:ShowSettingsCategory(key)
                            end
                            if ADT and ADT.SetDBValue then
                                ADT.SetDBValue('LastCategoryKey', key)
                            end
                        end
                    end)
                end
                
                -- 应用默认显隐（只影响 Dock 主体，不影响 SubPanel）
                C_Timer.After(0, function()
                    if ADT and ADT.DockUI and ADT.DockUI.ApplyPanelsDefaultVisibility then
                        ADT.DockUI.ApplyPanelsDefaultVisibility()
                    end
                end)
            end
            
            -- 调整层级确保在编辑器之上
            if HouseEditorFrame then
                MainFrame:SetParent(HouseEditorFrame)
                MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            end
        else
            -- 退出编辑模式：隐藏 GUI
            MainFrame:SetParent(UIParent)
            MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            MainFrame:Hide()
        end
        
        wasEditorActive = isActive
    end
    
    EditorWatcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    EditorWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    EditorWatcher:SetScript("OnEvent", function(_, event)
        if event == "HOUSE_EDITOR_MODE_CHANGED" then
            -- 离开编辑模式时，立刻隐藏以避免可见闪烁；进入时再做轻微延迟以等待编辑器完成布局
            local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
            if not isActive then
                -- 立即隐藏，不等待
                if MainFrame then
                    MainFrame:SetParent(UIParent)
                    MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                    MainFrame:Hide()
                end
                wasEditorActive = false
                return
            end
        end
        -- 进入或其它情况：短延迟以确保编辑器框架已就位
        C_Timer.After(0.05, UpdateEditorState)
    end)
end

-- ShowUI is defined in DockUI.lua (View layer)

-- ============================================================================
-- Controller 初始化入口
-- ============================================================================

local function InitController()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then
        -- 延迟初始化，等待 View 创建完成
        C_Timer.After(0.1, InitController)
        return
    end
    
    -- 如果已初始化则跳过
    if MainFrame._ControllerInitialized then return end
    MainFrame._ControllerInitialized = true
    
    -- 按顺序设置各个 Controller 组件
    SetupSettingsSubscriptions()
    SetupEscapeHandler()
    SetupEditorWatcher()
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[Controller] DockUI Controller initialized")
    end
end

-- 在 CreateUI 完成后设置 OnShow/AnchorWatcher/DataCallbacks
-- 这些需要在 UI 创建完成后才能设置
function UI.InitControllerPostCreate()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not MainFrame then return end
    
    SetupOnShowHandler()
    SetupAnchorWatcher()
    SetupDataChangeCallbacks()
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[Controller] Post-create handlers initialized")
    end
end

-- 启动初始化
InitController()
