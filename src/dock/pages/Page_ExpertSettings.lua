-- Page_ExpertSettings.lua
-- 专家模式设置页面：允许玩家可视化控制专家模式相关的 CVars
-- 使用 ScrollView 的自定义模板机制，确保控件正确渲染

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
    -- 调试输出
    if ADT.DebugPrint then
        ADT.DebugPrint(string.format("[ExpertSettings] SetCVar %s = %s", cvarName, tostring(value)))
    end
end

-- 创建复选框设置行
local function CreateCheckboxRow(parent, width, label, tooltip, getValue, setValue)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 28)
    
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        setValue(checked)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    cb:SetScript("OnEnter", function(self)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.checkbox = cb
    
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    row.label = text
    
    row.Refresh = function(self)
        self.checkbox:SetChecked(getValue())
    end
    
    return row
end

-- 创建按钮组行
local function CreateButtonGroupRow(parent, width, label, tooltip, options, getValue, setValue)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 28)
    
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", row, "LEFT", 0, 0)
    text:SetText(label .. ":")
    row.label = text
    
    local buttons = {}
    local labelWidth = 120
    local btnWidth = 42
    local btnGap = 4
    
    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(btnWidth, 22)
        btn:SetPoint("LEFT", row, "LEFT", labelWidth + (i-1) * (btnWidth + btnGap), 0)
        btn:SetText(opt.text)
        btn.value = opt.value
        btn:SetScript("OnClick", function(self)
            setValue(self.value)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            row:Refresh()
        end)
        btn:SetScript("OnEnter", function(self)
            if tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(label, 1, 1, 1)
                GameTooltip:AddLine(tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[#buttons + 1] = btn
    end
    row.buttons = buttons
    
    row.Refresh = function(self)
        local current = getValue()
        for _, btn in ipairs(self.buttons) do
            if btn.GetNormalTexture and btn:GetNormalTexture() then
                if math.abs((btn.value or 0) - (current or 0)) < 0.01 then
                    btn:GetNormalTexture():SetVertexColor(0.2, 0.8, 0.2)
                else
                    btn:GetNormalTexture():SetVertexColor(1, 1, 1)
                end
            end
        end
    end
    
    return row
end

-- 专家设置面板容器（延迟创建）
local expertPanel = nil
local expertRows = {}

local function EnsureExpertPanel(parent, width)
    if expertPanel then
        expertPanel:SetParent(parent)
        expertPanel:ClearAllPoints()
        expertPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        expertPanel:SetWidth(width)
        return expertPanel
    end
    
    expertPanel = CreateFrame("Frame", nil, parent)
    expertPanel:SetSize(width, 140)
    
    local offsetX = GetRightPadding()
    local innerWidth = width - offsetX * 2
    local rowHeight = 32
    local y = -8
    
    -- 行1：默认启用吸附
    local row1 = CreateCheckboxRow(
        expertPanel, innerWidth,
        L["Default Snap Enabled"] or "Default Snap Enabled",
        L["Default Snap Enabled tooltip"] or "ON: Snap by default\nOFF: No snap by default (Blizzard default)",
        function() return GetCVarNum(CVARS.SnapOnHold.name) == 0 end,
        function(checked)
            SetCVarNum(CVARS.SnapOnHold.name, checked and 0 or 1)
            print("|cFF00FF00[ADT]|r " .. (L["Default Snap Enabled"] or "Default Snap") .. " = " .. (checked and "ON" or "OFF"))
        end
    )
    row1:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    expertRows[1] = row1
    y = y - rowHeight
    
    -- 行2：旋转精度
    local rotOptions = {
        {value = 5, text = "5°"},
        {value = 10, text = "10°"},
        {value = 15, text = "15°"},
        {value = 45, text = "45°"},
        {value = 90, text = "90°"},
    }
    local row2 = CreateButtonGroupRow(
        expertPanel, innerWidth,
        L["Rotation Snap Degrees"] or "Rotation Snap",
        L["Rotation Snap Degrees tooltip"] or "Rotation snap degrees",
        rotOptions,
        function() return GetCVarNum(CVARS.RotationSnapDegrees.name) end,
        function(val)
            SetCVarNum(CVARS.RotationSnapDegrees.name, val)
            print("|cFF00FF00[ADT]|r " .. (L["Rotation Snap Degrees"] or "Rotation Snap") .. " = " .. val .. "°")
        end
    )
    row2:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    expertRows[2] = row2
    y = y - rowHeight
    
    -- 行3：缩放精度
    local scaleOptions = {
        {value = 0.1, text = "10%"},
        {value = 0.2, text = "20%"},
        {value = 0.5, text = "50%"},
        {value = 1, text = "100%"},
    }
    local row3 = CreateButtonGroupRow(
        expertPanel, innerWidth,
        L["Scale Snap"] or "Scale Snap",
        L["Scale Snap tooltip"] or "Scale snap percent",
        scaleOptions,
        function() return GetCVarNum(CVARS.ScaleSnap.name) end,
        function(val)
            SetCVarNum(CVARS.ScaleSnap.name, val)
            print("|cFF00FF00[ADT]|r " .. (L["Scale Snap"] or "Scale Snap") .. " = " .. (val * 100) .. "%")
        end
    )
    row3:SetPoint("TOPLEFT", expertPanel, "TOPLEFT", offsetX, y)
    expertRows[3] = row3
    y = y - rowHeight - 8
    
    -- 行4：恢复默认按钮
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
        -- 刷新
        for _, r in ipairs(expertRows) do
            if r.Refresh then r:Refresh() end
        end
    end)
    expertRows[4] = resetBtn
    
    return expertPanel
end

-- 刷新所有控件状态
function PageExpertSettings:RefreshControls()
    for _, r in ipairs(expertRows) do
        if r.Refresh then r:Refresh() end
    end
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
            -- 刷新控件状态
            PageExpertSettings:RefreshControls()
        end,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        top = offsetY,
        bottom = offsetY + 140,
        offsetX = offsetX,
    }
    offsetY = offsetY + 140

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
