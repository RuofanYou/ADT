-- Page_Keybinds.lua
-- 快捷键页面渲染器

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding

local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

-- ============================================================================
-- 页面渲染器
-- ============================================================================

local PageKeybinds = {}

function PageKeybinds:Render(mainFrame, categoryKey)
    if ADT.DebugPrint then
        ADT.DebugPrint("[PageKeybinds] Render called with key=" .. tostring(categoryKey))
    end
    if not (mainFrame.ModuleTab and mainFrame.ModuleTab.ScrollView) then
        mainFrame.__pendingTabKey = categoryKey
        return false
    end
    local cat = CommandDock:GetCategoryByKey(categoryKey)
    if not cat or cat.categoryType ~= 'keybinds' then return false end
    
    mainFrame.currentDecorCategory = nil
    mainFrame.currentAboutCategory = nil
    mainFrame.currentKeybindsCategory = categoryKey
    mainFrame.currentSettingsCategory = nil
    if ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
    
    local content = {}
    local n = 0
    local buttonHeight = Def.ButtonSize
    local fromOffsetY = Def.ButtonSize
    local offsetY = fromOffsetY
    local offsetX = GetRightPadding()
    
    -- 标题
    n = n + 1
    content[n] = {
        dataIndex = n,
        templateKey = "Header",
        setupFunc = function(obj)
            obj:SetText(cat.categoryName)
            if obj.Left then obj.Left:Hide() end
            if obj.Right then obj.Right:Hide() end
            if obj.Divider then obj.Divider:Show() end
            obj.Label:SetJustifyH("LEFT")
            
            -- 创建提示文本
            if not obj._keybindHint then
                local KCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.KeybindUI) or {}
                local hintOffsetX = KCFG.headerHintOffsetX or -8
                local hintOffsetY = KCFG.headerHintOffsetY or 0
                local hint = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                hint:SetDrawLayer("OVERLAY", 7)
                hint:SetPoint("RIGHT", obj, "RIGHT", hintOffsetX, hintOffsetY)
                hint:SetJustifyH("RIGHT")
                hint:SetTextColor(0.6, 0.8, 1, 1)
                
                if not obj._adt_hintHooked then
                    obj:HookScript("OnHide", function() if hint then hint:Hide() end end)
                    obj:HookScript("OnShow", function() if hint then hint:Show() end end)
                    obj._adt_hintHooked = true
                end
                obj._keybindHint = hint
            end
            obj._keybindHint:SetText("")
            obj._keybindHint:Show()
            mainFrame._keybindCategoryHint = obj._keybindHint
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + Def.ButtonSize,
        offsetX = GetRightPadding(),
    }
    offsetY = offsetY + Def.ButtonSize
    
    -- 获取快捷键动作
    local actions = ADT.Keybinds and ADT.Keybinds.GetAllActions and ADT.Keybinds:GetAllActions() or {}
    
    if #actions == 0 then
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(ADT.L["Keybinds Module Not Loaded"])
                SetTextColor(obj.Label, Def.TextColorDisabled)
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Hide() end
                obj.Label:SetJustifyH("LEFT")
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + buttonHeight,
            offsetX = offsetX,
        }
    else
        for _, actionInfo in ipairs(actions) do
            n = n + 1
            local top = offsetY
            local bottom = offsetY + buttonHeight + 2
            local capAction = actionInfo
            content[n] = {
                dataIndex = n,
                templateKey = "KeybindEntry",
                setupFunc = function(obj)
                    obj:SetKeybindByActionName(capAction.name)
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                top = top,
                bottom = bottom,
                offsetX = offsetX,
            }
            offsetY = bottom
        end
        
        -- 底部提示
        offsetY = offsetY + Def.ButtonSize
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                obj:SetText(ADT.L["Keybinds Housing Only Hint"])
                SetTextColor(obj.Label, Def.TextColorWarn or {1, 0.82, 0})
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Hide() end
                obj.Label:SetJustifyH("LEFT")
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + buttonHeight,
            offsetX = offsetX,
        }
        
        -- 恢复默认按钮
        offsetY = offsetY + buttonHeight + 8
        n = n + 1
        local resetBtnH = 24
        content[n] = {
            dataIndex = n,
            templateKey = "CenterButton",
            setupFunc = function(btn)
                if btn.SetText then btn:SetText(ADT.L["Reset All Keybinds"]) end
                btn:SetScript("OnClick", function()
                    if ADT.Keybinds and ADT.Keybinds.ResetAllToDefaults then
                        ADT.Keybinds:ResetAllToDefaults()
                        if ADT.Notify then ADT.Notify(ADT.L["Keybinds Reset Done"]) end
                        local mf = ADT.DockUI.GetMainFrame()
                        if mf then mf:ShowKeybindsCategory(categoryKey) end
                    end
                end)
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + resetBtnH,
            offsetX = offsetX,
        }
    end
    
    mainFrame.ModuleTab.ScrollView:SetContent(content, false)
    if mainFrame.UpdateAutoWidth then mainFrame:UpdateAutoWidth() end
    return true
end

-- ============================================================================
-- 注册页面
-- ============================================================================

ADT.DockPages:Register("keybinds", PageKeybinds)
ADT.DockPages.PageKeybinds = PageKeybinds
