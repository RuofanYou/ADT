-- Page_AutoRotate.lua
-- 自动旋转页面

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding

local PageAutoRotate = {}

function PageAutoRotate:Render(mainFrame, categoryKey)
    categoryKey = categoryKey or "AutoRotate"
    
    if not (mainFrame.ModuleTab and mainFrame.ModuleTab.ScrollView) then
        mainFrame.__pendingTabKey = categoryKey
        return false
    end
    local cat = CommandDock:GetCategoryByKey(categoryKey)
    if not cat then return false end

    mainFrame.currentSettingsCategory = categoryKey
    mainFrame.currentDecorCategory = nil
    mainFrame.currentAboutCategory = nil
    mainFrame.currentDyePresetsCategory = nil
    if ADT.SetDBValue then ADT.SetDBValue('LastCategoryKey', categoryKey) end

    local content = {}
    local n = 0
    local buttonHeight = Def.ButtonSize
    local offsetY = Def.ButtonSize
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
        bottom = offsetY + buttonHeight,
        offsetX = offsetX,
    }
    offsetY = offsetY + buttonHeight

    -- 分类内条目
    for _, data in ipairs(cat.modules or {}) do
        n = n + 1
        local top = offsetY
        local bottom = offsetY + buttonHeight
        content[n] = {
            dataIndex = n,
            templateKey = "Entry",
            setupFunc = function(obj)
                obj.parentDBKey = nil
                obj:SetData(data)
            end,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            top = top,
            bottom = bottom,
            offsetX = offsetX,
        }
        offsetY = bottom

        if data.subOptions then
            for _, v in ipairs(data.subOptions) do
                n = n + 1
                top = offsetY
                bottom = offsetY + buttonHeight
                content[n] = {
                    dataIndex = n,
                    templateKey = "Entry",
                    setupFunc = function(obj)
                        obj.parentDBKey = data.dbKey
                        obj:SetData(v)
                    end,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    top = top,
                    bottom = bottom,
                    offsetX = offsetX + 0.5*Def.ButtonSize,
                }
                offsetY = bottom
            end
        end
    end

    mainFrame.firstModuleData = (cat.modules or {})[1]
    mainFrame.ModuleTab.ScrollView:SetContent(content, false)
    if mainFrame.UpdateAutoWidth then mainFrame:UpdateAutoWidth() end
    
    return true
end

ADT.DockPages:Register("AutoRotate", PageAutoRotate)
ADT.DockPages.PageAutoRotate = PageAutoRotate
