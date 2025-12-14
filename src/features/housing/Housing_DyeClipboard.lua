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
DyeClipboard._savedSchemeKey = nil -- string：最近一次复制的“染料方案指纹”（序列化后）
DyeClipboard._savedColors = nil -- number[]：最近一次复制的颜色序列（0=无色）

DyeClipboard._hookInstalled = false
DyeClipboard._registeredMouseUp = false

--------------------------------------------------------------------------------
-- 工具函数
--------------------------------------------------------------------------------

local function CopyAndSortDyeSlots(dyeSlots)
    if not dyeSlots then
        return nil
    end
    local copy = {}
    for i = 1, #dyeSlots do
        copy[i] = dyeSlots[i]
    end
    table.sort(copy, function(a, b)
        if not a then
            return false
        end
        if not b then
            return true
        end
        return (a.orderIndex or 0) < (b.orderIndex or 0)
    end)
    return copy
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

local function ExtractDyeColorsFromSlots(sortedSlots)
    if not sortedSlots then
        return nil
    end
    local colors = {}
    for i = 1, #sortedSlots do
        local slot = sortedSlots[i]
        local colorID = 0
        if slot and slot.dyeColorID then
            colorID = slot.dyeColorID
        end
        colors[i] = colorID
    end
    return colors
end

local function EncodeSchemeKey(colors)
    if not colors then
        return nil
    end
    -- 方案指纹：用“长度 + 冒号分隔”保证确定性（同时便于快速比较）
    -- 例：3:0:120:0
    return tostring(#colors) .. ":" .. table.concat(colors, ":")
end

function DyeClipboard:_renderSwatchLineFromSlots(prefixText, dyeSlots, numSlots)
    local sortedSlots = CopyAndSortDyeSlots(dyeSlots)
    if not sortedSlots then
        return (prefixText or "")
    end
    numSlots = numSlots or #sortedSlots
    local line = (prefixText or "")
    for i = 1, numSlots do
        local slot = sortedSlots[i]
        local colorID = (slot and slot.dyeColorID) or 0
        line = line .. self:_makeColorBlock(colorID)
    end
    return line
end

function DyeClipboard:_renderSwatchLineFromColors(prefixText, colors, numSlots)
    if not colors then
        return (prefixText or "")
    end
    numSlots = numSlots or #colors
    local line = (prefixText or "")
    for i = 1, numSlots do
        line = line .. self:_makeColorBlock(colors[i] or 0)
    end
    return line
end

function DyeClipboard:HasSameScheme(decorInstanceInfo)
    if not self._savedSchemeKey then
        return false
    end

    local dyeSlots = decorInstanceInfo and decorInstanceInfo.dyeSlots
    local sortedSlots = CopyAndSortDyeSlots(dyeSlots)
    if not sortedSlots then
        return false
    end

    local colors = ExtractDyeColorsFromSlots(sortedSlots)
    local key = EncodeSchemeKey(colors)
    return key == self._savedSchemeKey
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

    local sortedSlots = CopyAndSortDyeSlots(decorInstanceInfo.dyeSlots)
    local colors = ExtractDyeColorsFromSlots(sortedSlots)
    self._savedColors = colors
    self._savedSchemeKey = EncodeSchemeKey(colors)

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
        ADT.DebugPrint("[DyeClipboard] 复制染料成功，槽位数=" .. tostring(colors and #colors or 0))
    end
    return true
end

function DyeClipboard:ApplyDyesToSelected()
    if not (IsDyeClipboardEnabled() and IsCustomizeModeShown()) then
        return false
    end
    if not self._savedColors then
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
    local sortedSlots = CopyAndSortDyeSlots(dyeSlots)

    local anyDiff = false
    for i = 1, #sortedSlots do
        local slot = sortedSlots[i]
        local currentColorID = (slot and slot.dyeColorID) or 0
        local wantedColorID = self._savedColors[i] or 0
        if wantedColorID ~= currentColorID then
            anyDiff = true
            if slot then
                slot.dyeColorID = wantedColorID
            end

            if ApplyDyeToSelectedDecor then
                local apiColorID = wantedColorID
                if apiColorID == 0 then
                    apiColorID = nil
                end
                if slot and slot.ID then
                    ApplyDyeToSelectedDecor(slot.ID, apiColorID)
                end
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
