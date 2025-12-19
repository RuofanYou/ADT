-- Page_AutoRotate.lua
-- 高级旋转页面

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding
local L = ADT.L or {}

local PageAutoRotate = {}

-- 角度选项（学习专家设置样式，用下拉菜单）
local PULSE_DEGREES_OPTIONS = {
    { value = 5,  text = "5°"  },
    { value = 15, text = "15°" },
    { value = 45, text = "45°" },
    { value = 90, text = "90°" },
}

-- 创建“脉冲角度”下拉行
local pulseDegreesFrame = nil
local function EnsurePulseDegreesFrame(parent, width)
    if pulseDegreesFrame then
        pulseDegreesFrame:SetParent(parent)
        pulseDegreesFrame:ClearAllPoints()
        pulseDegreesFrame:SetWidth(width)
        if pulseDegreesFrame.dropdown and pulseDegreesFrame.dropdown.UpdateLabel then
            pulseDegreesFrame.dropdown:UpdateLabel()
        end
        return pulseDegreesFrame
    end

    pulseDegreesFrame = CreateFrame("Frame", nil, parent)
    pulseDegreesFrame:SetSize(width, 36)

    local offsetX = GetRightPadding()
    local innerWidth = width - offsetX * 2

    local function getValue()
        return tonumber(ADT.GetDBValue and ADT.GetDBValue("ExpertPulseDegrees")) or 45
    end
    local function setValue(v)
        if ADT.SetDBValue then
            ADT.SetDBValue("ExpertPulseDegrees", v, true)
        end
        print(string.format("|cFF00FF00[ADT]|r " .. (L["Pulse Degrees Set"] or "Pulse degrees set to %d°"), v))
        if ADT.UI and ADT.UI.PlaySoundCue then ADT.UI.PlaySoundCue('ui.checkbox.on') end
    end

    local row = ADT.DockUI.CreateDropdownRow(
        pulseDegreesFrame, innerWidth,
        (L["Expert Pulse Degrees"] or "Pulse Rotation Amount:") ,
        PULSE_DEGREES_OPTIONS,
        getValue,
        setValue,
        { labelOffsetX = offsetX, buttonOffsetX = offsetX + 120, buttonWidth = 80 }
    )
    row:SetPoint("TOPLEFT", pulseDegreesFrame, "TOPLEFT", 0, -8)
    if row.UpdateLabel then row:UpdateLabel() end
    pulseDegreesFrame.dropdown = row

    return pulseDegreesFrame
end

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
    local panelWidth = mainFrame.centerButtonWidth or 300

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

    -- 注册自定义模板（如果尚未注册）
    local sv = mainFrame.ModuleTab.ScrollView
    if sv and sv._templates and not sv._templates["PulseDegreesPanel"] then
        sv:AddTemplate("PulseDegreesPanel", function()
            local panel = EnsurePulseDegreesFrame(sv, panelWidth)
            return panel
        end)
    end

    -- 添加脉冲角度选择面板
    n = n + 1
    content[n] = {
        dataIndex = n,
        templateKey = "PulseDegreesPanel",
        setupFunc = function(obj)
            if obj.Refresh then obj:Refresh() end
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + 36,
        offsetX = offsetX,
    }
    offsetY = offsetY + 36

    mainFrame.firstModuleData = (cat.modules or {})[1]
    mainFrame.ModuleTab.ScrollView:SetContent(content, false)
    if mainFrame.UpdateAutoWidth then mainFrame:UpdateAutoWidth() end
    
    return true
end

ADT.DockPages:Register("AutoRotate", PageAutoRotate)
ADT.DockPages.PageAutoRotate = PageAutoRotate
