local ADDON_NAME, ADT = ...

-- 本地化表
ADT = ADT or {}
ADT.L = ADT.L or {}

-- 默认配置（单一权威）
local DEFAULTS = {
    EnableDupe = true,
    -- 1: Ctrl, 2: Alt
    DuplicateKey = 2,
}

local function CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

local function GetDB()
    _G.ADT_DB = CopyDefaults(_G.ADT_DB, DEFAULTS)
    return _G.ADT_DB
end

function ADT.GetDBBool(key)
    local db = GetDB()
    return not not db[key]
end

function ADT.GetDBValue(key)
    local db = GetDB()
    return db[key]
end

function ADT.SetDBValue(key, value)
    local db = GetDB()
    db[key] = value
end

function ADT.FlipDBBool(key)
    ADT.SetDBValue(key, not ADT.GetDBBool(key))
end

-- 获取当前重复热键名
function ADT.GetDuplicateKeyName()
    local index = ADT.GetDBValue("DuplicateKey") or 2
    if index == 1 then
        return CTRL_KEY_TEXT or "CTRL"
    else
        return ALT_KEY_TEXT or "ALT"
    end
end

-- Settings API：在暴雪设置中嵌入我们的独立 GUI（仿 Plumber 注册方式）
local function RegisterSettingsCategory()
    local BlizzardPanel = CreateFrame("Frame", "ADTSettingsContainer", UIParent)
    BlizzardPanel:Hide()

    local category = Settings.RegisterCanvasLayoutCategory(BlizzardPanel, "AdvancedDecorationTools")
    Settings.RegisterAddOnCategory(category)

    BlizzardPanel:SetScript("OnShow", function(self)
        local Main = ADT and ADT.ControlCenter and ADT.ControlCenter.SettingsPanel
        if Main and Main.ShowUI then
            Main:Hide()
            Main:SetParent(self)
            Main:ClearAllPoints()
            Main:SetPoint("TOPLEFT", self, "TOPLEFT", -10, 6)
            Main:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
            Main:ShowUI("blizzard")
        end
    end)

    BlizzardPanel:SetScript("OnHide", function(self)
        local Main = ADT and ADT.ControlCenter and ADT.ControlCenter.SettingsPanel
        if Main then Main:Hide() end
    end)

    ADT.SettingsCategory = category
end

-- 初始化
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, addonName)
    if addonName == ADDON_NAME then
        GetDB() -- 初始化 SavedVariables
        RegisterSettingsCategory()
        if ADT.Housing and ADT.Housing.LoadSettings then
            ADT.Housing:LoadSettings()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
