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

-- 内部状态
DyeClipboard._tooltipHookInstalled = false

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

local function IsDyeClipboardEnabled()
    -- 默认启用；玩家手动关闭时才禁用
    return not (ADT.GetDBValue and ADT.GetDBValue('EnableDyeCopy') == false)
end

local function IsCustomizeModeShown()
    local hf = _G.HouseEditorFrame
    local frame = hf and hf.CustomizeModeFrame
    return frame and frame.IsShown and frame:IsShown()
end

local function BuildPreviewFromSlots(dyeSlots, numSlots)
    if not dyeSlots or #dyeSlots == 0 then return "" end
    tblSort(dyeSlots, OrderBySlotIndex)
    local preview = ""
    numSlots = numSlots or #dyeSlots
    for i = 1, numSlots do
        local slot = dyeSlots[i]
        preview = preview .. MakeColorBlock(slot and slot.dyeColorID or 0)
    end
    return preview
end

local function BuildPreviewFromColors(colors, numSlots)
    if not colors then return "" end
    local preview = ""
    for i = 1, (numSlots or #colors) do
        preview = preview .. MakeColorBlock(colors[i] or 0)
    end
    return preview
end

local function AreSlotsSameAsColors(dyeSlots, colors)
    if not (dyeSlots and colors) then return false end
    tblSort(dyeSlots, OrderBySlotIndex)
    for i, slot in ipairs(dyeSlots) do
        local a = slot.dyeColorID or 0
        local b = colors[i] or 0
        if a ~= b then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- 复制功能
--------------------------------------------------------------------------------

function DyeClipboard:CopyFromHovered()
    -- 检查是否启用染料复制功能
    if not IsDyeClipboardEnabled() then
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
    if not IsDyeClipboardEnabled() then
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

function DyeClipboard:TryPasteByShiftClick()
    if not IsDyeClipboardEnabled() then
        return false
    end
    if not self.copiedColors then
        return false
    end
    if not IsCustomizeModeShown() then
        return false
    end

    -- 只响应“点在装饰上”的 Shift+左键，避免误点 UI 造成对当前选中目标的意外覆盖
    if IsHoveringDecor and not IsHoveringDecor() then
        return false
    end

    -- 选择状态有可能在同一帧稍后才刷新；延迟到下一帧再取 SelectedDecorInfo 更稳
    C_Timer.After(0, function()
        self:PasteToSelected()
    end)
    return true
end

function DyeClipboard:OnEvent(event, ...)
    if event == "GLOBAL_MOUSE_UP" then
        local button = ...
        -- SHIFT+左键 = 粘贴染料
        if button == "LeftButton" and IsShiftKeyDown() then
            self:TryPasteByShiftClick()
        end
    end
end

DyeClipboard:SetScript("OnEvent", DyeClipboard.OnEvent)

-- 全局鼠标抬起监听：不依赖 HouseEditorFrame 是否已创建，靠运行时判断当前是否处于自定义模式
DyeClipboard:RegisterEvent("GLOBAL_MOUSE_UP")

--------------------------------------------------------------------------------
-- Tooltip 增强（对齐自定义模式体验，但不依赖复制/粘贴核心逻辑）
--------------------------------------------------------------------------------

local function TryInstallCustomizeTooltipHook()
    if DyeClipboard._tooltipHookInstalled then return end
    local hf = _G.HouseEditorFrame
    local modeFrame = hf and hf.CustomizeModeFrame
    if not (modeFrame and modeFrame.ShowDecorInstanceTooltip) then return end

    DyeClipboard._tooltipHookInstalled = true

    hooksecurefunc(modeFrame, "ShowDecorInstanceTooltip", function(frame, decorInstanceInfo)
        if not (IsDyeClipboardEnabled() and decorInstanceInfo and CanDecorBeDyed(decorInstanceInfo)) then
            return
        end

        local tooltip = GameTooltip
        if not (tooltip and tooltip.GetOwner and tooltip:GetOwner() == frame) then
            return
        end

        local numSlots = decorInstanceInfo.dyeSlots and #decorInstanceInfo.dyeSlots or 0
        if numSlots <= 0 then return end

        -- 右侧小预览：先展示“目标当前染料”，再展示“剪贴板染料（如有）”
        local currentPreview = BuildPreviewFromSlots(decorInstanceInfo.dyeSlots)
        tooltip:AddDoubleLine("SHIFT+C 复制染料", currentPreview, 1, 0.82, 0, 1, 1, 1)

        if DyeClipboard.copiedColors then
            local clipPreview = BuildPreviewFromColors(DyeClipboard.copiedColors, numSlots)
            if AreSlotsSameAsColors(decorInstanceInfo.dyeSlots, DyeClipboard.copiedColors) then
                tooltip:AddDoubleLine("已复制此方案", clipPreview, 0.6, 0.6, 0.6, 1, 1, 1)
            else
                tooltip:AddDoubleLine("SHIFT+左键 粘贴染料", clipPreview, 1, 0.82, 0, 1, 1, 1)
            end
        end

        tooltip:Show()
    end)

    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 已安装 CustomizeMode Tooltip 钩子")
    end
end

-- 说明：
-- 过去我们在 PLAYER_ENTERING_WORLD 时只尝试一次读取 HouseEditorFrame.CustomizeModeFrame 并安装钩子。
-- 但 HouseEditor UI 往往按需加载（Blizzard_HouseEditor），导致那一次尝试拿不到 frame，从而 Shift+左键永远不生效。
-- 现在改为：
-- 1) GLOBAL_MOUSE_UP 永久监听，运行时判断是否处于 CustomizeMode；
-- 2) Tooltip 钩子在 Blizzard_HouseEditor 加载后再安装。

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_HouseEditor" and arg1 ~= ADDON_NAME then
        return
    end
    TryInstallCustomizeTooltipHook()
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
