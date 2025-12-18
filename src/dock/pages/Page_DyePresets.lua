-- Page_DyePresets.lua
-- 染色预设页面渲染器

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

local PageDyePresets = {}

function PageDyePresets:Render(mainFrame, categoryKey)
    if not (mainFrame.ModuleTab and mainFrame.ModuleTab.ScrollView) then
        mainFrame.__pendingTabKey = categoryKey
        return false
    end
    local cat = CommandDock:GetCategoryByKey(categoryKey)
    if not cat or cat.categoryType ~= 'dyePresetList' then return false end
    
    mainFrame.currentDecorCategory = nil
    mainFrame.currentSettingsCategory = nil
    mainFrame.currentAboutCategory = nil
    mainFrame.currentDyePresetsCategory = categoryKey
    if ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
    
    local list = cat.getListData and cat.getListData() or {}
    local content = {}
    local n = 0
    local buttonHeight = 32
    local fromOffsetY = Def.ButtonSize
    local offsetY = fromOffsetY
    local buttonGap = 2
    local offsetX = GetRightPadding()
    
    -- 分类标题
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
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + Def.ButtonSize,
        offsetX = GetRightPadding(),
    }
    offsetY = offsetY + Def.ButtonSize
    
    -- 保存按钮
    n = n + 1
    local saveBtnH = 28
    content[n] = {
        dataIndex = n,
        templateKey = "CenterButton",
        setupFunc = function(btn)
            local btnText = ADT.L["Save Current Dye"] or "保存当前染色"
            if btn.SetText then btn:SetText(btnText) end
            btn:Enable()
            btn:SetScript("OnClick", function()
                local hasClipboard = ADT.DyeClipboard and ADT.DyeClipboard._savedColors and #ADT.DyeClipboard._savedColors > 0
                if not hasClipboard then
                    if ADT.Notify then ADT.Notify(ADT.L["No dye copied"] or "未复制任何染色", "error") end
                    return
                end
                if cat.onSaveClick then
                    cat.onSaveClick()
                    C_Timer.After(0.05, function()
                        local mf = ADT.DockUI.GetMainFrame()
                        if mf then mf:ShowDyePresetsCategory(categoryKey) end
                    end)
                end
            end)
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + saveBtnH,
        offsetX = offsetX,
    }
    offsetY = offsetY + saveBtnH + 8
    
    -- 预设列表或空提示
    if #list == 0 then
        n = n + 1
        local emptyTop = offsetY + (Def.EmptyStateTopGap or 0)
        local emptyBottom = emptyTop + Def.ButtonSize
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                local text = cat.emptyText or ADT.L["No dye presets"] or "暂无染色预设"
                local firstLine = text:match("^([^\n]*)") or text
                obj:SetText(firstLine)
                SetTextColor(obj.Label, Def.TextColorDisabled)
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Hide() end
                obj.Label:SetJustifyH("LEFT")
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = emptyTop,
            bottom = emptyBottom,
            offsetX = offsetX,
        }
    else
        for i, preset in ipairs(list) do
            n = n + 1
            local top = offsetY
            local bottom = offsetY + buttonHeight + buttonGap
            local capIndex, capCat, capPreset = i, cat, preset
            content[n] = {
                dataIndex = n,
                templateKey = "DyePresetItem",
                setupFunc = function(obj)
                    obj:SetPresetData(capIndex, capPreset, capCat)
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                top = top,
                bottom = bottom,
                offsetX = offsetX,
            }
            offsetY = bottom
        end
    end
    
    mainFrame.ModuleTab.ScrollView:SetContent(content, false)
    if mainFrame.UpdateAutoWidth then mainFrame:UpdateAutoWidth() end
    return true
end

-- ============================================================================
-- 注册页面
-- ============================================================================

ADT.DockPages:Register("dyePresetList", PageDyePresets)
ADT.DockPages.PageDyePresets = PageDyePresets
