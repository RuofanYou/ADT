local ADDON_NAME, ADT = ...
ADT = ADT or {}

-- Slash：/adt 打开设置面板（自定义 ControlCenter 样式）
SLASH_ADT1 = "/adt"

-- 单一权威：切换主面板的逻辑集中在此处，供斜杠命令与快捷键复用
function ADT.ToggleMainUI()
    local Main = ADT and ADT.ControlCenter and ADT.ControlCenter.SettingsPanel
    if not Main then return end
    if Settings and ADT.SettingsCategory and SettingsPanel and SettingsPanel:IsShown() then
        Settings.OpenToCategory(ADT.SettingsCategory)
        return
    end
    if Main:IsShown() then
        Main:Hide()
    else
        -- 根据是否处于住宅编辑模式，选择更合适的父级与层级
        local parent, strata
        if HouseEditorFrame and HouseEditorFrame:IsShown() then
            parent, strata = HouseEditorFrame, "TOOLTIP"
        else
            parent, strata = UIParent, "DIALOG"
        end
        Main:ClearAllPoints()
        Main:SetParent(parent)
        if Main.SetFrameStrata then Main:SetFrameStrata(strata) end
        Main:SetPoint("CENTER")
        Main:ShowUI("standalone")
    end
end

SlashCmdList["ADT"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" or msg == "dbg" then
        if ADT and ADT.FlipDBBool and ADT.IsDebugEnabled and ADT.Notify then
            ADT.FlipDBBool("DebugEnabled")
            local state = ADT.IsDebugEnabled() and "开启" or "关闭"
            ADT.Notify("ADT 调试已"..state, ADT.IsDebugEnabled() and 'success' or 'info')
        end
        return
    end
    ADT.ToggleMainUI()
end

-- 当编辑模式开关时，自动把设置面板重挂到合适的父级，避免被编辑器遮挡
do
    local function IsOwnedByBlizzardSettings(main)
        local p = main and main.GetParent and main:GetParent()
        return p and (p == _G.ADTSettingsContainer or (p.GetName and p:GetName() == "ADTSettingsContainer"))
    end

    local function ReanchorSettingsPanel()
        local Main = ADT and ADT.ControlCenter and ADT.ControlCenter.SettingsPanel
        if not (Main and Main:IsShown()) then return end
        -- 如果当前在暴雪设置页中展示，则不干预
        if IsOwnedByBlizzardSettings(Main) then return end

        if HouseEditorFrame and HouseEditorFrame:IsShown() then
            if Main:GetParent() ~= HouseEditorFrame then
                Main:SetParent(HouseEditorFrame)
            end
            if Main.SetFrameStrata then Main:SetFrameStrata("TOOLTIP") end
        else
            if Main:GetParent() ~= UIParent then
                Main:SetParent(UIParent)
            end
            if Main.SetFrameStrata then Main:SetFrameStrata("DIALOG") end
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function()
        -- 下一帧处理，避免和暴雪自身的布局竞争
        C_Timer.After(0, ReanchorSettingsPanel)
    end)
end
