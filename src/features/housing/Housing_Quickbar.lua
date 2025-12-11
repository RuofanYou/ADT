-- Housing_Quickbar.lua
-- 功能：快捷栏 - 快速放置常用 Decor
-- 设计：F1-F8 键位，抓取时按键绑定，未抓取时按键调用
-- 持久化：数据存储在 ADT_DB.Quickbar（SavedVariables）

local ADDON_NAME, ADT = ...
ADT = ADT or {}

local L = ADT.L or {}

-- ===========================
-- 常量
-- ===========================

local SLOT_KEYS = { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8" }
local NUM_SLOTS = #SLOT_KEYS

-- ===========================
-- 模块
-- ===========================

local M = CreateFrame("Frame")
ADT.Quickbar = M

M.slots = {}  -- 运行时槽位数据缓存
-- 说明：F1-F8 的按键绑定已统一迁移到 ADT.Keybinds 模块
-- 这里不再自建隐藏按钮与覆盖绑定，仅保留交互逻辑与 UI。
M.uiFrame = nil

-- ===========================
-- 工具函数
-- ===========================

local function D(msg)
    if ADT and ADT.DebugPrint then ADT.DebugPrint(msg) end
end

local function Notify(msg, typ)
    if ADT and ADT.Notify then ADT.Notify(msg, typ or 'info') end
end

-- 检测是否在住宅编辑器中
local function IsEditorActive()
    return C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
end

-- 前置声明：供上方函数体内调用，避免加载期未赋值
local GetDecorInfoByRecordID

-- 检测是否正在放置/抓取物品（多种检测方式）
local function IsPlacingDecor()
    -- 方式1：正在放置新装饰
    if C_HousingBasicMode and C_HousingBasicMode.IsPlacingNewDecor and C_HousingBasicMode.IsPlacingNewDecor() then
        return true
    end
    -- 方式2：有选中的装饰
    if C_HousingBasicMode and C_HousingBasicMode.IsDecorSelected and C_HousingBasicMode.IsDecorSelected() then
        return true
    end
    if C_HousingExpertMode and C_HousingExpertMode.IsDecorSelected and C_HousingExpertMode.IsDecorSelected() then
        return true
    end
    -- 方式3：检查当前放置状态
    if C_HousingBasicMode and C_HousingBasicMode.HasCurrentPlacement and C_HousingBasicMode.HasCurrentPlacement() then
        return true
    end
    return false
end

-- 更细粒度状态：是否“正在放置新装饰”与“是否已选中地面装饰”（用于决定调用 Cancel/Remove）
local function IsPlacingNew()
    return C_HousingBasicMode and C_HousingBasicMode.IsPlacingNewDecor and C_HousingBasicMode.IsPlacingNewDecor()
end

local function IsAnyDecorSelected()
    -- 优先使用全局态（更可靠，官方事件/UI均以此为准）
    if C_HousingDecor and C_HousingDecor.IsDecorSelected and C_HousingDecor.IsDecorSelected() then
        return true
    end
    -- 兼容回退：两种模式均检查一次
    local selBasic  = C_HousingBasicMode  and C_HousingBasicMode.IsDecorSelected  and C_HousingBasicMode.IsDecorSelected()
    local selExpert = C_HousingExpertMode and C_HousingExpertMode.IsDecorSelected and C_HousingExpertMode.IsDecorSelected()
    return not not (selBasic or selExpert)
end

-- 获取当前抓取物品的 recordID 和其他信息
local function GetCurrentDecorInfo()
    -- 情况A：地面“已选中”的装饰（优先，权威）
    do
        local info
        -- 优先使用全局态
        if C_HousingDecor and C_HousingDecor.GetSelectedDecorInfo then
            info = C_HousingDecor.GetSelectedDecorInfo()
        end
        -- 回退到模式态
        if (not info or not info.decorID) and C_HousingBasicMode and C_HousingBasicMode.GetSelectedDecorInfo then
            info = C_HousingBasicMode.GetSelectedDecorInfo()
        end
        if (not info or not info.decorID) and C_HousingExpertMode and C_HousingExpertMode.GetSelectedDecorInfo then
            info = C_HousingExpertMode.GetSelectedDecorInfo()
        end
        if info then
            local icon = info.iconTexture or info.iconAtlas or info.icon or info.iconID
            if info.decorID then
                D(string.format("[Quickbar] GetSelectedDecorInfo: decorID=%s, name=%s, icon=%s", tostring(info.decorID), tostring(info.name), tostring(icon)))
                return info.decorID, info.name, icon
            end
        end
    end

    -- 情况B：正在放置的新装饰（来自 Closet/预览）。依赖 PaintMode 捕获到的 recordID。
    if IsPlacingNew() and ADT and ADT.PaintMode and ADT.PaintMode.lastPlacedRecordID then
        local rid = ADT.PaintMode.lastPlacedRecordID
        local name, icon = GetDecorInfoByRecordID(rid)
        D(string.format("[Quickbar] From PaintMode.lastPlacedRecordID: recordID=%s, name=%s", tostring(rid), tostring(name)))
        return rid, name, icon
    end

    -- 备用：从 ADT.Housing 的统一接口拿一次
    if ADT.Housing and ADT.Housing.GetSelectedDecorRecordIDAndName then
        local rid, name, icon = ADT.Housing:GetSelectedDecorRecordIDAndName()
        if rid then return rid, name, icon end
    end
    return nil, nil, nil
end

-- 统一：取消当前抓取/预览（等同 R 在预览态）
local function CancelActiveEditing()
    if C_HousingBasicMode and C_HousingBasicMode.CancelActiveEditing then
        C_HousingBasicMode.CancelActiveEditing()
        return true
    end
    if C_HousingExpertMode and C_HousingExpertMode.CancelActiveEditing then
        C_HousingExpertMode.CancelActiveEditing()
        return true
    end
    return false
end

local function GetCurrentDecorRecordID()
    local rid, _, _ = GetCurrentDecorInfo()
    return rid
end

-- 获取 Decor 名称和图标（从 Catalog 查询）
GetDecorInfoByRecordID = function(recordID)
    if not recordID then return nil, nil end
    
    -- 方式1：从 Catalog 获取（使用正确的字段名：iconTexture/iconAtlas）
    if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
        local entryInfo = C_HousingCatalog.GetCatalogEntryInfoByRecordID(
            Enum.HousingCatalogEntryType.Decor, recordID, true)
        if entryInfo then
            -- 尝试多种可能的图标字段名
            local icon = entryInfo.iconTexture or entryInfo.iconAtlas or entryInfo.icon or entryInfo.iconID
            D(string.format("[Quickbar] GetCatalogEntryInfoByRecordID: name=%s, iconTexture=%s, iconAtlas=%s, icon=%s",
                tostring(entryInfo.name), tostring(entryInfo.iconTexture), tostring(entryInfo.iconAtlas), tostring(icon)))
            return entryInfo.name, icon, entryInfo.entryID
        end
    end
    
    -- 方式2：通过 C_HousingDecor.GetDecorIcon 直接获取图标
    if C_HousingDecor and C_HousingDecor.GetDecorIcon then
        local success, icon = pcall(C_HousingDecor.GetDecorIcon, recordID)
        if success and icon then
            D(string.format("[Quickbar] C_HousingDecor.GetDecorIcon: %s", tostring(icon)))
            return nil, icon, nil
        end
    end
    
    return nil, nil, nil
end

-- ===========================
-- 数据持久化
-- ===========================

-- 确保 DB 表存在
local function EnsureDB()
    if not _G.ADT_DB then _G.ADT_DB = {} end
    if not _G.ADT_DB.Quickbar then _G.ADT_DB.Quickbar = {} end
    return _G.ADT_DB.Quickbar
end

-- 加载持久化数据到运行时
function M:LoadSlots()
    local db = EnsureDB()
    for i = 1, NUM_SLOTS do
        if db[i] and db[i].recordID then
            local name, icon = GetDecorInfoByRecordID(db[i].recordID)
            self.slots[i] = {
                recordID = db[i].recordID,
                name = name or db[i].name or L["Unknown Decor"],
                icon = icon or db[i].icon or 134400,  -- 问号图标
            }
        else
            self.slots[i] = nil
        end
    end
    D("[Quickbar] Loaded " .. NUM_SLOTS .. " slots from SavedVariables")
end

-- 保存运行时数据到持久化
function M:SaveSlots()
    local db = EnsureDB()
    for i = 1, NUM_SLOTS do
        if self.slots[i] and self.slots[i].recordID then
            db[i] = {
                recordID = self.slots[i].recordID,
                name = self.slots[i].name,
                icon = self.slots[i].icon,
            }
        else
            db[i] = nil
        end
    end
    D("[Quickbar] Saved to SavedVariables")
end

-- ===========================
-- 槽位 CRUD
-- ===========================

function M:GetSlotData(slotIndex)
    return self.slots[slotIndex]
end

function M:SetSlotData(slotIndex, recordID, nameOverride, iconOverride)
    if not recordID then
        self.slots[slotIndex] = nil
        self:SaveSlots()
        self:RefreshUI()
        D(string.format("[Quickbar] Slot %d cleared", slotIndex))
        return
    end
    
    -- 优先使用传入的值，否则从 Catalog 查询
    local name = nameOverride
    local icon = iconOverride
    if not name or not icon then
        local catName, catIcon = GetDecorInfoByRecordID(recordID)
        name = name or catName
        icon = icon or catIcon
    end
    
    self.slots[slotIndex] = {
        recordID = recordID,
        name = name or L["Unknown Decor"],
        icon = icon or 134400,
    }
    self:SaveSlots()
    self:RefreshUI()
    D(string.format("[Quickbar] Slot %d set to recordID=%d, name=%s", 
        slotIndex, recordID, tostring(name)))
end

function M:ClearSlot(slotIndex)
    self:SetSlotData(slotIndex, nil)
    Notify(string.format(L["Quickbar slot %s cleared"] or "快捷栏 %s 已清空", SLOT_KEYS[slotIndex]), 'info')
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

-- ===========================
-- 核心交互逻辑
-- ===========================

function M:OnQuickbarKeyPressed(slotIndex)
    if not IsEditorActive() then return end
    
    local slotData = self:GetSlotData(slotIndex)
    local isPlacing = IsPlacingDecor()
    local isPlacingNew = IsPlacingNew()
    local isSelected = IsAnyDecorSelected()
    
    -- 获取当前抓取的完整信息
    local currentRID, currentName, currentIcon = nil, nil, nil
    if isPlacing then
        currentRID, currentName, currentIcon = GetCurrentDecorInfo()
    end
    
    D(string.format("[Quickbar] Key %s pressed: slotIndex=%d, isPlacing=%s, isPlacingNew=%s, isSelected=%s, slotHasData=%s, currentRID=%s",
        SLOT_KEYS[slotIndex], slotIndex, tostring(isPlacing), tostring(isPlacingNew), tostring(isSelected), tostring(slotData ~= nil), tostring(currentRID)))
    
    if isPlacing then
        -- 当前有抓取
        if slotData then
            -- 槽位非空：先取消当前抓取，再抓取槽位物品
            -- 必须先取消，否则当前物品会被放置在鼠标位置！
            if CancelActiveEditing() then D("[Quickbar] CancelActiveEditing before switching to slot item") end
            -- 延迟一小段时间再抓取槽位物品，确保取消操作完成
            C_Timer.After(0.1, function()
                self:PlaceFromSlot(slotIndex)
            end)
        else
            -- 槽位为空：绑定当前物品到槽位
            if currentRID then
                -- 绑定时直接传入名称和图标
                self:SetSlotData(slotIndex, currentRID, currentName, currentIcon)
                -- 绑定后的状态处理：
                --  - 若当前是“已选中地面装饰”，应当移除该装饰（等同于 R），以体现“装进快捷栏”的效果。
                --  - 若当前是“新装饰预览”（来自 Closet/商城），则取消当前预览即可。
                -- 优先依据全局态再回退（更稳健）
                local hasSelected = (C_HousingDecor and C_HousingDecor.IsDecorSelected and C_HousingDecor.IsDecorSelected()) or isSelected
                if hasSelected and ADT and ADT.Housing and ADT.Housing.RemoveSelectedDecor then
                    local ok = ADT.Housing:RemoveSelectedDecor()
                    D("[Quickbar] RemoveSelectedDecor called after bind, ok=" .. tostring(ok))
                else
                    local cancelled = CancelActiveEditing()
                    D("[Quickbar] CancelActiveEditing called after bind (preview or no selection), ok=" .. tostring(cancelled))
                end
                Notify(string.format(L["Decor bound to quickbar %s"] or "装饰已绑定到快捷栏 %s", 
                    SLOT_KEYS[slotIndex]), 'success')
                PlaySound(SOUNDKIT.UI_70_ARTIFACT_FORGE_APPEARANCE_LOCKED)
            end
        end
    else
        -- 当前无抓取
        if slotData then
            self:PlaceFromSlot(slotIndex)
        end
        -- 槽位为空：无操作
    end
end

-- 从槽位放置物品
function M:PlaceFromSlot(slotIndex)
    local slotData = self:GetSlotData(slotIndex)
    if not slotData or not slotData.recordID then
        D("[Quickbar] PlaceFromSlot: slot is empty")
        return
    end
    
    -- 切换到普通模式（如果在专家模式）
    local currentMode = C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode()
    if currentMode and currentMode ~= Enum.HouseEditorMode.BasicDecor then
        D("[Quickbar] Switching to BasicDecor mode")
        C_HouseEditor.ActivateHouseEditorMode(Enum.HouseEditorMode.BasicDecor)
        -- 延迟执行放置
        C_Timer.After(0.2, function()
            self:DoPlaceFromSlot(slotIndex)
        end)
        return
    end
    
    self:DoPlaceFromSlot(slotIndex)
end

function M:DoPlaceFromSlot(slotIndex)
    local slotData = self:GetSlotData(slotIndex)
    if not slotData or not slotData.recordID then return end
    
    -- 使用 ADT.Housing 的统一入口
    if ADT.Housing and ADT.Housing.StartPlacingByRecordID then
        local ok = ADT.Housing:StartPlacingByRecordID(slotData.recordID)
        if ok then
            D(string.format("[Quickbar] Placing from slot %d: %s", slotIndex, slotData.name or "?"))
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        else
            Notify(L["Cannot place decor"] or "无法放置装饰", 'warning')
        end
    else
        D("[Quickbar] ADT.Housing.StartPlacingByRecordID not available")
    end
end

-- ===========================
-- 按键绑定
-- ===========================

function M:SetupKeybindings() end
function M:EnableKeybindings() end
function M:DisableKeybindings() end

-- ===========================
-- UI 刷新（由 QuickbarUI 实现）
-- ===========================

function M:RefreshUI()
    if self.uiFrame and self.uiFrame.Refresh then
        self.uiFrame:Refresh()
    end
end

-- ===========================
-- 事件处理
-- ===========================

local function OnEditorOpened()
    -- 覆盖绑定改由 ADT.Keybinds 统一激活
    if M.uiFrame then M.uiFrame:Show() end
    D("[Quickbar] Editor opened")
end

local function OnEditorClosed()
    -- 覆盖绑定改由 ADT.Keybinds 统一停用
    if M.uiFrame then M.uiFrame:Hide() end
    D("[Quickbar] Editor closed")
end

M:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
M:RegisterEvent("ADDON_LOADED")

M:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME then
            M:LoadSlots()
        end
    elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
        local mode = ...
        if mode and mode ~= Enum.HouseEditorMode.None then
            OnEditorOpened()
        else
            OnEditorClosed()
        end
    end
end)

-- ===========================
-- 初始化
-- ===========================

-- 绑定启停交由 Keybinds 统一处理，这里不再重复启用。

-- ===========================
-- 斜杠命令
-- ===========================

SLASH_ADTQUICKBAR1 = "/adtquickbar"
SLASH_ADTQUICKBAR2 = "/adtqb"
SlashCmdList["ADTQUICKBAR"] = function(msg)
    if msg == "clear" then
        for i = 1, NUM_SLOTS do
            M.slots[i] = nil
        end
        M:SaveSlots()
        M:RefreshUI()
        Notify(L["All quickbar slots cleared"] or "所有快捷栏已清空", 'info')
    elseif msg == "show" then
        for i = 1, NUM_SLOTS do
            local data = M.slots[i]
            print(string.format("[%s] %s", SLOT_KEYS[i], 
                data and (data.name or tostring(data.recordID)) or "(空)"))
        end
    else
        print("|cff00ccff[ADT Quickbar]|r 用法:")
        print("  /adtqb clear - 清空所有快捷栏")
        print("  /adtqb show - 显示所有快捷栏内容")
    end
end

D("[Quickbar] Module loaded")
