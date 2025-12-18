-- DockUI_Templates.lua
-- DockUI 滚动视图模板创建（DyePresetItem / KeybindEntry）
-- 从 DockUI.lua 拆分，遵循关注点分离原则

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local API = ADT.API
local Mixin = API.Mixin
local CreateFrame = CreateFrame

-- 从子模块获取配置（单一权威：DockUI_Def.lua）
local Def = ADT.DockUI.Def

-- 工具函数
local function SetTextColor(obj, color)
    obj:SetTextColor(color[1], color[2], color[3])
end

-- ============================================================================
-- DyePresetItem Mixin（染色预设条目）
-- ============================================================================

local DyePresetItemMixin = {}

function DyePresetItemMixin:SetPresetData(index, preset, categoryInfo)
    self.presetIndex = index
    self.preset = preset
    self.categoryInfo = categoryInfo

    -- 构建色块显示文本
    local colorStr = ""
    if preset and preset.colors then
        for _, colorID in ipairs(preset.colors) do
            colorStr = colorStr .. self:_makeColorBlock(colorID or 0)
        end
    end

    -- 设置显示：预设序号 + 色块
    local label = string.format("%s %d: %s", ADT.L["Preset"] or "预设", index, colorStr)
    self.Label:SetText(label)
end

function DyePresetItemMixin:_makeColorBlock(dyeColorID)
    -- 调用 DyeClipboard 的色块生成方法
    if ADT.DyeClipboard and ADT.DyeClipboard._makeColorBlock then
        return ADT.DyeClipboard:_makeColorBlock(dyeColorID)
    end
    -- 降级：简单色块占位
    return "|TInterface\\BUTTONS\\WHITE8X8:12:12:0:0:8:8:0:8:0:8|t"
end

function DyePresetItemMixin:OnEnter()
    self.Background:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    SetTextColor(self.Label, Def.TextColorHighlight)
end

function DyePresetItemMixin:OnLeave()
    self.Background:SetColorTexture(0, 0, 0, 0.1)
    SetTextColor(self.Label, Def.TextColorNormal)
end

function DyePresetItemMixin:OnClick(button)
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if self.categoryInfo and self.categoryInfo.onItemClick then
        self.categoryInfo.onItemClick(self.presetIndex, button)
        -- 刷新列表
        if button == "RightButton" then
            C_Timer.After(0.05, function()
                if MainFrame and MainFrame.ShowDyePresetsCategory then
                    MainFrame:ShowDyePresetsCategory(self.categoryInfo.key)
                end
            end)
        end
    end
end

-- ============================================================================
-- DyePresetItem 创建函数
-- ============================================================================

local function CreateDyePresetItemEntry(parent, centerButtonWidth)
    local f = CreateFrame("Button", nil, parent)
    Mixin(f, DyePresetItemMixin)
    f:SetSize(centerButtonWidth or Def.centerButtonWidth, 32)
    f:RegisterForClicks("AnyUp")

    -- 背景
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.1)
    f.Background = bg

    -- 标签（显示色块序列）
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", f, "LEFT", 8, 0)
    label:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.Label = label

    f:SetScript("OnEnter", f.OnEnter)
    f:SetScript("OnLeave", f.OnLeave)
    f:SetScript("OnClick", f.OnClick)

    return f
end

-- ============================================================================
-- KeybindEntry Mixin（快捷键条目）
-- ============================================================================

local KeybindEntryMixin = {}

-- 单一权威：所有显示数据一律从 ADT.Keybinds 现存配置读取
-- 说明：过去使用构建时快照（actionInfo）导致"滚动复用后回退到旧文本"。
-- 现改为按 actionName 即时查询，彻底消除快照失真。
function KeybindEntryMixin:SetKeybindByActionName(actionName)
    self.actionName = actionName
    -- 动作显示名
    local displayName = (ADT.Keybinds and ADT.Keybinds.GetActionDisplayName and ADT.Keybinds:GetActionDisplayName(actionName)) or actionName
    if self.ActionLabel then
        self.ActionLabel:SetText(displayName)
    end
    -- 按键显示名
    local key = ADT.Keybinds and ADT.Keybinds.GetKeybind and ADT.Keybinds:GetKeybind(actionName) or ""
    local keyText = ADT.Keybinds and ADT.Keybinds.GetKeyDisplayName and ADT.Keybinds:GetKeyDisplayName(key) or ""
    if self.KeyLabel then
        if keyText == "" then
            keyText = ADT.L["Not Set"]
            SetTextColor(self.KeyLabel, Def.TextColorDisabled or {0.5, 0.5, 0.5})
        else
            SetTextColor(self.KeyLabel, {1, 0.82, 0}) -- 金色
        end
        self.KeyLabel:SetText(keyText)
    end
    self:UpdateRecordingState(false)
end

function KeybindEntryMixin:UpdateRecordingState(isRecording)
    self.isRecording = isRecording
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    local headerHint = MainFrame and MainFrame._keybindCategoryHint
    if isRecording then
        -- 录制中状态
        if self.KeyLabel then
            self.KeyLabel:SetText(ADT.L["Press Key"])
            SetTextColor(self.KeyLabel, {1, 0.82, 0}) -- 金色
        end
        if self.KeyBorder then
            self.KeyBorder:SetColorTexture(1, 0.82, 0, 1)  -- 金色边框
        end
        -- 在 Header 区域显示提示
        if headerHint then
            headerHint:SetText(ADT.L["ESC Cancel"])
            headerHint:SetTextColor(1, 0.82, 0, 1)  -- 金色
        end
    else
        -- 恢复正常状态
        if self.KeyBorder then
            self.KeyBorder:SetColorTexture(0.3, 0.3, 0.3, 1)  -- 灰色边框
        end
        -- 清除 Header 提示
        if headerHint then
            headerHint:SetText("")
        end
    end
end

function KeybindEntryMixin:OnRecordButtonClick()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if self.isRecording then
        -- 取消录制
        self:UpdateRecordingState(false)
        -- 恢复当前配置显示（而非旧快照）
        self:SetKeybindByActionName(self.actionName)
        if MainFrame then MainFrame._recordingKeybindEntry = nil end
    else
        -- 开始录制
        -- 先取消其他正在录制的条目
        if MainFrame and MainFrame._recordingKeybindEntry and MainFrame._recordingKeybindEntry ~= self then
            MainFrame._recordingKeybindEntry:UpdateRecordingState(false)
            MainFrame._recordingKeybindEntry:SetKeybindByActionName(MainFrame._recordingKeybindEntry.actionName)
        end
        if MainFrame then MainFrame._recordingKeybindEntry = self end
        self:UpdateRecordingState(true)
    end
end

function KeybindEntryMixin:OnClearButtonClick()
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if self.actionName and ADT.Keybinds then
        ADT.Keybinds:SetKeybind(self.actionName, "")
        -- 刷新显示（即时读取单一权威配置）
        self:SetKeybindByActionName(self.actionName)
    end
end

function KeybindEntryMixin:OnKeyDown(key)
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not self.isRecording then return end
    
    -- 忽略单独的修饰键
    if key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT" then return end
    if key == "LCTRL" or key == "RCTRL" or key == "CTRL" then return end
    if key == "LALT" or key == "RALT" or key == "ALT" then return end
    if key == "ESCAPE" then
        -- ESC 取消录制（恢复当前配置显示）
        self:UpdateRecordingState(false)
        self:SetKeybindByActionName(self.actionName)
        if MainFrame then MainFrame._recordingKeybindEntry = nil end
        return
    end
    
    -- 构建按键字符串
    local modifiers = ""
    if IsControlKeyDown() then modifiers = modifiers .. "CTRL-" end
    if IsShiftKeyDown() then modifiers = modifiers .. "SHIFT-" end
    if IsAltKeyDown() then modifiers = modifiers .. "ALT-" end
    
    local finalKey = modifiers .. key
    
    -- 保存按键
    if self.actionName and ADT.Keybinds then
        ADT.Keybinds:SetKeybind(self.actionName, finalKey)
        -- 刷新显示（从配置读取最新值，避免本地快照）
        self:SetKeybindByActionName(self.actionName)
    end
    
    self:UpdateRecordingState(false)
    if MainFrame then MainFrame._recordingKeybindEntry = nil end
end

function KeybindEntryMixin:GetDesiredWidth()
    -- 动态计算所需宽度：基于实际文本宽度 + 按键框 + 左右内边距
    local KCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.KeybindUI) or {}
    local keyBoxWidth = KCFG.keyBoxWidth or 100
    local actionToKeyGap = KCFG.actionToKeyGap or 8
    local leftPad  = KCFG.rowLeftPad or 8
    local rightPad = KCFG.rowRightPad or 8

    local minText = KCFG.actionLabelWidth or 120
    local textWidth = minText
    if self.ActionLabel and self.ActionLabel.GetStringWidth then
        local actualWidth = self.ActionLabel:GetStringWidth()
        if actualWidth and actualWidth > 0 then
            textWidth = math.max(minText, actualWidth + 10) -- 额外留白
        end
    end

    return leftPad + textWidth + actionToKeyGap + keyBoxWidth + rightPad
end

-- ============================================================================
-- KeybindEntry 创建函数
-- ============================================================================

local function CreateKeybindEntry(parent, centerButtonWidth)
    local MainFrame = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    
    -- 读取配置（配置驱动，单一权威）
    local KCFG = (ADT.HousingInstrCFG and ADT.HousingInstrCFG.KeybindUI) or {}
    local actionLabelWidth = KCFG.actionLabelWidth or 120
    local keyBoxWidth = KCFG.keyBoxWidth or 100
    local keyBoxHeight = KCFG.keyBoxHeight or 22
    local actionToKeyGap = KCFG.actionToKeyGap or 8
    local rowLeftPad  = KCFG.rowLeftPad or 8
    local rowRightPad = KCFG.rowRightPad or 8
    local borderNormal = KCFG.borderNormal or { r = 0.3, g = 0.3, b = 0.3, a = 1 }
    local borderHover = KCFG.borderHover or { r = 0.8, g = 0.6, b = 0, a = 1 }
    local bgColor = KCFG.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 1 }
    
    local f = CreateFrame("Button", nil, parent)
    Mixin(f, KeybindEntryMixin)
    f:SetSize(centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- 背景
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.1)
    f.Background = bg
    
    -- 动作名称标签（左侧）
    local actionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionLabel:SetJustifyH("LEFT")
    f.ActionLabel = actionLabel

    -- 按键框容器（右对齐，保证右侧留边对称）
    local keyBox = CreateFrame("Button", nil, f)
    keyBox:SetSize(keyBoxWidth, keyBoxHeight)
    keyBox:ClearAllPoints()
    keyBox:SetPoint("RIGHT", f, "RIGHT", -rowRightPad, 0)
    keyBox:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.KeyBox = keyBox

    -- 重新锚定动作名称标签：左贴父，右贴按键框左侧，留出间距
    actionLabel:ClearAllPoints()
    actionLabel:SetPoint("LEFT", f, "LEFT", rowLeftPad, 0)
    actionLabel:SetPoint("RIGHT", keyBox, "LEFT", -actionToKeyGap, 0)
    if actionLabel.SetMaxLines then actionLabel:SetMaxLines(1) end
    if actionLabel.SetWordWrap then actionLabel:SetWordWrap(false) end
    
    -- 按键框背景（深色边框）
    local keyBg = keyBox:CreateTexture(nil, "BACKGROUND")
    keyBg:SetAllPoints()
    keyBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    f.KeyBackground = keyBg
    
    -- 按键框边框
    local keyBorder = keyBox:CreateTexture(nil, "BORDER")
    keyBorder:SetAllPoints()
    keyBorder:SetColorTexture(borderNormal.r, borderNormal.g, borderNormal.b, borderNormal.a)
    keyBorder:SetDrawLayer("BORDER", -1)
    f.KeyBorder = keyBorder
    
    -- 内边框（让背景看起来有边框）
    local keyInner = keyBox:CreateTexture(nil, "ARTWORK")
    keyInner:SetPoint("TOPLEFT", 1, -1)
    keyInner:SetPoint("BOTTOMRIGHT", -1, 1)
    keyInner:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    f.KeyInner = keyInner
    
    -- 按键文本
    local keyLabel = keyBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keyLabel:SetPoint("CENTER", keyBox, "CENTER", 0, 0)
    f.KeyLabel = keyLabel
    
    -- 按键框点击：左键录制，右键清除
    keyBox:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            f:OnClearButtonClick()
        else
            f:OnRecordButtonClick()
        end
    end)
    
    -- 按键框悬停效果（使用 Header 区域的提示）
    keyBox:SetScript("OnEnter", function(self)
        if not f.isRecording then
            keyBorder:SetColorTexture(borderHover.r, borderHover.g, borderHover.b, borderHover.a)
            local mf = ADT.CommandDock and ADT.CommandDock.SettingsPanel
            local headerHint = mf and mf._keybindCategoryHint
            if headerHint then
                local hintColor = KCFG.hintHover or { r = 0.6, g = 0.8, b = 1 }
                local hintText = ADT.L["Right Click Clear"]
                headerHint:SetText(hintText)
                headerHint:SetTextColor(hintColor.r, hintColor.g, hintColor.b, 1)
            end
        end
    end)
    
    keyBox:SetScript("OnLeave", function(self)
        if not f.isRecording then
            keyBorder:SetColorTexture(borderNormal.r, borderNormal.g, borderNormal.b, borderNormal.a)
            local mf = ADT.CommandDock and ADT.CommandDock.SettingsPanel
            local headerHint = mf and mf._keybindCategoryHint
            if headerHint then
                headerHint:SetText("")
            end
        end
    end)
    
    -- 键盘监听
    f:SetScript("OnKeyDown", function(self, key)
        if self.isRecording then
            self:SetPropagateKeyboardInput(false)
            self:OnKeyDown(key)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    
    return f
end

-- ============================================================================
-- 模板注册函数（由 DockUI.lua 调用）
-- ============================================================================

function ADT.DockUI.RegisterScrollViewTemplates(ScrollView, centerButtonWidth)
    -- 染色预设条目模板
    local function DyePresetItem_Create()
        local obj = CreateDyePresetItemEntry(ScrollView, centerButtonWidth)
        obj:SetSize(centerButtonWidth or Def.centerButtonWidth, 32)
        return obj
    end
    ScrollView:AddTemplate("DyePresetItem", DyePresetItem_Create)

    -- 快捷键条目模板
    local function KeybindEntry_Create()
        local obj = CreateKeybindEntry(ScrollView, centerButtonWidth)
        obj:SetSize(centerButtonWidth or Def.centerButtonWidth, Def.ButtonSize)
        return obj
    end
    ScrollView:AddTemplate("KeybindEntry", KeybindEntry_Create)
end

-- 导出 Mixin（供外部复用或测试）
ADT.DockUI.DyePresetItemMixin = DyePresetItemMixin
ADT.DockUI.KeybindEntryMixin = KeybindEntryMixin
