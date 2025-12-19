-- Housing_AxisSelect.lua
-- ADT 专家模式：快速选择旋转轴（X/Y/Z）
-- 原理：切换子模式重置轴到默认Y，再调用 SelectNextRotationAxis() 指定次数

local ADDON_NAME, ADT = ...
if not ADT or not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local L = ADT and ADT.L or {}

local AxisSelect = {}
ADT.AxisSelect = AxisSelect

-- 轴对应的切换次数（重置后默认为 X）
-- 顺序：X→Y→Z→X
local AxisSwitchCount = {
    X = 0,  -- 默认轴，无需切换
    Y = 1,  -- 1次
    Z = 2,  -- 2次
}

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
    hud:SetSize(50, 110)  -- 宽度 50, 高度容纳 3 个按钮 + 间距
    hud:SetPoint("LEFT", UIParent, "CENTER", 300, 0)  -- 屏幕中心偏右
    hud:SetFrameStrata("MEDIUM")
    hud:SetFrameLevel(50)
    
    -- 按钮配置（从上到下：X → Y → Z）
    local buttonConfig = {
        { axis = "X", label = "X", order = 1 },
        { axis = "Y", label = "Y", order = 2 },
        { axis = "Z", label = "Z", order = 3 },
    }
    
    local buttonWidth = 40
    local buttonHeight = 32
    local buttonSpacing = 4
    
    hud.Buttons = {}
    
    for _, cfg in ipairs(buttonConfig) do
        local btn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
        btn:SetSize(buttonWidth, buttonHeight)
        btn:SetText(cfg.label)
        
        -- 垂直排列
        local yOffset = -((cfg.order - 1) * (buttonHeight + buttonSpacing))
        btn:SetPoint("TOP", hud, "TOP", 0, yOffset)
        
        -- 点击事件
        btn.axis = cfg.axis
        btn:SetScript("OnClick", function(self)
            AxisSelect:SelectAxis(self.axis)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        
        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local axisName = L["Axis " .. self.axis] or (self.axis .. " " .. (L["Axis"] or "Axis"))
            GameTooltip:SetText(axisName, 1, 1, 1)
            GameTooltip:AddLine(L["Click to select rotation axis"] or "Click to select rotation axis", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        hud.Buttons[cfg.axis] = btn
    end
    
    AxisHUD = hud
    return hud
end

-- 更新 HUD 显隐
local function UpdateHUDVisibility()
    if not AxisHUD then return end
    
    local show = false
    if IsExpertMode() then
        if IsRotateSubmode() then
            if HasDecorSelected() then
                show = true
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

if ADT and ADT.DebugPrint then
    ADT.DebugPrint("[AxisSelect] 模块已加载")
end
