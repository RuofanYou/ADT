-- Keybinds.lua
-- ADT 自定义快捷键核心模块
-- 使用 SetOverrideBindingClick 实现动态快捷键绑定


local ADDON_NAME, ADT = ...

-- ===========================
-- 模块初始化
-- ===========================
local M = {}
ADT.Keybinds = M

-- ===========================
-- 默认快捷键配置
-- ===========================
local DEFAULTS = {
    Duplicate    = "CTRL-D",     -- 复制放置
    Copy         = "CTRL-C",     -- 复制到剪切板
    Cut          = "CTRL-X",     -- 剪切
    Paste        = "CTRL-V",     -- 粘贴
    Store        = "CTRL-S",     -- 存入临时板
    Recall       = "CTRL-R",     -- 取出临时板
    Reset        = "T",          -- 重置变换
    ResetAll     = "CTRL-T",     -- 重置全部
    -- 根据玩家反馈：Q=顺时针(+90)，E=逆时针(-90)
    RotateCCW90  = "E",          -- 逆时针旋转90°（默认 E）
    RotateCW90   = "Q",          -- 顺时针旋转90°（默认 Q）
    -- 染料复制（自定义模式专用）
    DyeCopy      = "SHIFT-C",    -- 复制染料
    -- 快捷栏（Quickbar）默认键位
    Quickbar1    = "F1",
    Quickbar2    = "F2",
    Quickbar3    = "F3",
    Quickbar4    = "F4",
    Quickbar5    = "F5",
    Quickbar6    = "F6",
    Quickbar7    = "F7",
    Quickbar8    = "F8",
}

-- 动作定义（每个动作对应一个功能）
-- 注意：这是快捷键到功能的唯一权威映射
local ACTIONS = {
    Duplicate = {
        name = "重复",
        nameEN = "Duplicate",
        callback = function() if ADT.Housing and ADT.Housing.TryDuplicateItem then ADT.Housing:TryDuplicateItem() end end,
    },
    Copy = {
        name = "复制",
        nameEN = "Copy",
        callback = function() if ADT.Housing and ADT.Housing.Binding_Copy then ADT.Housing:Binding_Copy() end end,
    },
    Cut = {
        name = "剪切",
        nameEN = "Cut",
        callback = function() if ADT.Housing and ADT.Housing.Binding_Cut then ADT.Housing:Binding_Cut() end end,
    },
    Paste = {
        name = "粘贴",
        nameEN = "Paste",
        callback = function() if ADT.Housing and ADT.Housing.Binding_Paste then ADT.Housing:Binding_Paste() end end,
    },
    Store = {
        name = "存入临时板",
        nameEN = "Store",
        callback = function() if _G.ADT_Temp_StoreSelected then ADT_Temp_StoreSelected() end end,
    },
    Recall = {
        name = "取出临时板",
        nameEN = "Recall",
        callback = function() if _G.ADT_Temp_RecallTop then ADT_Temp_RecallTop() end end,
    },
    Reset = {
        name = "重置变换",
        nameEN = "Reset",
        callback = function() if ADT.Housing and ADT.Housing.ResetCurrentSubmode then ADT.Housing:ResetCurrentSubmode() end end,
    },
    ResetAll = {
        name = "重置全部",
        nameEN = "Reset All",
        callback = function() if ADT.Housing and ADT.Housing.ResetAllTransforms then ADT.Housing:ResetAllTransforms() end end,
    },
    RotateCCW90 = {
        name = "逆时针旋转90°",
        nameEN = "Rotate CCW 90°",
        callback = function() if ADT.RotateHotkey and ADT.RotateHotkey.RotateSelectedByDegrees then ADT.RotateHotkey:RotateSelectedByDegrees(-90) end end,
    },
    RotateCW90 = {
        name = "顺时针旋转90°",
        nameEN = "Rotate CW 90°",
        callback = function() if ADT.RotateHotkey and ADT.RotateHotkey.RotateSelectedByDegrees then ADT.RotateHotkey:RotateSelectedByDegrees(90) end end,
    },
    -- 染料复制（自定义模式专用）
    DyeCopy = {
        name = "复制染料",
        nameEN = "Copy Dye",
        callback = function() if ADT.DyeClipboard and ADT.DyeClipboard.CopyFromHovered then ADT.DyeClipboard:CopyFromHovered() end end,
    },
    -- 快捷栏（Quickbar）槽位 1-8：回调统一委托给 Quickbar 模块
    Quickbar1 = {
        name = "快捷栏 1",
        nameEN = "Quickbar 1",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(1) end end,
    },
    Quickbar2 = {
        name = "快捷栏 2",
        nameEN = "Quickbar 2",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(2) end end,
    },
    Quickbar3 = {
        name = "快捷栏 3",
        nameEN = "Quickbar 3",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(3) end end,
    },
    Quickbar4 = {
        name = "快捷栏 4",
        nameEN = "Quickbar 4",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(4) end end,
    },
    Quickbar5 = {
        name = "快捷栏 5",
        nameEN = "Quickbar 5",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(5) end end,
    },
    Quickbar6 = {
        name = "快捷栏 6",
        nameEN = "Quickbar 6",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(6) end end,
    },
    Quickbar7 = {
        name = "快捷栏 7",
        nameEN = "Quickbar 7",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(7) end end,
    },
    Quickbar8 = {
        name = "快捷栏 8",
        nameEN = "Quickbar 8",
        callback = function() if ADT.Quickbar and ADT.Quickbar.OnQuickbarKeyPressed then ADT.Quickbar:OnQuickbarKeyPressed(8) end end,
    },
}

-- ===========================
-- 内部状态
-- ===========================
local ownerFrame = nil          -- 覆盖绑定的 owner frame
local buttons = {}              -- 每个 action 对应的隐藏按钮
local isBindingsActive = false  -- 当前是否激活绑定
local isInCombat = false        -- 是否在战斗中

-- ===========================
-- 工具函数
-- ===========================

-- 前置声明：为避免在函数定义之前被引用，先声明局部变量，后续用赋值方式定义
local EnsureOwnerFrame
local EnsureButton

-- 获取用户配置的快捷键
function M:GetKeybind(actionName)
    local db = ADT.GetDBValue and ADT.GetDBValue("Keybinds") or {}
    return db[actionName] or DEFAULTS[actionName] or ""
end

-- 获取某个动作当前“显示用”的按键文本（本地化后的友好格式）
-- 说明：统一入口，避免各处手写 GetKeybind+GetKeyDisplayName 的重复逻辑（单一权威）
function M:GetActionKeyDisplay(actionName)
    if not actionName or actionName == "" then return "" end
    local raw = self:GetKeybind(actionName)
    return self:GetKeyDisplayName(raw)
end

-- Quickbar 专用：按索引获取当前按键（原始/显示）
function M:GetQuickbarKey(index)
    if not index then return "" end
    return self:GetKeybind("Quickbar" .. tostring(index))
end

function M:GetQuickbarKeyDisplay(index)
    if not index then return "" end
    return self:GetActionKeyDisplay("Quickbar" .. tostring(index))
end

-- 设置用户配置的快捷键
function M:SetKeybind(actionName, key)
    if not ADT.SetDBValue then return end
    local db = ADT.GetDBValue("Keybinds") or {}
    db[actionName] = key or ""
    ADT.SetDBValue("Keybinds", db)
    
    -- 如果绑定已激活，必须清除所有绑定后重新注册（避免旧按键残留）
    if isBindingsActive then
        local owner = EnsureOwnerFrame()
        if owner then
            -- 先清除所有绑定（单一权威：清除所有再重新注册）
            ClearOverrideBindings(owner)
        end
        -- 重新注册所有绑定
        for name in pairs(ACTIONS) do
            self:RegisterBinding(name)
        end
        if ADT.DebugPrint then
            ADT.DebugPrint("[Keybinds] 快捷键已更新并重新注册全部:", actionName, "->", key or "")
        end
    end
    
    -- 通知 Housing 模块刷新覆盖绑定（固定绑定如 L、Q、E）
    if ADT.Housing and ADT.Housing.RefreshOverrides then
        ADT.Housing:RefreshOverrides()
    end
    -- 刷新 HoverHUD 键帽文本（单一权威：显示与绑定一致）
    if ADT.Housing and ADT.Housing.RefreshKeycaps then
        ADT.Housing:RefreshKeycaps()
    end
    -- 若存在快捷栏 UI，立即刷新其键帽文本
    if ADT.Quickbar and ADT.Quickbar.RefreshUI then
        ADT.Quickbar:RefreshUI()
    end
end

-- 获取动作的显示名称（使用本地化系统）
function M:GetActionDisplayName(actionName)
    local L = ADT.L or {}
    local key = "Keybind Action " .. actionName
    -- 优先使用本地化表中的翻译
    if L[key] and L[key] ~= key then
        return L[key]
    end
    -- 兜底：使用 ACTIONS 中的硬编码名称
    local action = ACTIONS[actionName]
    if not action then return actionName end
    local locale = ADT.CurrentLocale or (ADT.GetActiveLocale and ADT.GetActiveLocale()) or GetLocale()
    if locale == "zhCN" or locale == "zhTW" then
        return action.name
    end
    return action.nameEN
end

-- 获取按键的显示名称（本地化）
function M:GetKeyDisplayName(key)
    if not key or key == "" then return "" end
    -- 简单替换修饰键为本地化文本
    local display = key
    display = display:gsub("CTRL%-", (CTRL_KEY_TEXT or "Ctrl") .. "+")
    display = display:gsub("SHIFT%-", (SHIFT_KEY_TEXT or "Shift") .. "+")
    display = display:gsub("ALT%-", (ALT_KEY_TEXT or "Alt") .. "+")
    return display
end

-- 获取所有动作
function M:GetAllActions()
    -- 将 Quickbar 动作单独分组，避免被名称排序打散
    local normals, quickbars = {}, {}
    for name in pairs(ACTIONS) do
        local idx = string.match(name, '^Quickbar(%d+)$')
        if idx then
            table.insert(quickbars, { name = name, idx = tonumber(idx) })
        else
            table.insert(normals, { name = name })
        end
    end

    table.sort(normals, function(a, b) return a.name < b.name end)

    -- 规则：RotateCW90 在 RotateCCW90 前
    do
        local idxCW, idxCCW
        for i, v in ipairs(normals) do
            if v.name == 'RotateCW90' then idxCW = i end
            if v.name == 'RotateCCW90' then idxCCW = i end
        end
        if idxCW and idxCCW and idxCW > idxCCW then
            local cw = table.remove(normals, idxCW)
            if idxCW < idxCCW then idxCCW = idxCCW - 1 end
            table.insert(normals, idxCCW, cw)
        end
    end

    -- 规则：Store 紧邻 Recall 之上
    do
        local idxStore, idxRecall
        for i, v in ipairs(normals) do
            if v.name == 'Store' then idxStore = i end
            if v.name == 'Recall' then idxRecall = i end
        end
        if idxStore and idxRecall and idxStore ~= (idxRecall - 1) then
            local storeEntry = table.remove(normals, idxStore)
            if idxStore < idxRecall then idxRecall = idxRecall - 1 end
            table.insert(normals, idxRecall, storeEntry)
        end
    end

    table.sort(quickbars, function(a, b) return (a.idx or 0) < (b.idx or 0) end)

    local result = {}
    local function push(name)
        table.insert(result, {
            name = name,
            displayName = self:GetActionDisplayName(name),
            key = self:GetKeybind(name),
            keyDisplay = self:GetKeyDisplayName(self:GetKeybind(name)),
        })
    end
    for _, v in ipairs(normals) do push(v.name) end
    for _, v in ipairs(quickbars) do push(v.name) end
    return result
end

-- ===========================
-- 核心：绑定管理
-- ===========================

-- 创建 owner frame（一次性）
EnsureOwnerFrame = function()
    if ownerFrame then return ownerFrame end
    ownerFrame = CreateFrame("Frame", "ADT_KeybindsOwner", UIParent)
    ownerFrame:Hide()  -- 隐藏，不参与 UI
    return ownerFrame
end

-- 为指定动作创建隐藏按钮
EnsureButton = function(actionName)
    if buttons[actionName] then return buttons[actionName] end
    
    local action = ACTIONS[actionName]
    if not action or not action.callback then return nil end
    
    local btnName = "ADT_Keybind_" .. actionName
    local btn = CreateFrame("Button", btnName, UIParent, "SecureActionButtonTemplate")
    btn:SetAttribute("type", "click")
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:SetScript("OnClick", function(self, button, down)
        -- 仅在按下时触发
        if down then
            action.callback()
        end
    end)
    btn:Hide()  -- 隐藏
    
    buttons[actionName] = btn
    return btn
end

-- 注册单个绑定
function M:RegisterBinding(actionName)
    if isInCombat then return end  -- 战斗中不修改绑定
    -- 若为 Q/E 旋转并且用户关闭了"启用 Q/E 旋转"，则跳过注册
    if (actionName == 'RotateCCW90' or actionName == 'RotateCW90') then
        local en = ADT.GetDBValue and ADT.GetDBValue('EnableQERotate')
        if en == false then return end
    end
    -- 若为染料复制并且用户关闭了"启用染料复制"，则跳过注册
    if actionName == 'DyeCopy' then
        local en = ADT.GetDBValue and ADT.GetDBValue('EnableDyeCopy')
        if en == false then return end
    end

    local key = self:GetKeybind(actionName)
    if not key or key == "" then return end
    
    local owner = EnsureOwnerFrame()
    local btn = EnsureButton(actionName)
    if not btn then return end
    
    local btnName = btn:GetName()
    SetOverrideBindingClick(owner, true, key, btnName, "LeftButton")
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[Keybinds] 注册绑定:", actionName, "->", key)
    end
end

-- 取消单个绑定
function M:UnregisterBinding(actionName)
    if isInCombat then return end
    
    local key = self:GetKeybind(actionName)
    if not key or key == "" then return end
    
    local owner = EnsureOwnerFrame()
    if owner then
        -- 使用 SetOverrideBinding(owner, true, key, nil) 取消特定绑定
        SetOverrideBinding(owner, true, key, nil)
    end
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[Keybinds] 取消绑定:", actionName)
    end
end

-- 刷新单个绑定（取消后重新注册）
function M:RefreshBinding(actionName)
    self:UnregisterBinding(actionName)
    self:RegisterBinding(actionName)
end

-- 激活所有绑定（进入 Housing 编辑模式时调用）
function M:ActivateAll()
    if isBindingsActive then return end
    if isInCombat then return end
    
    EnsureOwnerFrame()
    
    for actionName in pairs(ACTIONS) do
        self:RegisterBinding(actionName)
    end
    
    isBindingsActive = true
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[Keybinds] 所有快捷键已激活")
    end
end

-- 停用所有绑定（离开 Housing 编辑模式时调用）
function M:DeactivateAll()
    if not isBindingsActive then return end
    if isInCombat then return end
    
    local owner = EnsureOwnerFrame()
    if owner then
        ClearOverrideBindings(owner)
    end
    
    isBindingsActive = false
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[Keybinds] 所有快捷键已停用")
    end
end

-- 获取默认值
function M:GetDefault(actionName)
    return DEFAULTS[actionName] or ""
end

-- 恢复所有默认
function M:ResetAllToDefaults()
    if not ADT.SetDBValue then return end
    local db = {}
    for name, key in pairs(DEFAULTS) do
        db[name] = key
    end
    ADT.SetDBValue("Keybinds", db)
    -- 刷新绑定
    if isBindingsActive then
        self:DeactivateAll()
        self:ActivateAll()
    end
    -- 键帽文本也需要同步刷新
    if ADT.Housing and ADT.Housing.RefreshKeycaps then
        ADT.Housing:RefreshKeycaps()
    end
    -- 同步刷新快捷栏 UI 的键帽文本
    if ADT.Quickbar and ADT.Quickbar.RefreshUI then
        ADT.Quickbar:RefreshUI()
    end
end

-- ===========================
-- 事件监听
-- ===========================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- 进入战斗
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- 离开战斗
eventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        isInCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        isInCombat = false
        -- 如果之前在编辑模式，重新激活绑定
        if C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() then
            M:ActivateAll()
        end
    elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
        local mode = ...
        if mode and mode ~= 0 then
            -- 进入某个编辑模式
            M:ActivateAll()
        else
            -- 离开编辑模式
            M:DeactivateAll()
        end
    end
end)

-- ===========================
-- 初始化
-- ===========================
local function OnAddonLoaded()
    -- 确保 Keybinds 配置存在
    if ADT.GetDBValue and not ADT.GetDBValue("Keybinds") then
        if ADT.SetDBValue then
            local db = {}
            for name, key in pairs(DEFAULTS) do
                db[name] = key
            end
            ADT.SetDBValue("Keybinds", db)
        end
    end
    -- 清理已废弃字段：移除旧版“快速缩放”快捷键，避免出现在配置中（单一权威）
    if ADT.GetDBValue and ADT.SetDBValue then
        local db = ADT.GetDBValue("Keybinds") or {}
        if db.QuickScale ~= nil then
            db.QuickScale = nil
            ADT.SetDBValue("Keybinds", db)
        end
    end
    
    -- 如果已在编辑模式，立即激活
    if C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() then
        M:ActivateAll()
    end
    -- 初始进入时尝试刷新一次键帽文本（若 UI 已创建）
    if ADT.Housing and ADT.Housing.RefreshKeycaps then
        ADT.Housing:RefreshKeycaps()
    end
end

-- 延迟初始化（确保 DB 已加载）
C_Timer.After(0.5, OnAddonLoaded)

-- 调试提示
if ADT.DebugPrint then
    ADT.DebugPrint("[Keybinds] 模块已加载")
end

-- 订阅设置变化：当“启用 Q/E 旋转”被关闭/开启时，注销/注册相关绑定
if ADT and ADT.Settings and ADT.Settings.On then
    ADT.Settings.On('EnableQERotate', function(enabled)
        if not isBindingsActive then return end
        if enabled == false then
            M:UnregisterBinding('RotateCW90')
            M:UnregisterBinding('RotateCCW90')
        else
            M:RegisterBinding('RotateCW90')
            M:RegisterBinding('RotateCCW90')
        end
    end)
    -- 订阅设置变化：当"启用染料复制"被关闭/开启时，注销/注册相关绑定
    ADT.Settings.On('EnableDyeCopy', function(enabled)
        if not isBindingsActive then return end
        if enabled == false then
            M:UnregisterBinding('DyeCopy')
        else
            M:RegisterBinding('DyeCopy')
        end
    end)
end
