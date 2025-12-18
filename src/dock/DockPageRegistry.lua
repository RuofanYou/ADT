-- DockPageRegistry.lua
-- 页面注册表：管理所有 Dock 页面模块的注册与渲染

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

-- ============================================================================
-- 页面注册表
-- ============================================================================

ADT.DockPages = ADT.DockPages or {}

-- 注册页面
-- @param key 页面键名（与分类 key 对应）
-- @param page 页面模块（需实现 Render, OnShow, OnHide）
function ADT.DockPages:Register(key, page)
    if not key or not page then return end
    self[key] = page
    if ADT.DebugPrint then
        ADT.DebugPrint("[DockPages] Registered page: " .. tostring(key))
    end
end

-- 获取页面
function ADT.DockPages:Get(key)
    return self[key]
end

-- 检查页面是否已注册
function ADT.DockPages:Has(key)
    return self[key] ~= nil
end
