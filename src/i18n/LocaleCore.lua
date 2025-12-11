-- LocaleCore.lua：ADT 本地化管理（运行时切换）
local ADDON_NAME, ADT = ...
ADT = ADT or {}
ADT.Locales = ADT.Locales or {}
ADT.L = ADT.L or {}

-- ADT 支持的官方语言列表（单一权威，顺序即 UI 展示顺序）
ADT.SupportedLocales = {
    "enUS",
    "zhCN",
    "zhTW",
    "deDE",
    "frFR",
    "esES",
    "esMX",
    "itIT",
    "koKR",
    "ptBR",
    "ruRU",
}

-- 应用指定语言到 ADT.L
-- 规则：先填充 enUS 基线，再用目标语言覆写已有键
function ADT.ApplyLocale(localeKey)
    local base = ADT.Locales.enUS
    if type(base) ~= "table" then base = {} end

    wipe(ADT.L)
    for k, v in pairs(base) do
        ADT.L[k] = v
    end

    local actualKey = "enUS"
    if localeKey and localeKey ~= "enUS" then
        local override = ADT.Locales[localeKey]
        if type(override) == "table" then
            for k, v in pairs(override) do
                if v ~= nil then
                    ADT.L[k] = v
                end
            end
            actualKey = localeKey
        end
    end

    ADT.CurrentLocale = actualKey
end

-- 获取当前应使用的语言
function ADT.GetActiveLocale()
    -- 优先使用用户设置（nil=自动）
    local userLang = _G.ADT_DB and _G.ADT_DB.SelectedLanguage
    if userLang and ADT.Locales[userLang] then
        return userLang
    end
    -- 否则使用客户端语言
    local clientLang = GetLocale()
    if ADT.Locales[clientLang] then
        return clientLang
    end
    -- 默认英文
    return "enUS"
end

local function InitLocale()
    local locale = ADT.GetActiveLocale()
    ADT.ApplyLocale(locale)
end

-- 立即初始化
InitLocale()
