-- Page_ExpertSettings.lua
-- 专家模式设置页面：允许玩家可视化控制专家模式相关的 CVars
-- 手动创建控件，确保 CVar 真正生效

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local CommandDock = ADT.CommandDock
local Def = ADT.DockUI.Def
local GetRightPadding = ADT.DockUI.GetRightPadding
local L = ADT.L or {}

local PageExpertSettings = {}

-- CVar 配置
local CVARS = {
    SnapOnHold = {
        name = "housingExpertGizmos_SnapOnHold",
        default = 1,
    },
    RotationSnapDegrees = {
        name = "housingExpertGizmos_Rotation_SnapDegrees",
        default = 15,
    },
    ScaleSnap = {
        name = "housingExpertGizmos_Scale_Snap",
        default = 0.1,
    },
}

-- 获取 CVar 值
local function GetCVarNum(cvarName)
    local val = GetCVar(cvarName)
    return tonumber(val) or 0
end

-- 设置 CVar 值
local function SetCVarNum(cvarName, value)
    SetCVar(cvarName, value)
    if ADT.DebugPrint then
        ADT.DebugPrint(string.format("[ExpertSettings] SetCVar %s = %s", cvarName, tostring(value)))
    end
end

-- 专家设置面板容器（延迟创建）
local expertPanel = nil
local checkboxSnapOnHold = nil
local dropdownRotation = nil
local dropdownScale = nil

-- 刷新所有控件状态
local function RefreshControls()
    -- 复选框
    if checkboxSnapOnHold then
        local snapVal = GetCVarNum(CVARS.SnapOnHold.name)
        checkboxSnapOnHold:SetChecked(snapVal == 0)
    end
    
    -- 旋转下拉菜单
    if dropdownRotation and dropdownRotation.UpdateLabel then
        dropdownRotation:UpdateLabel()
    end
    
    -- 缩放下拉菜单
    if dropdownScale and dropdownScale.UpdateLabel then
        dropdownScale:UpdateLabel()
    end
end

-- 创建下拉菜单按钮
local function CreateDropdownButton(parent, width, label, options, getCVar, setCVar, cvarName)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 28)
    
    -- 标签
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", row, "LEFT", 0, 0)
    text:SetText(label)
    row.label = text
    
    -- 下拉按钮（使用游戏内置样式）
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(80, 22)
    btn:SetPoint("LEFT", row, "LEFT", 120, 0)
    
    -- 背景
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetAtlas("common-dropdown-c-button-open")
    
    -- 高亮
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    
    -- 当前值文本
    btn.valueText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.valueText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.valueText:SetTextColor(1, 0.82, 0)
    
    -- 箭头
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arrow:SetAtlas("common-dropdown-c-button-arrow-down")
    
    row.options = options
    row.getCVar = getCVar
    row.setCVar = setCVar
    row.cvarName = cvarName
    
    -- 更新显示
    function row:UpdateLabel()
        local current = self.getCVar()
        for _, opt in ipairs(self.options) do
            if math.abs((opt.value or 0) - (current or 0)) < 0.01 then
                btn.valueText:SetText(opt.text)
                return
            end
        end
        btn.valueText:SetText(tostring(current))
    end
    
    -- 点击展开下拉菜单
    btn:SetScript("OnClick", function()
        MenuUtil.CreateContextMenu(btn, function(owner, root)
            for _, opt in ipairs(options) do
                local function IsSelected()
                    return math.abs((getCVar() or 0) - (opt.value or 0)) < 0.01
                end
                local function SetSelected()
                    setCVar(opt.value)
                    row:UpdateLabel()
                    return MenuResponse.Close
                end
                root:CreateRadio(opt.text, IsSelected, SetSelected, opt.value)
            end
        end)
    end)
    
    return row
end

local function EnsureExpertPanel(parent, width)
    if expertPanel then
        expertPanel:SetParent(parent)
        expertPanel:ClearAllPoints()
        expertPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        expertPanel:SetWidth(width)
        RefreshControls()
        return expertPanel
    end
    
    expertPanel = CreateFrame("Frame", nil, parent)
    expertPanel:SetSize(width, 140)
    
    local offsetX = GetRightPadding()
    local innerWidth = width - offsetX * 2
    local rowHeight = 32
    local y = -8
    
    -- ==================== 行1：默认启用吸附（复选框） ====================
    local row1 = CreateFrame("Frame", nil, expertPanel)
    row1:SetSize(innerWidth, 28)
    row1:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    
    local cb = CreateFrame("CheckButton", nil, row1, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", row1, "LEFT", 0, 0)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        -- checked=true 表示"默认启用吸附"，对应 CVar=0
        -- checked=false 表示"默认不吸附"，对应 CVar=1
        SetCVarNum(CVARS.SnapOnHold.name, checked and 0 or 1)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        print("|cFF00FF00[ADT]|r " .. (L["Default Snap Enabled"] or "Default Snap Enabled") .. " = " .. (checked and "ON" or "OFF"))
    end)
    
    local cbLabel = row1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cbLabel:SetText(L["Default Snap Enabled"] or "Default Snap Enabled")
    
    checkboxSnapOnHold = cb
    y = y - rowHeight
    
    -- ==================== 行2：旋转精度（下拉菜单） ====================
    local rotOptions = {
        {value = 5, text = "5°"},
        {value = 10, text = "10°"},
        {value = 15, text = "15°"},
        {value = 30, text = "30°"},
        {value = 45, text = "45°"},
        {value = 90, text = "90°"},
    }
    dropdownRotation = CreateDropdownButton(
        expertPanel, innerWidth,
        (L["Rotation Snap Degrees"] or "Rotation Snap") .. ":",
        rotOptions,
        function() return GetCVarNum(CVARS.RotationSnapDegrees.name) end,
        function(val)
            SetCVarNum(CVARS.RotationSnapDegrees.name, val)
            print("|cFF00FF00[ADT]|r " .. (L["Rotation Snap Degrees"] or "Rotation Snap") .. " = " .. val .. "°")
        end,
        CVARS.RotationSnapDegrees.name
    )
    dropdownRotation:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    y = y - rowHeight
    
    -- ==================== 行3：缩放精度（下拉菜单） ====================
    local scaleOptions = {
        {value = 0.1, text = "10%"},
        {value = 0.2, text = "20%"},
        {value = 0.5, text = "50%"},
        {value = 1, text = "100%"},
    }
    dropdownScale = CreateDropdownButton(
        expertPanel, innerWidth,
        (L["Scale Snap"] or "Scale Snap") .. ":",
        scaleOptions,
        function() return GetCVarNum(CVARS.ScaleSnap.name) end,
        function(val)
            SetCVarNum(CVARS.ScaleSnap.name, val)
            print("|cFF00FF00[ADT]|r " .. (L["Scale Snap"] or "Scale Snap") .. " = " .. (val * 100) .. "%")
        end,
        CVARS.ScaleSnap.name
    )
    dropdownScale:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    y = y - rowHeight + 4
    
    -- ==================== 行4：恢复默认按钮 ====================
    local resetBtn = CreateFrame("Button", nil, expertPanel, "UIPanelButtonTemplate")
    resetBtn:SetSize(100, 26)
    resetBtn:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    resetBtn:SetText(L["Reset to Default"] or "Reset Default")
    resetBtn:SetScript("OnClick", function()
        SetCVarNum(CVARS.SnapOnHold.name, CVARS.SnapOnHold.default)
        SetCVarNum(CVARS.RotationSnapDegrees.name, CVARS.RotationSnapDegrees.default)
        SetCVarNum(CVARS.ScaleSnap.name, CVARS.ScaleSnap.default)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        print("|cFF00FF00[ADT]|r " .. (L["Expert Settings Reset"] or "Expert settings reset"))
        RefreshControls()
    end)
    
    return expertPanel
end

-- 页面渲染
function PageExpertSettings:Render(mainFrame, categoryKey)
    categoryKey = categoryKey or "ExpertSettings"
    
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
    local buttonHeight = Def.ButtonSize or 28
    local offsetY = buttonHeight
    local offsetX = GetRightPadding()
    local panelWidth = (mainFrame.centerButtonWidth or 300)

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

    -- 专用自定义面板
    n = n + 1
    content[n] = {
        dataIndex = n,
        templateKey = "ExpertSettingsPanel",
        setupFunc = function(obj)
            RefreshControls()
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + 130,
        offsetX = offsetX,
    }
    offsetY = offsetY + 130

    -- 注册自定义模板（如果尚未注册）
    local sv = mainFrame.ModuleTab.ScrollView
    if sv and sv._templates and not sv._templates["ExpertSettingsPanel"] then
        sv:AddTemplate("ExpertSettingsPanel", function()
            local panel = EnsureExpertPanel(sv, panelWidth)
            return panel
        end)
    end

    mainFrame.firstModuleData = nil
    mainFrame.ModuleTab.ScrollView:SetContent(content, false)
    if mainFrame.UpdateAutoWidth then mainFrame:UpdateAutoWidth() end
    
    return true
end

-- 注册页面
ADT.DockPages:Register("ExpertSettings", PageExpertSettings)
ADT.DockPages.PageExpertSettings = PageExpertSettings
