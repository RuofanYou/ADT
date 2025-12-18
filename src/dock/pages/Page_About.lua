-- Page_About.lua
-- 关于页面渲染器（插件信息）

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding

-- ============================================================================
-- 页面渲染器
-- ============================================================================

local PageAbout = {}

function PageAbout:Render(mainFrame, categoryKey)
    if not (mainFrame.ModuleTab and mainFrame.ModuleTab.ScrollView) then
        mainFrame.__pendingTabKey = categoryKey
        return false
    end
    local cat = CommandDock:GetCategoryByKey(categoryKey)
    if not cat or cat.categoryType ~= 'about' then return false end
    
    -- 更新当前分类状态
    mainFrame.currentDecorCategory = nil
    mainFrame.currentAboutCategory = categoryKey
    mainFrame.currentSettingsCategory = nil
    mainFrame.currentDyePresetsCategory = nil
    if ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
    
    local content = {}
    local n = 0
    local buttonHeight = Def.ButtonSize
    local fromOffsetY = Def.ButtonSize
    local offsetY = fromOffsetY
    local offsetX = GetRightPadding()
    
    -- 添加标题
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
    offsetY = offsetY + Def.ButtonSize * 2
    
    -- 添加信息文本
    if cat.getInfoText then
        local infoText = cat.getInfoText()
        for line in infoText:gmatch("[^\n]+") do
            n = n + 1
            content[n] = {
                dataIndex = n,
                templateKey = "Header",
                setupFunc = function(obj)
                    obj:SetText(line)
                    obj.Label:SetJustifyH("LEFT")
                    if obj.Left then obj.Left:Hide() end
                    if obj.Right then obj.Right:Hide() end
                    if obj.Divider then obj.Divider:Hide() end
                    if obj.SetLeftPadding then obj:SetLeftPadding(GetRightPadding() + (Def.AboutTextExtraLeft or 0)) end
                end,
                point = "TOPLEFT",
                relativePoint = "TOPLEFT",
                top = offsetY,
                bottom = offsetY + buttonHeight,
                offsetX = offsetX,
            }
            offsetY = offsetY + buttonHeight
        end
    end
    
    mainFrame.ModuleTab.ScrollView:SetContent(content, false)
    if mainFrame.UpdateAutoWidth then mainFrame:UpdateAutoWidth() end
    return true
end

-- ============================================================================
-- 注册页面
-- ============================================================================

ADT.DockPages:Register("about", PageAbout)
ADT.DockPages.PageAbout = PageAbout
