-- Keybinds.lua
-- ADT 自定义快捷键核心模块
-- 使用 SetOverrideBindingClick 实现动态快捷键绑定
-- 参考自 JST 插件的 UpdateFocusBindingClick 实现模式

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
    RotateCCW90  = "",           -- 逆时针旋转90°（无默认）
    RotateCW90   = "",           -- 顺时针旋转90°（无默认）
    QuickScale   = "SHIFT-S",    -- 快速缩放到200%
}

-- 动作定义（每个动作对应一个功能）
-- 注意：这是快捷键到功能的唯一权威映射
local ACTIONS = {
    Duplicate = {
        name = "复制放置",
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
    QuickScale = {
        name = "快速缩放200%",
        nameEN = "Quick Scale 200%",
        callback = function() if ADT.AutoScale and ADT.AutoScale.QuickScale then ADT.AutoScale:QuickScale() end end,
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
end

-- 获取动作的显示名称
function M:GetActionDisplayName(actionName)
    local action = ACTIONS[actionName]
    if not action then return actionName end
    -- 根据游戏语言返回
    local locale = GetLocale()
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
    local result = {}
    for name, info in pairs(ACTIONS) do
        table.insert(result, {
            name = name,
            displayName = self:GetActionDisplayName(name),
            key = self:GetKeybind(name),
            keyDisplay = self:GetKeyDisplayName(self:GetKeybind(name)),
        })
    end
    -- 按类别排序（可选）
    table.sort(result, function(a, b) return a.name < b.name end)
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
    
    -- 如果已在编辑模式，立即激活
    if C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() then
        M:ActivateAll()
    end
end

-- 延迟初始化（确保 DB 已加载）
C_Timer.After(0.5, OnAddonLoaded)

-- 调试提示
if ADT.DebugPrint then
    ADT.DebugPrint("[Keybinds] 模块已加载")
end
