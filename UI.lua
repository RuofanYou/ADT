local ADDON_NAME, ADT = ...
ADT = ADT or {}

-- Slash：/adt 打开设置面板（自定义 ControlCenter 样式）
SLASH_ADT1 = "/adt"
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
    local Main = ADT and ADT.ControlCenter and ADT.ControlCenter.SettingsPanel
    if not Main then return end
    if Settings and ADT.SettingsCategory and SettingsPanel and SettingsPanel:IsShown() then
        Settings.OpenToCategory(ADT.SettingsCategory)
        return
    end
    if Main:IsShown() then
        Main:Hide()
    else
        Main:ClearAllPoints()
        Main:SetParent(UIParent)
        Main:SetPoint("CENTER")
        Main:ShowUI("standalone")
    end
end
