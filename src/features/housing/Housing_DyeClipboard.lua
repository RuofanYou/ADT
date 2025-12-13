-- Housing_DyeClipboard.lua：染料复制粘贴模块
-- 功能：在自定义模式下，SHIFT+C 复制悬停装饰的染料方案，SHIFT+左键点击粘贴
-- ADT 独立实现

local ADDON_NAME, ADT = ...
local L = ADT and ADT.L or {}

-- 暴雪 API
local tblSort = table.sort
local C_HousingCustomizeMode = C_HousingCustomizeMode
local C_DyeColor = C_DyeColor

local IsHoveringDecor = C_HousingCustomizeMode and C_HousingCustomizeMode.IsHoveringDecor
local GetHoveredDecorInfo = C_HousingCustomizeMode and C_HousingCustomizeMode.GetHoveredDecorInfo
local IsDecorSelected = C_HousingCustomizeMode and C_HousingCustomizeMode.IsDecorSelected
local GetSelectedDecorInfo = C_HousingCustomizeMode and C_HousingCustomizeMode.GetSelectedDecorInfo
local ApplyDyeToSelectedDecor = C_HousingCustomizeMode and C_HousingCustomizeMode.ApplyDyeToSelectedDecor

-- 模块对象
local DyeClipboard = CreateFrame("Frame", "ADT_DyeClipboardHandler")
ADT.DyeClipboard = DyeClipboard

-- 剪贴板数据
DyeClipboard.copiedColors = nil        -- { [slotIndex] = dyeColorID, ... }
DyeClipboard.copiedSlotData = nil      -- 原始槽位数据
DyeClipboard.copiedFromName = nil

--------------------------------------------------------------------------------
-- 辅助函数
--------------------------------------------------------------------------------

-- 按槽位顺序排序
local function OrderBySlotIndex(a, b)
    return a.orderIndex < b.orderIndex
end

-- 生成染料颜色方块
local function MakeColorBlock(colorID)
    if not colorID or colorID == 0 then
        return "|cff666666█|r"
    end
    local colorData = C_DyeColor and C_DyeColor.GetDyeColorInfo(colorID)
    if colorData and colorData.swatchColorStart then
        local r, g, b = colorData.swatchColorStart:GetRGBAsBytes()
        return string.format("|cff%02x%02x%02x█|r", r, g, b)
    end
    return "?"
end

-- 检查装饰是否支持染色
local function CanDecorBeDyed(decorInfo)
    if not decorInfo then return false end
    if decorInfo.isLocked then return false end
    if not decorInfo.canBeCustomized then return false end
    local slots = decorInfo.dyeSlots
    return slots and #slots > 0
end

--------------------------------------------------------------------------------
-- 复制功能
--------------------------------------------------------------------------------

function DyeClipboard:CopyFromHovered()
    -- 检查是否启用染料复制功能
    if ADT.GetDBValue and ADT.GetDBValue('EnableDyeCopy') == false then
        return false
    end
    
    -- 检查是否悬停在装饰上
    if not IsHoveringDecor or not IsHoveringDecor() then
        return false
    end
    
    local decorInfo = GetHoveredDecorInfo and GetHoveredDecorInfo()
    if not CanDecorBeDyed(decorInfo) then
        return false
    end
    
    -- 存储染料数据
    local slots = decorInfo.dyeSlots
    tblSort(slots, OrderBySlotIndex)
    
    self.copiedColors = {}
    self.copiedSlotData = slots
    self.copiedFromName = decorInfo.name
    
    for idx, slot in ipairs(slots) do
        self.copiedColors[idx] = slot.dyeColorID or 0
    end
    
    -- 显示通知
    local colorPreview = ""
    for idx = 1, #slots do
        colorPreview = colorPreview .. MakeColorBlock(self.copiedColors[idx])
    end
    
    if ADT.Notify then
        local msg = string.format(L["Dyes copied from %s"] or "已复制 %s 的染料: ", decorInfo.name)
        ADT.Notify(msg .. colorPreview, "success")
    end
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 已复制: " .. tostring(decorInfo.name) .. ", 槽位数: " .. #slots)
    end
    
    return true
end

--------------------------------------------------------------------------------
-- 粘贴功能
--------------------------------------------------------------------------------

function DyeClipboard:PasteToSelected()
    -- 检查是否启用染料复制功能
    if ADT.GetDBValue and ADT.GetDBValue('EnableDyeCopy') == false then
        return false
    end
    
    -- 检查是否有已复制的数据
    if not self.copiedColors then
        return false
    end
    
    -- 获取选中装饰信息
    local targetInfo = GetSelectedDecorInfo and GetSelectedDecorInfo()
    if not targetInfo or not targetInfo.canBeCustomized then
        return false
    end
    
    local targetSlots = targetInfo.dyeSlots
    if not targetSlots or #targetSlots == 0 then
        return false
    end
    
    -- 排序目标槽位
    tblSort(targetSlots, OrderBySlotIndex)
    
    -- 应用染料
    local hasChanges = false
    for idx, slot in ipairs(targetSlots) do
        local sourceColor = self.copiedColors[idx] or 0
        local currentColor = slot.dyeColorID or 0
        
        if sourceColor ~= currentColor then
            hasChanges = true
            slot.dyeColorID = sourceColor
            
            local colorToApply = sourceColor == 0 and nil or sourceColor
            if ApplyDyeToSelectedDecor then
                ApplyDyeToSelectedDecor(slot.ID, colorToApply)
            end
        end
    end
    
    -- 显示通知
    if hasChanges then
        local colorPreview = ""
        local showCount = math.min(#self.copiedSlotData, #targetSlots)
        for idx = 1, showCount do
            colorPreview = colorPreview .. MakeColorBlock(self.copiedColors[idx])
        end
        
        if ADT.Notify then
            local msg = string.format(L["Dyes pasted to %s"] or "已粘贴染料到 %s: ", targetInfo.name or "")
            ADT.Notify(msg .. colorPreview, "success")
        end
        
        if ADT.DebugPrint then
            ADT.DebugPrint("[DyeClipboard] 已粘贴到: " .. tostring(targetInfo.name))
        end
    end
    
    return hasChanges
end

function DyeClipboard:HasCopiedDyes()
    return self.copiedColors ~= nil
end

function DyeClipboard:Clear()
    self.copiedColors = nil
    self.copiedSlotData = nil
    self.copiedFromName = nil
end




--------------------------------------------------------------------------------
-- 鼠标事件处理
--------------------------------------------------------------------------------

function DyeClipboard:OnEvent(event, ...)
    if event == "GLOBAL_MOUSE_UP" then
        local button = ...
        -- SHIFT+左键 = 粘贴染料
        if button == "LeftButton" and IsShiftKeyDown() then
            self:PasteToSelected()
        end
    end
end

DyeClipboard:SetScript("OnEvent", DyeClipboard.OnEvent)

--------------------------------------------------------------------------------
-- 模式状态管理
--------------------------------------------------------------------------------

function DyeClipboard:Enable()
    -- 检查是否启用染料复制功能
    if ADT.GetDBValue and ADT.GetDBValue('EnableDyeCopy') == false then
        return
    end
    
    self:RegisterEvent("GLOBAL_MOUSE_UP")
    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 已启用")
    end
end

function DyeClipboard:Disable()
    self:UnregisterEvent("GLOBAL_MOUSE_UP")
    self.copiedColors = nil
    self.copiedSlotData = nil
    self.copiedFromName = nil
    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 已禁用")
    end
end

-- 检查并更新状态
local function CheckModeState()
    local frame = HouseEditorFrame and HouseEditorFrame.CustomizeModeFrame
    if frame and frame:IsShown() then
        DyeClipboard:Enable()
    else
        DyeClipboard:Disable()
    end
end

-- 初始化 hooks
local function InitializeModule()
    local customizeFrame = HouseEditorFrame and HouseEditorFrame.CustomizeModeFrame
    if customizeFrame then
        customizeFrame:HookScript("OnShow", function()
            DyeClipboard:Enable()
        end)
        customizeFrame:HookScript("OnHide", function()
            DyeClipboard:Disable()
        end)
        CheckModeState()
    end
    
    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 模块初始化完成")
    end
end

local LoaderFrame = CreateFrame("Frame")
LoaderFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
LoaderFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, InitializeModule)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

--------------------------------------------------------------------------------
-- 调试命令
--------------------------------------------------------------------------------

SLASH_ADTDYE1 = "/adtdye"
SlashCmdList["ADTDYE"] = function(msg)
    local cmd = (msg or ""):lower()
    if cmd == "copy" then
        DyeClipboard:CopyFromHovered()
    elseif cmd == "paste" then
        DyeClipboard:PasteToSelected()
    elseif cmd == "clear" then
        DyeClipboard:Clear()
        if ADT.Notify then ADT.Notify(L["Dye clipboard cleared"] or "染料剪贴板已清空", "info") end
    elseif cmd == "status" then
        if DyeClipboard:HasCopiedDyes() then
            local preview = ""
            for i = 1, #DyeClipboard.copiedSlotData do
                preview = preview .. MakeColorBlock(DyeClipboard.copiedColors[i])
            end
            print("|cff00ff00[ADT]|r 已复制染料来自: " .. tostring(DyeClipboard.copiedFromName) .. " " .. preview)
        else
            print("|cff00ff00[ADT]|r 染料剪贴板为空")
        end
    else
        print("|cff00ff00[ADT 染料剪贴板]|r 用法:")
        print("  /adtdye copy - 复制悬停装饰的染料")
        print("  /adtdye paste - 粘贴染料到已选中装饰")
        print("  /adtdye clear - 清空剪贴板")
        print("  /adtdye status - 查看剪贴板状态")
        print("  快捷键: SHIFT+C 复制, SHIFT+左键 粘贴")
    end
end
