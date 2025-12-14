-- Housing_DyeClipboard.lua：染料复制/粘贴（CustomizeMode）
-- 交互：
--   1) SHIFT+C（悬停装饰）复制染料
--   2) SHIFT+左键（悬停装饰）把剪贴板染料预览应用到“当前选中装饰”
-- 说明：ApplyDyeToSelectedDecor 只做预览；实际保存由暴雪 UI 自己的“应用”按钮提交。

local ADDON_NAME, ADT = ...
local L = (ADT and ADT.L) or {}

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
DyeClipboard._savedScheme = nil -- { [slotIndex]=dyeColorID(0=无色), ... }
DyeClipboard._savedSlots = nil  -- 最近一次复制来源的 dyeSlots（用于 tooltip 展示）

DyeClipboard._hookInstalled = false
DyeClipboard._registeredMouseUp = false

--------------------------------------------------------------------------------
-- 工具函数
--------------------------------------------------------------------------------

function DyeClipboard:_sortSlots(slots)
    table.sort(slots, function(a, b) return a.orderIndex < b.orderIndex end)
    return slots
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

function DyeClipboard:CanCustomizeDecor(decorInstanceInfo)
    if decorInstanceInfo and (not decorInstanceInfo.isLocked) and decorInstanceInfo.canBeCustomized then
        return decorInstanceInfo.dyeSlots and #decorInstanceInfo.dyeSlots > 0
    end
    return false
end

function DyeClipboard:_makeColorBlock(colorID)
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

function DyeClipboard:_createTooltipLineWithSwatch(prefixText, dyeSlots, numSlots)
    self:_sortSlots(dyeSlots)
    local line = (prefixText or "") .. ""
    numSlots = numSlots or #dyeSlots
    for i = 1, numSlots do
        local colorID = dyeSlots[i] and dyeSlots[i].dyeColorID or 0
        line = line .. self:_makeColorBlock(colorID)
    end
    return line
end

function DyeClipboard:HasSameScheme(decorInstanceInfo)
    if not self._savedScheme then
        return false
    end

    local dyeSlots = decorInstanceInfo and decorInstanceInfo.dyeSlots
    if not dyeSlots then
        return false
    end

    self:_sortSlots(dyeSlots)
    for i, v in ipairs(dyeSlots) do
        if not (v.dyeColorID and self._savedScheme[i] == v.dyeColorID) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- 复制 / 粘贴
--------------------------------------------------------------------------------

function DyeClipboard:CopyDyesFromHovered()
    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return false
    end
    if not (IsHoveringDecor and IsHoveringDecor()) then
        return false
    end

    local decorInstanceInfo = GetHoveredDecorInfo and GetHoveredDecorInfo()
    if not self:CanCustomizeDecor(decorInstanceInfo) then
        return false
    end

    self._savedScheme = {}
    self._savedSlots = decorInstanceInfo.dyeSlots
    self:_sortSlots(self._savedSlots)

    for i, v in ipairs(self._savedSlots) do
        self._savedScheme[i] = v.dyeColorID or 0
    end

    -- 复制后刷新 tooltip（避免“已复制/可粘贴”提示延迟）
    local hf = _G.HouseEditorFrame
    local modeFrame = hf and hf.CustomizeModeFrame
    if modeFrame and modeFrame.OnDecorHovered then
        GameTooltip:Hide()
        modeFrame:OnDecorHovered()
    end

    -- 如果当前已经选中一个可染色装饰，则自动尝试粘贴（更顺滑）
    if IsDecorSelected and IsDecorSelected() then
        local openedInfo = GetSelectedDecorInfo and GetSelectedDecorInfo()
        if self:CanCustomizeDecor(openedInfo) then
            self:ApplyDyesToSelected()
        end
    end

    if ADT.DebugPrint then
        ADT.DebugPrint("[DyeClipboard] 复制染料成功，槽位数=" .. tostring(#self._savedScheme))
    end
    return true
end

function DyeClipboard:ApplyDyesToSelected()
    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return false
    end
    if not self._savedScheme then
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
    self:_sortSlots(dyeSlots)

    local anyDiff = false
    for i, v in ipairs(dyeSlots) do
        local savedColorID = self._savedScheme[i] or 0
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

-- 对接 ADT 快捷键：SHIFT+C
function DyeClipboard:CopyFromHovered()
    return self:CopyDyesFromHovered()
end

--------------------------------------------------------------------------------
-- 事件：GLOBAL_MOUSE_UP（仅在 tooltip 判定可交互时注册）
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
    if button == "LeftButton" and IsShiftKeyDown() then
        self:ApplyDyesToSelected()
    end
end

function DyeClipboard:OnEvent(event, ...)
    if event == "GLOBAL_MOUSE_UP" then
        self:OnGlobalMouseUp(...)
    end
end

DyeClipboard:SetScript("OnEvent", function(self, ...) self:OnEvent(...) end)

--------------------------------------------------------------------------------
-- Tooltip hook：ShowDecorInstanceTooltip（tooltip 驱动注册）
--------------------------------------------------------------------------------

function DyeClipboard:OnShowDecorInstanceTooltip(modeFrame, decorInstanceInfo)
    -- 每次刷新 tooltip 都先清理注册，避免鼠标离开后依然拦截点击
    self:UnregisterGlobalMouseUp()

    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return
    end
    if not self:CanCustomizeDecor(decorInstanceInfo) then
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

    local currentLine = self:_createTooltipLineWithSwatch("", decorInstanceInfo.dyeSlots)
    if self:HasSameScheme(decorInstanceInfo) then
        tooltip:AddDoubleLine(L["Dyes Copied"] or "已复制此方案", currentLine, 0.5, 0.5, 0.5, 1, 1, 1)
    else
        tooltip:AddDoubleLine("SHIFT+C 复制染料", currentLine, 1, 0.82, 0, 1, 1, 1)
        if self._savedSlots then
            tooltip:AddDoubleLine("SHIFT+左键 粘贴染料", self:_createTooltipLineWithSwatch("", self._savedSlots, numSlots), 1, 0.82, 0, 1, 1, 1)
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
