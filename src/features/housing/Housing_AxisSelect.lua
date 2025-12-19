-- Housing_AxisSelect.lua
-- ADT 专家模式：快速选择旋转轴（X/Y/Z）+ 增量旋转控制
-- 原理：切换子模式重置轴到默认X，再调用 SelectNextRotationAxis() 指定次数

local ADDON_NAME, ADT = ...
if not ADT or not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local L = ADT and ADT.L or {}

local AxisSelect = {}
ADT.AxisSelect = AxisSelect

-- 功能开关状态
AxisSelect.isEnabled = true

-- 加载设置
local function LoadSettings()
    AxisSelect.isEnabled = (ADT.GetDBValue and ADT.GetDBValue("EnablePulseRotate")) ~= false  -- 默认开启
    if ADT and ADT.DebugPrint then
        ADT.DebugPrint(string.format("[AxisSelect] LoadSettings: enabled=%s", tostring(AxisSelect.isEnabled)))
    end
end

-- 轴对应的切换次数（重置后默认为 X）
-- 顺序：X→Y→Z→X
local AxisSwitchCount = {
    X = 0,  -- 默认轴，无需切换
    Y = 1,  -- 1次
    Z = 2,  -- 2次
}

-- 脉冲旋转配置
-- 基准：0.1秒 = 5°，所以 1秒 = 45°
-- DB 中存储的是目标角度（5/15/45/90），需要转换为脉冲时间
local function GetPulseDuration()
    local degrees = ADT.GetDBValue and ADT.GetDBValue("ExpertPulseDegrees") or 45
    -- 转换：角度 / 45 = 秒数
    return degrees / 45
end

-- 提供给 tooltip 使用的角度获取函数
function AxisSelect:GetPulseDegrees()
    return ADT.GetDBValue and ADT.GetDBValue("ExpertPulseDegrees") or 45
end

--------------------------------------------------------------------------------
-- 核心逻辑
--------------------------------------------------------------------------------

-- 检查是否在专家模式
local function IsExpertMode()
    if not C_HouseEditor or not C_HouseEditor.GetActiveHouseEditorMode then return false end
    return C_HouseEditor.GetActiveHouseEditorMode() == Enum.HouseEditorMode.ExpertDecor
end

-- 检查是否在旋转子模式
local function IsRotateSubmode()
    if not C_HousingExpertMode or not C_HousingExpertMode.GetPrecisionSubmode then return false end
    return C_HousingExpertMode.GetPrecisionSubmode() == Enum.HousingPrecisionSubmode.Rotate
end

-- 检查是否有选中的装饰
local function HasDecorSelected()
    if not C_HousingExpertMode or not C_HousingExpertMode.IsDecorSelected then return false end
    return C_HousingExpertMode.IsDecorSelected()
end

-- 核心：重置轴并切换到目标轴
function AxisSelect:SelectAxis(axis)
    local count = AxisSwitchCount[axis]
    if not count then return end
    
    -- 条件1：必须在专家模式
    if not IsExpertMode() then return end
    
    -- 条件2：必须有选中的装饰
    if not HasDecorSelected() then return end
    
    -- 步骤1：切换到 Translate 再切回 Rotate（重置轴）
    C_HousingExpertMode.SetPrecisionSubmode(Enum.HousingPrecisionSubmode.Translate)
    C_HousingExpertMode.SetPrecisionSubmode(Enum.HousingPrecisionSubmode.Rotate)
    
    -- 步骤2：调用 SelectNextRotationAxis 指定次数
    for i = 1, count do
        C_HousingExpertMode.SelectNextRotationAxis()
    end
    
    if ADT and ADT.DebugPrint then
        ADT.DebugPrint(string.format("[AxisSelect] 选择 %s 轴（切换 %d 次）", axis, count))
    end
end

-- 快捷方法
function AxisSelect:SelectAxisX() self:SelectAxis("X") end
function AxisSelect:SelectAxisY() self:SelectAxis("Y") end
function AxisSelect:SelectAxisZ() self:SelectAxis("Z") end

--------------------------------------------------------------------------------
-- 脉冲旋转功能
--------------------------------------------------------------------------------

-- 脉冲锁定状态（防止多轴脉冲互相干扰）
local isPulsing = false

-- 更新所有按钮的启用/禁用状态
local function UpdateButtonsEnabled()
    if not AxisHUD then return end
    
    for axis, btn in pairs(AxisHUD.Buttons or {}) do
        btn:SetEnabled(not isPulsing)
    end
    for axis, btns in pairs(AxisHUD.RotateButtons or {}) do
        if btns.left then btns.left:SetEnabled(not isPulsing) end
        if btns.right then btns.right:SetEnabled(not isPulsing) end
    end
end

-- 执行一次脉冲旋转
-- direction: "left" 或 "right"
-- axis: "X", "Y", "Z"（先切换到该轴再旋转）
function AxisSelect:PulseRotate(axis, direction)
    -- 条件检查
    if not IsExpertMode() then return end
    if not HasDecorSelected() then return end
    
    -- 如果正在脉冲中，忽略请求
    if isPulsing then
        if ADT and ADT.DebugPrint then
            ADT.DebugPrint("[AxisSelect] 忽略请求：正在脉冲中")
        end
        return
    end
    
    -- 设置脉冲锁定
    isPulsing = true
    UpdateButtonsEnabled()
    
    -- 先切换到目标轴
    self:SelectAxis(axis)
    
    -- 确定旋转方向
    local incrementType
    if direction == "left" then
        incrementType = Enum.HousingIncrementType.RotateLeft
    else
        incrementType = Enum.HousingIncrementType.RotateRight
    end
    
    -- 开始旋转
    C_HousingExpertMode.SetPrecisionIncrementingActive(incrementType, true)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    
    -- 脉冲结束后停止旋转并解锁
    local pulseDuration = GetPulseDuration()
    C_Timer.After(pulseDuration, function()
        C_HousingExpertMode.SetPrecisionIncrementingActive(incrementType, false)
        -- 解除脉冲锁定
        isPulsing = false
        UpdateButtonsEnabled()
    end)
    
    if ADT and ADT.DebugPrint then
        ADT.DebugPrint(string.format("[AxisSelect] 脉冲旋转: %s 轴 %s 方向 %.2f秒", axis, direction, pulseDuration))
    end
end


--------------------------------------------------------------------------------
-- HUD UI
--------------------------------------------------------------------------------

local AxisHUD

local function CreateAxisHUD()
    -- 等待暴雪插件加载
    local expertFrame = HouseEditorFrame and HouseEditorFrame.ExpertDecorModeFrame
    if not expertFrame then return end
    if AxisHUD then return AxisHUD end
    
    -- 创建主容器（挂载到专家模式框架下）
    local hud = CreateFrame("Frame", "ADT_AxisSelectHUD", expertFrame)
    hud:SetSize(120, 120)  -- 扩大宽度以容纳 +/- 按钮
    hud:SetPoint("LEFT", UIParent, "CENTER", 300, 0)  -- 屏幕中心偏右
    hud:SetFrameStrata("MEDIUM")
    hud:SetFrameLevel(50)
    
    -- 按钮配置（从上到下：X → Y → Z）
    local buttonConfig = {
        { axis = "X", label = "X", order = 1 },
        { axis = "Y", label = "Y", order = 2 },
        { axis = "Z", label = "Z", order = 3 },
    }
    
    local axisButtonSize = 32
    local smallButtonSize = 28
    local buttonSpacing = 6
    local rowHeight = axisButtonSize + buttonSpacing
    
    hud.Buttons = {}
    hud.RotateButtons = {}
    
    -- 创建自定义样式按钮的辅助函数
    -- isSmall: 是否是小按钮（-/+ 按钮）
    local function CreateStyledButton(parent, size, label, isSmall)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(size, size)
        
        -- 背景（正常状态）
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetAtlas("common-dropdown-c-button-open")
        
        -- 悬停高亮（叠加在背景上，不替换）
        btn.hover = btn:CreateTexture(nil, "ARTWORK")
        btn.hover:SetAllPoints()
        btn.hover:SetAtlas("common-dropdown-c-button-hover-1")
        btn.hover:Hide()
        
        -- 按下状态
        btn.pushed = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        btn.pushed:SetAllPoints()
        btn.pushed:SetAtlas("common-dropdown-c-button-pressed-1")
        btn.pushed:Hide()
        
        -- 文本标签
        -- XYZ 轴按钮用更小字体；-+ 用标准字体确保可见
        local fontName = isSmall and "GameFontNormal" or "GameFontHighlightSmall"
        btn.text = btn:CreateFontString(nil, "OVERLAY", fontName)
        btn.text:SetPoint("CENTER", 0, 0)
        btn.text:SetText(label)
        btn.text:SetTextColor(1, 0.82, 0)  -- 金色
        
        -- 悬停效果
        btn:SetScript("OnEnter", function(self)
            self.hover:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self.hover:Hide()
        end)
        
        -- 按下/松开效果
        btn:SetScript("OnMouseDown", function(self)
            self.pushed:Show()
            self.hover:Hide()
            self.text:SetPoint("CENTER", 1, -1)  -- 文字偏移模拟按下
        end)
        btn:SetScript("OnMouseUp", function(self)
            self.pushed:Hide()
            self.text:SetPoint("CENTER", 0, 0)  -- 恢复文字位置
        end)
        
        -- 禁用状态处理
        btn:SetScript("OnDisable", function(self)
            self.text:SetTextColor(0.5, 0.5, 0.5)
            self.bg:SetDesaturated(true)
        end)
        btn:SetScript("OnEnable", function(self)
            self.text:SetTextColor(1, 0.82, 0)
            self.bg:SetDesaturated(false)
        end)
        
        return btn
    end
    
    for _, cfg in ipairs(buttonConfig) do
        local yOffset = -((cfg.order - 1) * rowHeight)
        
        -- 轴选择按钮（中间）
        local axisBtn = CreateStyledButton(hud, axisButtonSize, cfg.label)
        axisBtn:SetPoint("TOP", hud, "TOP", 0, yOffset)
        axisBtn.axis = cfg.axis
        axisBtn:SetScript("OnClick", function(self)
            -- 脉冲旋转期间禁止切换轴（与 +/- 按钮一致）
            if isPulsing then return end
            AxisSelect:SelectAxis(self.axis)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        axisBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Axis " .. self.axis] or (self.axis .. " Axis"), 1, 1, 1)
            GameTooltip:AddLine(L["Click to select rotation axis"] or "Click to select", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        axisBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        hud.Buttons[cfg.axis] = axisBtn
        
        -- 左旋转按钮（-）
        local leftBtn = CreateStyledButton(hud, smallButtonSize, "-", true)
        leftBtn:SetPoint("RIGHT", axisBtn, "LEFT", -4, 0)
        leftBtn.axis = cfg.axis
        leftBtn:SetScript("OnClick", function(self)
            AxisSelect:PulseRotate(self.axis, "left")
        end)
        leftBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Rotate Left"] or "Rotate Left", 1, 1, 1)
            GameTooltip:AddLine(string.format(L["Rotate %d degrees"] or "Rotate %d°", AxisSelect:GetPulseDegrees()), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        leftBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        
        -- 右旋转按钮（+）
        local rightBtn = CreateStyledButton(hud, smallButtonSize, "+", true)
        rightBtn:SetPoint("LEFT", axisBtn, "RIGHT", 4, 0)
        rightBtn.axis = cfg.axis
        rightBtn:SetScript("OnClick", function(self)
            AxisSelect:PulseRotate(self.axis, "right")
        end)
        rightBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Rotate Right"] or "Rotate Right", 1, 1, 1)
            GameTooltip:AddLine(string.format(L["Rotate %d degrees"] or "Rotate %d°", AxisSelect:GetPulseDegrees()), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        rightBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        
        hud.RotateButtons[cfg.axis] = { left = leftBtn, right = rightBtn }
    end
    
    AxisHUD = hud
    return hud
end


-- 更新 HUD 显隐
local function UpdateHUDVisibility()
    if not AxisHUD then return end
    
    local show = false
    -- 检查功能开关
    if AxisSelect.isEnabled then
        if IsExpertMode() then
            if IsRotateSubmode() then
                if HasDecorSelected() then
                    show = true
                end
            end
        end
    end
    
    AxisHUD:SetShown(show)
end

--------------------------------------------------------------------------------
-- 事件监听
--------------------------------------------------------------------------------

local EL = CreateFrame("Frame")

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_HouseEditor" then
            CreateAxisHUD()
            UpdateHUDVisibility()
        end
    elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
        UpdateHUDVisibility()
    elseif event == "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED" then
        UpdateHUDVisibility()
    elseif event == "HOUSING_DECOR_PRECISION_SUBMODE_CHANGED" then
        UpdateHUDVisibility()
    end
end

EL:RegisterEvent("ADDON_LOADED")
EL:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
EL:RegisterEvent("HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED")
EL:RegisterEvent("HOUSING_DECOR_PRECISION_SUBMODE_CHANGED")
EL:SetScript("OnEvent", OnEvent)

-- 如果 Blizzard_HouseEditor 已加载，立即初始化
if C_AddOns.IsAddOnLoaded("Blizzard_HouseEditor") then
    CreateAxisHUD()
    UpdateHUDVisibility()
end

-- 提供命令行接口调整脉冲角度
SLASH_ADTPULSE1 = "/adtpulse"
SlashCmdList["ADTPULSE"] = function(msg)
    local degrees = tonumber(msg)
    if degrees and (degrees == 5 or degrees == 15 or degrees == 45 or degrees == 90) then
        if ADT.SetDBValue then
            ADT.SetDBValue("ExpertPulseDegrees", degrees)
            print(string.format("|cFF00FF00[ADT]|r 脉冲旋转角度已设置为 %d°", degrees))
        end
    else
        local current = ADT.GetDBValue and ADT.GetDBValue("ExpertPulseDegrees") or 45
        print("|cFF00FF00[ADT]|r 用法: /adtpulse <角度> (5/15/45/90)")
        print(string.format("|cFF00FF00[ADT]|r 当前脉冲角度: %d°", current))
    end
end

--------------------------------------------------------------------------------
-- 设置注册
--------------------------------------------------------------------------------

local function RegisterSettings()
    if not (ADT.CommandDock and ADT.CommandDock.AddModule) then return end
    local CC = ADT.CommandDock

    CC:AddModule({
        name = L["Enable Pulse Rotate"],
        dbKey = 'EnablePulseRotate',
        type = 'toggle',
        description = L["Enable Pulse Rotate tooltip"],
        categoryKeys = { 'AutoRotate' },
        uiOrder = 12,  -- 排在递增角度(11)之后，脉冲角度下拉菜单之前
    })
end

-- 订阅设置变化
if ADT.Settings and ADT.Settings.On then
    ADT.Settings.On("EnablePulseRotate", function()
        LoadSettings()
        UpdateHUDVisibility()
    end)
end

-- 延迟注册设置
C_Timer.After(0.5, function()
    LoadSettings()
    RegisterSettings()
end)

if ADT.CommandDock and ADT.CommandDock.RegisterModuleProvider then
    ADT.CommandDock:RegisterModuleProvider(RegisterSettings)
end

if ADT and ADT.DebugPrint then
    ADT.DebugPrint("[AxisSelect] 模块已加载")
end
