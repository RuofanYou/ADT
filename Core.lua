local ADDON_NAME, ADT = ...

-- 本地化表
ADT = ADT or {}
ADT.L = ADT.L or {}

-- 默认配置（单一权威）
local DEFAULTS = {
    EnableDupe = true,
    -- 是否启用 T 重置默认属性（专家模式下重置当前子模式）
    EnableResetT = true,
    -- 是否启用 Ctrl+T 全部重置
    EnableResetAll = true,
    -- 是否启用 L 锁定/解锁 悬停装饰
    EnableLock = true,
    -- 1: Ctrl, 2: Alt, 3: Ctrl+D（默认，释放 Alt）
    DuplicateKey = 3,
    -- 记住控制中心上次选中的分类（'Housing'/'Clipboard'/'History'/...）
    LastCategoryKey = nil,
    -- 悬停高亮（3D场景中高亮当前悬停的装饰物）
    EnableHoverHighlight = true,
    -- 放置历史记录
    PlacementHistory = {},
    -- 额外剪切板（持久化，可视化列表）
    ExtraClipboard = {},
    -- 调试开关：仅当开启时才向聊天框 print
    DebugEnabled = false,
    -- UI 位置持久化：历史弹窗
    HistoryPopupPos = nil,
    -- UI 位置持久化：控制中心主面板
    SettingsPanelPos = nil,
    -- UI 尺寸持久化：控制中心主面板（w/h）
    SettingsPanelSize = nil,
    -- 语言选择（nil=跟随客户端）
    SelectedLanguage = nil,
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
    -- 一次性迁移：旧版本默认是 Alt（2），改为 Ctrl+D（3）
    if _G.ADT_DB and _G.ADT_DB.DuplicateKey == 2 then
        _G.ADT_DB.DuplicateKey = 3
    end
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

-- Frame 位置保存/恢复（单一权威）
function ADT.SaveFramePosition(dbKey, frame)
    if not (dbKey and frame and frame.GetPoint) then return end
    local point, relTo, relPoint, xOfs, yOfs = frame:GetPoint(1)
    if not point then return end
    local relName = relTo and relTo:GetName() or "UIParent"
    ADT.SetDBValue(dbKey, { point = point, rel = relName, relPoint = relPoint or point, x = xOfs or 0, y = yOfs or 0 })
end

function ADT.RestoreFramePosition(dbKey, frame, fallback)
    if not (dbKey and frame and frame.SetPoint) then return end
    local pos = ADT.GetDBValue(dbKey)
    frame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        local rel = _G[pos.rel or "UIParent"] or UIParent
        frame:SetPoint(pos.point, rel, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        if type(fallback) == "function" then
            fallback(frame)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
end

-- Frame 尺寸保存/恢复（单一权威，独立于位置）
function ADT.SaveFrameSize(dbKey, frame)
    if not (dbKey and frame and frame.GetWidth) then return end
    local w, h = math.floor(frame:GetWidth() + 0.5), math.floor(frame:GetHeight() + 0.5)
    if w and h and w > 0 and h > 0 then
        ADT.SetDBValue(dbKey, { w = w, h = h })
    end
end

function ADT.RestoreFrameSize(dbKey, frame)
    if not (dbKey and frame and frame.SetSize) then return end
    local sz = ADT.GetDBValue(dbKey)
    if type(sz) == "table" and (sz.w and sz.h) then
        frame:SetSize(sz.w, sz.h)
    end
end

-- 调试打印（仅在 DebugEnabled 时输出到聊天框）
function ADT.IsDebugEnabled()
    return ADT.GetDBBool("DebugEnabled")
end

function ADT.DebugPrint(msg)
    if ADT.IsDebugEnabled() then
        print("ADT:", msg)
    end
end

-- 顶部美观提示（暴雪风格），带简单节流
do
    local lastMsg, lastT = nil, 0
    local function canShow(msg)
        local now = GetTime and GetTime() or 0
        if msg == lastMsg and (now - lastT) < 0.6 then
            return false
        end
        lastMsg, lastT = msg, now
        return true
    end

    local function AcquireNoticeFrame()
        local parent = (HouseEditorFrame and HouseEditorFrame:IsShown()) and HouseEditorFrame or UIParent
        local strata = (parent == HouseEditorFrame) and "TOOLTIP" or "FULLSCREEN_DIALOG"
        if ADT.NoticeFrame and ADT.NoticeFrame.SetParent then
            local f = ADT.NoticeFrame
            f:SetParent(parent)
            f:ClearAllPoints()
            f:SetPoint("TOP", parent, "TOP", 0, -120)
            f:SetFrameStrata(strata)
            local base = (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
            pcall(f.SetFrameLevel, f, base + 1000)
            f:SetToplevel(true)
            return f
        end
        local f = CreateFrame("ScrollingMessageFrame", "ADT_NoticeFrame", parent)
        f:SetSize(1024, 64)
        f:SetPoint("TOP", parent, "TOP", 0, -120)
        f:SetFrameStrata(strata)
        local base = (parent.GetFrameLevel and parent:GetFrameLevel()) or 0
        pcall(f.SetFrameLevel, f, base + 1000)
        f:SetToplevel(true)
        f:SetJustifyH("CENTER")
        if GameFontHighlightLarge then f:SetFontObject(GameFontHighlightLarge)
        elseif GameFontNormalLarge then f:SetFontObject(GameFontNormalLarge) end
        f:SetShadowOffset(1, -1)
        f:SetFading(true)
        f:SetFadeDuration(0.5)
        f:SetTimeVisible(2.0)
        f:SetMaxLines(3)
        f:EnableMouse(false)
        ADT.NoticeFrame = f
        return f
    end

    -- kind: 'success' | 'error' | 'info'
    function ADT.Notify(msg, kind)
        if not msg or msg == "" then return end
        if not canShow(msg) then return end

        local color
        if kind == 'error' then
            local c = ChatTypeInfo and ChatTypeInfo.ERROR_MESSAGE
            color = c and { r = c.r, g = c.g, b = c.b } or { r = 1.0, g = 0.25, b = 0.25 }
        else
            -- 暴雪黄色信息
            local c = _G.YELLOW_FONT_COLOR or (ChatTypeInfo and ChatTypeInfo.SYSTEM)
            local r, g, b = 1, 0.82, 0
            if c then
                if c.r then r = c.r; g = c.g; b = c.b
                elseif c.GetRGB then r, g, b = c:GetRGB() end
            end
            color = { r = r, g = g, b = b }
        end

        local frame = AcquireNoticeFrame()
        if frame and frame.AddMessage then
            frame:AddMessage(tostring(msg), color.r, color.g, color.b)
            return
        end
        -- 兜底：在调试模式才打印
        ADT.DebugPrint(msg)
    end
end

-- 获取当前重复热键名
function ADT.GetDuplicateKeyName()
    -- 为兼容旧字段名，仍保留此函数，但返回用于 UI 显示的“按键文本”。
    local index = ADT.GetDBValue("DuplicateKey") or 3
    if index == 3 then
        return (CTRL_KEY_TEXT and (CTRL_KEY_TEXT.."+D")) or "CTRL+D"
    elseif index == 1 then
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
        -- 在 SavedVariables 就位后，依据用户设置重新应用语言（确保持久化生效）
        if ADT.ApplyLocale and ADT.GetActiveLocale then
            ADT.ApplyLocale(ADT.GetActiveLocale())
        end
        RegisterSettingsCategory()
        if ADT.Housing and ADT.Housing.LoadSettings then
            ADT.Housing:LoadSettings()
        end
        -- 若控制中心已构建，刷新一次分类与条目（避免语言切换后残留旧文案）
        if ADT.ControlCenter and ADT.ControlCenter.SettingsPanel then
            local Main = ADT.ControlCenter.SettingsPanel
            -- 仅当 UI 已构建完毕（存在对象池与滚动容器）时刷新；否则等待真正打开面板时再刷新。
            local canRefresh = Main.ModuleTab and Main.ModuleTab.ScrollView
            if canRefresh then
                if Main.RefreshCategoryList then Main:RefreshCategoryList() end
                if Main.RefreshFeatureList then Main:RefreshFeatureList() end
            end
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
