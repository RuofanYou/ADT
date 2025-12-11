-- Housing_IncrementRotate.lua
-- 功能：递增旋转 - 批量放置时每个物品自动累加旋转角度
-- 设计：极简 - 直接使用已验证的 RotateSelectedByDegrees API

local ADDON_NAME, ADT = ...
ADT = ADT or {}

local M = CreateFrame("Frame")
ADT.IncrementRotate = M

local L = ADT.L or {}

-- ===========================
-- 状态（每次 /reload 重置）
-- ===========================
M.count = 0
M.incrementDeg = 90
M.isEnabled = false

-- ===========================
-- 工具函数
-- ===========================

local function D(msg)
    if ADT and ADT.DebugPrint then ADT.DebugPrint(msg) end
end

local function LoadSettings()
    M.isEnabled = (ADT.GetDBValue and ADT.GetDBValue("EnableIncrementRotate")) == true
    M.incrementDeg = tonumber(ADT.GetDBValue and ADT.GetDBValue("IncrementRotateDegrees")) or 90
    D(string.format("[IncRot] Settings: enabled=%s, deg=%.3f", tostring(M.isEnabled), M.incrementDeg))
end

-- ===========================
-- 事件处理
-- ===========================

M:RegisterEvent("HOUSING_DECOR_PLACE_SUCCESS")

M:SetScript("OnEvent", function(self, event, ...)
    if event ~= "HOUSING_DECOR_PLACE_SUCCESS" then return end
    if not M.isEnabled then return end
    
    if IsControlKeyDown() then
        M.count = M.count + 1
        D(string.format("[IncRot] PlaceSuccess: count=%d", M.count))
    else
        M.count = 0
    end
end)

-- ===========================
-- 钩子：开始放置时执行旋转
-- ===========================

local function OnStartPlacing()
    if not M.isEnabled then return end
    if not IsControlKeyDown() then
        M.count = 0
        return
    end
    
    -- 目标：第 n 件（从 0 开始）相对于“默认朝向”的绝对角度应为 n*step。
    -- 12.0 行为调整后，新开一次放置通常不会继承上一件的朝向；
    -- 因此这里直接旋转到“绝对角度”，避免出现始终只转固定 90° 的问题。
    -- 为减少旋转次数，按 0~359 归一化。
    local deg = 0
    if M.count > 0 then
        deg = (M.count * M.incrementDeg) % 360
    end
    
    D(string.format("[IncRot] StartPlacing: count=%d, deg=%.3f (increment mode)", M.count, deg))
    
    if deg == 0 then return end
    
    -- 直接调用已验证的 API（延迟确保物品就绪）
    C_Timer.After(0.1, function()
        if not IsControlKeyDown() then return end
        if ADT.RotateHotkey and ADT.RotateHotkey.RotateSelectedByDegrees then
            D(string.format("[IncRot] Execute: deg=%.3f", deg))
            ADT.RotateHotkey:RotateSelectedByDegrees(deg)
        end
    end)
end

if C_HousingBasicMode then
    if C_HousingBasicMode.StartPlacingNewDecor then
        hooksecurefunc(C_HousingBasicMode, "StartPlacingNewDecor", OnStartPlacing)
    end
    if C_HousingBasicMode.StartPlacingPreviewDecor then
        hooksecurefunc(C_HousingBasicMode, "StartPlacingPreviewDecor", OnStartPlacing)
    end
end

-- ===========================
-- 公开 API
-- ===========================

function M:Reset()
    M.count = 0
    if ADT.Notify then
        ADT.Notify(L["Increment accumulator reset to 0"], 'success')
    end
    D("[IncRot] Reset")
end

function M:LoadSettings()
    LoadSettings()
end

-- ===========================
-- 设置注册
-- ===========================

local function RegisterSettings()
    if not (ADT.CommandDock and ADT.CommandDock.AddModule) then return end
    local CC = ADT.CommandDock

    CC:AddModule({
        name = L["Enable Increment Rotate"],
        dbKey = 'EnableIncrementRotate',
        type = 'toggle',
        description = L["Enable Increment Rotate tooltip"],
        categoryKeys = { 'AutoRotate' },
        uiOrder = 10,
    })

    -- 解析自定义角度（容忍空白、度符、全角/中文标点等）
    local function ParseAngleInput(s)
        s = tostring(s or "")
        -- 去空白与常见单位
        s = s:gsub("[°度]", "")
        s = s:gsub("%s+", "")
        -- 全角数字/符号 → 半角
        local map = {
            ['０']='0',['１']='1',['２']='2',['３']='3',['４']='4',
            ['５']='5',['６']='6',['７']='7',['８']='8',['９']='9',
            ['．']='.', ['。']='.', ['，']='.', ['、']='.',
            ['－']='-', ['—']='-', ['–']='-', ['＋']='+',
        }
        s = s:gsub(".", function(ch) return map[ch] or ch end)
        -- 仅保留 数字 / 正负号 / 小数点
        s = s:gsub("[^%d%+%-%.]", "")
        -- 归一化多个小数点：仅保留首个
        local firstDot
        s = s:gsub("%.", function(dot)
            if firstDot then return "" else firstDot = true return dot end
        end)
        -- 去掉孤立的符号
        if s == "" or s == "." or s == "+" or s == "-" then return nil end
        local v = tonumber(s)
        return v
    end

    -- 自定义角度输入弹窗（KISS：基于 StaticPopup，避免引入额外 UI）
    local function OpenCustomAngleDialog()
        local DLG_KEY = "ADT_INPUT_INCREMENT_ROTATE_DEG"
        if not StaticPopupDialogs[DLG_KEY] then
            StaticPopupDialogs[DLG_KEY] = {
                text = L["Enter increment angle"],
                button1 = OKAY,
                button2 = CANCEL,
                hasEditBox = true,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnShow = function(self)
                    local current = tonumber(ADT.GetDBValue and ADT.GetDBValue('IncrementRotateDegrees')) or 90
                    local eb = self.GetEditBox and self:GetEditBox() or self.editBox
                    if eb then
                        local s = tostring(current)
                        eb:SetText(s)
                        if eb.HighlightText then eb:HighlightText() end
                        if eb.SetAutoFocus then eb:SetAutoFocus(true) end
                    end
                    D("[IncRot][Popup] OnShow")
                end,
                EditBoxOnEnterPressed = function(self)
                    local parent = self:GetParent()
                    StaticPopup_OnClick(parent, 1)
                end,
                OnAccept = function(self)
                    local eb = self.GetEditBox and self:GetEditBox() or self.editBox
                    local txt = eb and (eb.GetText and eb:GetText() or "") or ""
                    D("[IncRot][Popup] OnAccept raw=" .. tostring(txt))
                    local v = ParseAngleInput(txt)
                    D("[IncRot][Popup] parsed=" .. tostring(v))
                    if not v then
                        if ADT and ADT.Notify then ADT.Notify(L["Invalid number"], 'error') end
                        return
                    end
                    ADT.SetDBValue('IncrementRotateDegrees', v, true)
                    LoadSettings()
                    if ADT and ADT.CommandDock and ADT.CommandDock.SettingsPanel and ADT.CommandDock.SettingsPanel.UpdateSettingsEntries then
                        ADT.CommandDock.SettingsPanel:UpdateSettingsEntries()
                    end
                    if ADT and ADT.Notify then
                        ADT.Notify(string.format(L["Increment angle set to"].." %s°", tostring(v)), 'success')
                    end
                end,
            }
        end
        StaticPopup_Show(DLG_KEY)
    end

    local function valueToText(v)
        local num = tonumber(v)
        if not num then return tostring(v or '') end
        local s = string.format("%.3f", num):gsub("0+$", ""):gsub("%.$", "")
        return s .. "°"
    end

    CC:AddModule({
        name = L["Increment Angle"],
        dbKey = 'IncrementRotateDegrees',
        type = 'dropdown',
        options = {
            { value = 15,  text = "15°" },
            { value = 30,  text = "30°" },
            { value = 45,  text = "45°" },
            { value = 60,  text = "60°" },
            { value = 90,  text = "90°" },
            { value = 120, text = "120°" },
            { value = 180, text = "180°" },
            { action = 'button', text = L["Custom..."], onClick = OpenCustomAngleDialog },
        },
        valueToText = valueToText, -- 当当前值不在预设项中时，用于标签展示
        description = L["Increment Angle tooltip"],
        categoryKeys = { 'AutoRotate' },
        uiOrder = 11,
    })
end

-- ===========================
-- 初始化
-- ===========================

if ADT.Settings and ADT.Settings.On then
    ADT.Settings.On("EnableIncrementRotate", LoadSettings)
    ADT.Settings.On("IncrementRotateDegrees", LoadSettings)
end

C_Timer.After(0.5, function()
    M.count = 0
    LoadSettings()
    RegisterSettings()
    D("[IncRot] Initialized")
end)

if ADT.CommandDock and ADT.CommandDock.RegisterModuleProvider then
    ADT.CommandDock:RegisterModuleProvider(RegisterSettings)
end

-- ===========================
-- 斜杠命令
-- ===========================

SLASH_ADTRESETROT1 = "/adtresetrot"
SLASH_ADTRESETROT2 = "/重置旋转"
SlashCmdList["ADTRESETROT"] = function()
    if ADT.IncrementRotate then
        ADT.IncrementRotate:Reset()
    end
end
