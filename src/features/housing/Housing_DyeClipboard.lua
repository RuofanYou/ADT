-- Housing_DyeClipboard.lua：染料复制/粘贴（CustomizeMode）
-- 目标：交互与状态机 1:1 对齐参考实现 Referrence/Plumber/Modules/Housing/HouseEditor_CustomizeMode.lua
-- 交互：
--   1) 右键（悬停装饰）复制染料
--   2) Ctrl+左键（悬停装饰）把剪贴板染料预览应用到“当前选中装饰”
-- 说明：ApplyDyeToSelectedDecor 只做预览；实际保存由暴雪 UI 自己的“应用”按钮提交。

local ADDON_NAME, ADT = ...
local L = (ADT and ADT.L) or {}

local tsort = table.sort
local C_HousingCustomizeMode = C_HousingCustomizeMode
local C_DyeColor = C_DyeColor

local IsHoveringDecor = C_HousingCustomizeMode and C_HousingCustomizeMode.IsHoveringDecor
local GetHoveredDecorInfo = C_HousingCustomizeMode and C_HousingCustomizeMode.GetHoveredDecorInfo
local IsDecorSelected = C_HousingCustomizeMode and C_HousingCustomizeMode.IsDecorSelected
local GetSelectedDecorInfo = C_HousingCustomizeMode and C_HousingCustomizeMode.GetSelectedDecorInfo
local ApplyDyeToSelectedDecor = C_HousingCustomizeMode and C_HousingCustomizeMode.ApplyDyeToSelectedDecor

local DyeClipboard = CreateFrame("Frame", "ADT_DyeClipboard")
ADT.DyeClipboard = DyeClipboard

-- 单一权威状态
DyeClipboard.lastDyeInfo = nil  -- { [slotIndex]=dyeColorID(0=无色), ... }
DyeClipboard.lastDyeSlots = nil -- 最近一次复制来源的 dyeSlots（用于 tooltip 展示）

DyeClipboard._hookInstalled = false
DyeClipboard._registeredMouseUp = false

--------------------------------------------------------------------------------
-- 工具函数（对齐 Plumber 的最小集）
--------------------------------------------------------------------------------

local function SortFunc_DyeSlots(a, b)
    return a.orderIndex < b.orderIndex
end

local function IsCustomizeModeShown()
    local hf = _G.HouseEditorFrame
    local frame = hf and hf.CustomizeModeFrame
    return frame and frame.IsShown and frame:IsShown()
end

local function IsDyeClipboardEnabled()
    -- 默认启用；玩家手动关闭时才禁用
    return not (ADT.GetDBValue and ADT.GetDBValue("EnableDyeCopy") == false)
end

function DyeClipboard:IsCustomizableDecor(decorInstanceInfo)
    if decorInstanceInfo and (not decorInstanceInfo.isLocked) and decorInstanceInfo.canBeCustomized then
        return decorInstanceInfo.dyeSlots and #decorInstanceInfo.dyeSlots > 0
    end
    return false
end

local function MakeColorBlock(colorID)
    if not colorID or colorID == 0 then
        return "|cff666666█|r"
    end
    local colorData = C_DyeColor and C_DyeColor.GetDyeColorInfo and C_DyeColor.GetDyeColorInfo(colorID)
    if colorData and colorData.swatchColorStart then
        local r, g, b = colorData.swatchColorStart:GetRGBAsBytes()
        return string.format("|cff%02x%02x%02x█|r", r, g, b)
    end
    return "?"
end

local function CreateTooltipLineWithSwatch(prefixText, dyeSlots, numSlots)
    tsort(dyeSlots, SortFunc_DyeSlots)
    local line = (prefixText or "") .. ""
    numSlots = numSlots or #dyeSlots
    for i = 1, numSlots do
        local colorID = dyeSlots[i] and dyeSlots[i].dyeColorID or 0
        line = line .. MakeColorBlock(colorID)
    end
    return line
end

function DyeClipboard:IsDecorDyeCopied(decorInstanceInfo)
    if not self.lastDyeInfo then
        return false
    end

    local dyeSlots = decorInstanceInfo and decorInstanceInfo.dyeSlots
    if not dyeSlots then
        return false
    end

    tsort(dyeSlots, SortFunc_DyeSlots)
    for i, v in ipairs(dyeSlots) do
        -- 与 Plumber 一致：只要当前 slot.dyeColorID 不存在就视为不相等（无色=0 需要走 Apply 清空链路）
        if not (v.dyeColorID and self.lastDyeInfo[i] == v.dyeColorID) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- 复制 / 粘贴（对齐 Plumber）
--------------------------------------------------------------------------------

function DyeClipboard:TryCopyDecorDyes()
    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return false
    end
    if not (IsHoveringDecor and IsHoveringDecor()) then
        return false
    end

    local decorInstanceInfo = GetHoveredDecorInfo and GetHoveredDecorInfo()
    if not self:IsCustomizableDecor(decorInstanceInfo) then
        return false
    end

    self.lastDyeInfo = {}
    self.lastDyeSlots = decorInstanceInfo.dyeSlots
    tsort(self.lastDyeSlots, SortFunc_DyeSlots)

    for i, v in ipairs(self.lastDyeSlots) do
        self.lastDyeInfo[i] = v.dyeColorID or 0
    end

    -- 参考实现：复制后刷新 tooltip（避免“已复制/可粘贴”提示延迟）
    local hf = _G.HouseEditorFrame
    local modeFrame = hf and hf.CustomizeModeFrame
    if modeFrame and modeFrame.OnDecorHovered then
        GameTooltip:Hide()
        modeFrame:OnDecorHovered()
    end

    -- 参考实现：如果当前已经选中一个可染色装饰，则自动尝试粘贴（更顺滑）
    if IsDecorSelected and IsDecorSelected() then
        local openedInfo = GetSelectedDecorInfo and GetSelectedDecorInfo()
        if self:IsCustomizableDecor(openedInfo) then
            self:TryPasteCustomization()
        end
    end

    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 复制染料成功，槽位数=" .. tostring(#self.lastDyeInfo))
    end
    return true
end

function DyeClipboard:TryPasteCustomization()
    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return false
    end
    if not self.lastDyeInfo then
        return false
    end

    local info = GetSelectedDecorInfo and GetSelectedDecorInfo()
    if not (info and info.canBeCustomized) then
        return false
    end

    local dyeSlots = info.dyeSlots
    if not (dyeSlots and #dyeSlots > 0) then
        return false
    end
    tsort(dyeSlots, SortFunc_DyeSlots)

    local anyDiff = false
    for i, v in ipairs(dyeSlots) do
        local savedColorID = self.lastDyeInfo[i] or 0
        if savedColorID ~= v.dyeColorID then
            anyDiff = true
            v.dyeColorID = savedColorID

            if savedColorID == 0 then
                savedColorID = nil
            end

            if ApplyDyeToSelectedDecor then
                ApplyDyeToSelectedDecor(v.ID, savedColorID)
            end
        end
    end

    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 粘贴染料：anyDiff=" .. tostring(anyDiff))
    end
    return anyDiff
end

-- 兼容现有 Keybinds：SHIFT+C
function DyeClipboard:CopyFromHovered()
    return self:TryCopyDecorDyes()
end

--------------------------------------------------------------------------------
-- 事件：GLOBAL_MOUSE_UP（对齐 Plumber：仅在 tooltip 判定可交互时注册）
--------------------------------------------------------------------------------

function DyeClipboard:RegisterGlobalMouseUp()
    if self._registeredMouseUp then
        return
    end
    self._registeredMouseUp = true
    self:RegisterEvent("GLOBAL_MOUSE_UP")
end

function DyeClipboard:UnregisterGlobalMouseUp()
    if not self._registeredMouseUp then
        return
    end
    self._registeredMouseUp = false
    self:UnregisterEvent("GLOBAL_MOUSE_UP")
end

function DyeClipboard:OnGlobalMouseUp(button)
    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return
    end
    if button == "RightButton" then
        self:TryCopyDecorDyes()
    elseif button == "LeftButton" and IsControlKeyDown() then
        self:TryPasteCustomization()
    end
end

function DyeClipboard:OnEvent(event, ...)
    if event == "GLOBAL_MOUSE_UP" then
        self:OnGlobalMouseUp(...)
    end
end

DyeClipboard:SetScript("OnEvent", function(self, ...) self:OnEvent(...) end)

--------------------------------------------------------------------------------
-- Tooltip hook：ShowDecorInstanceTooltip（对齐 Plumber 的“tooltip 驱动注册”）
--------------------------------------------------------------------------------

function DyeClipboard:OnShowDecorInstanceTooltip(modeFrame, decorInstanceInfo)
    -- 参考实现：每次刷新 tooltip 都先清理注册，避免鼠标离开后依然拦截点击
    self:UnregisterGlobalMouseUp()

    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return
    end
    if not self:IsCustomizableDecor(decorInstanceInfo) then
        return
    end

    local tooltip = GameTooltip
    if not (tooltip and tooltip.GetOwner and tooltip:GetOwner() == modeFrame) then
        return
    end

    local numSlots = decorInstanceInfo.dyeSlots and #decorInstanceInfo.dyeSlots or 0
    if numSlots <= 0 then
        return
    end

    local currentLine = CreateTooltipLineWithSwatch("", decorInstanceInfo.dyeSlots)
    if self:IsDecorDyeCopied(decorInstanceInfo) then
        tooltip:AddDoubleLine(L["Dyes Copied"] or "已复制此方案", currentLine, 0.5, 0.5, 0.5, 1, 1, 1)
    else
        tooltip:AddDoubleLine("右键 复制染料", currentLine, 1, 0.82, 0, 1, 1, 1)
        if self.lastDyeSlots then
            tooltip:AddDoubleLine("Ctrl+左键 粘贴染料", CreateTooltipLineWithSwatch("", self.lastDyeSlots, numSlots), 1, 0.82, 0, 1, 1, 1)
        end
    end

    tooltip:Show()
    self:RegisterGlobalMouseUp()
end

local function TryInstallHook()
    if DyeClipboard._hookInstalled then
        return
    end
    local hf = _G.HouseEditorFrame
    local modeFrame = hf and hf.CustomizeModeFrame
    if not (modeFrame and modeFrame.ShowDecorInstanceTooltip) then
        return
    end

    DyeClipboard._hookInstalled = true
    hooksecurefunc(modeFrame, "ShowDecorInstanceTooltip", function(frame, decorInstanceInfo)
        DyeClipboard:OnShowDecorInstanceTooltip(frame, decorInstanceInfo)
    end)

    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 已安装 CustomizeMode Tooltip 钩子")
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 ~= "Blizzard_HouseEditor" and arg1 ~= ADDON_NAME then
        return
    end
    TryInstallHook()
end)

