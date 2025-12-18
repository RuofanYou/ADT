-- Page_Recent.lua
-- 最近放置页面

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding

local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

local PageRecent = {}

function PageRecent:Render(mainFrame, categoryKey)
    categoryKey = categoryKey or "History"
    
    if not (mainFrame.ModuleTab and mainFrame.ModuleTab.ScrollView) then
        mainFrame.__pendingTabKey = categoryKey
        return false
    end
    local cat = CommandDock:GetCategoryByKey(categoryKey)
    if not cat then return false end
    
    mainFrame.currentDecorCategory = categoryKey
    mainFrame.currentSettingsCategory = nil
    mainFrame.currentAboutCategory = nil
    mainFrame.currentDyePresetsCategory = nil
    if ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end
    
    local list = cat.getListData and cat.getListData() or {}
    local content = {}
    local n = 0
    local buttonHeight = 36
    local offsetY = Def.ButtonSize
    local buttonGap = 2
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
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + Def.ButtonSize,
        offsetX = offsetX,
    }
    offsetY = offsetY + Def.ButtonSize
    
    if #list == 0 then
        n = n + 1
        content[n] = {
            dataIndex = n,
            templateKey = "Header",
            setupFunc = function(obj)
                local text = cat.emptyText or ADT.L["List Is Empty"]
                obj:SetText(text:match("^([^\n]*)") or text)
                SetTextColor(obj.Label, Def.TextColorDisabled)
                if obj.Left then obj.Left:Hide() end
                if obj.Right then obj.Right:Hide() end
                if obj.Divider then obj.Divider:Hide() end
                obj.Label:SetJustifyH("LEFT")
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = offsetY,
            bottom = offsetY + Def.ButtonSize,
            offsetX = offsetX,
        }
    else
        for i, item in ipairs(list) do
            n = n + 1
            local top = offsetY
            local bottom = offsetY + buttonHeight + buttonGap
            local capCat, capItem = cat, item
            content[n] = {
                dataIndex = n,
                templateKey = "DecorItem",
                setupFunc = function(obj)
                    obj:SetData(capItem, capCat)
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

ADT.DockPages:Register("History", PageRecent)
ADT.DockPages.PageRecent = PageRecent
