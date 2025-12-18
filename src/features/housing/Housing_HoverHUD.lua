-- Housing_HoverHUD.lua：悬停信息与热键提示 HUD（ADT 独立实现）
local ADDON_NAME, ADT = ...
local L = ADT and ADT.L or {}

-- 直接使用暴雪 Housing API
local C_HousingDecor = C_HousingDecor
local GetHoveredDecorInfo = C_HousingDecor.GetHoveredDecorInfo
local IsHoveringDecor = C_HousingDecor.IsHoveringDecor
local GetActiveHouseEditorMode = C_HouseEditor.GetActiveHouseEditorMode
local IsHouseEditorActive = C_HouseEditor.IsHouseEditorActive
local GetCatalogEntryInfoByRecordID = C_HousingCatalog.GetCatalogEntryInfoByRecordID
local IsDecorSelected = C_HousingBasicMode.IsDecorSelected
-- 注意：SetPlacedDecorEntryHovered 是受保护 API，不能被第三方插件使用

local DisplayFrame

local function GetCatalogDecorInfo(decorID, tryGetOwnedInfo)
    tryGetOwnedInfo = true
    -- Enum.HousingCatalogEntryType.Decor = 1
    return GetCatalogEntryInfoByRecordID(1, decorID, tryGetOwnedInfo)
end

local EL = CreateFrame("Frame")
ADT.Housing = EL

-- 顶层：按 recordID 进入放置（供多处复用；单一权威）
function EL:StartPlacingByRecordID(recordID)
    if not recordID then return false end
    local entryInfo = GetCatalogDecorInfo(recordID)
    if not entryInfo or not entryInfo.entryID then return false end

    -- 室内/室外限制检查（单一权威）
    local isPlayerIndoors = C_Housing and C_Housing.IsInsideHouse and C_Housing.IsInsideHouse()
    local decorAllowsIndoors = entryInfo.isAllowedIndoors
    local decorAllowsOutdoors = entryInfo.isAllowedOutdoors
    
    -- 玩家在室外，但装饰仅允许室内
    if not isPlayerIndoors and decorAllowsIndoors and not decorAllowsOutdoors then
        if ADT and ADT.Notify then
            ADT.Notify(L["Cannot place indoor-only decor outdoors"], "warning")
        end
        return false
    end

    local decorPlaced = C_HousingDecor.GetSpentPlacementBudget()
    local maxDecor = C_HousingDecor.GetMaxPlacementBudget()
    local hasMaxDecor = C_HousingDecor.HasMaxPlacementBudget()
    if hasMaxDecor and decorPlaced >= maxDecor then
        return false
    end
    C_HousingBasicMode.StartPlacingNewDecor(entryInfo.entryID)
    return true
end


--
-- 简易剪切板（仅当前会话，单一权威）
--
EL.clipboard = nil -- { decorID, name, icon }

function EL:SetClipboard(recordID, name, icon)
    if not recordID then return false end
    self.clipboard = { decorID = recordID, name = name, icon = icon }
    return true
end

function EL:GetClipboard()
    return self.clipboard
end

--
-- 误操作保护模块（L 键锁定/解锁，选中时阻止选中）
--
local Protection = {}
EL.Protection = Protection

-- 本地缓存（避免 CopyDefaults 导致的数据不同步）
local protectedCache = nil

-- 获取保护列表（确保同步）
local function GetProtectedDB()
    -- 确保 ADT_DB 存在
    if not _G.ADT_DB then _G.ADT_DB = {} end
    if not _G.ADT_DB.ProtectedDecors then _G.ADT_DB.ProtectedDecors = {} end
    return _G.ADT_DB.ProtectedDecors
end

-- 检查装饰是否受保护（返回 isProtected, protectedName）
function Protection:IsProtected(decorGUID, decorID)
    local db = GetProtectedDB()
    local isProtected = decorGUID and db[decorGUID] ~= nil
    if ADT and ADT.DebugPrint then 
        ADT.DebugPrint("[Protection] IsProtected: GUID=" .. tostring(decorGUID) .. ", result=" .. tostring(isProtected))
    end
    if isProtected then
        return true, db[decorGUID].name
    end
    return false, nil
end

-- 添加保护（单个实例）
function Protection:ProtectInstance(decorGUID, name)
    if not decorGUID then return false end
    local db = GetProtectedDB()
    db[decorGUID] = { name = name or "未知", protectedAt = time() }
    if ADT and ADT.DebugPrint then 
        ADT.DebugPrint("[Protection] ProtectInstance: GUID=" .. tostring(decorGUID) .. " added")
    end
    return true
end

-- 移除保护（单个实例）
function Protection:UnprotectInstance(decorGUID)
    if not decorGUID then return false end
    local db = GetProtectedDB()
    if ADT and ADT.DebugPrint then 
        ADT.DebugPrint("[Protection] UnprotectInstance: GUID=" .. tostring(decorGUID) .. ", exists=" .. tostring(db[decorGUID] ~= nil))
    end
    if db[decorGUID] then
        db[decorGUID] = nil
        if ADT and ADT.DebugPrint then 
            ADT.DebugPrint("[Protection] UnprotectInstance: GUID=" .. tostring(decorGUID) .. " removed, verify=" .. tostring(db[decorGUID] == nil))
        end
        return true
    end
    return false
end

-- 获取所有受保护装饰列表
function Protection:GetAllProtected()
    return GetProtectedDB()
end

-- 清除所有保护
function Protection:ClearAll()
    if _G.ADT_DB then
        _G.ADT_DB.ProtectedDecors = {}
    end
end

-- 切换悬停装饰的保护状态
function EL:ToggleProtection()
    -- 若未启用 L 锁定开关，则直接忽略
    do
        local enabled = ADT.GetDBValue("EnableLock")
        if enabled == nil then enabled = true end
        if not enabled then return end
    end
    if ADT and ADT.DebugPrint then ADT.DebugPrint("[Housing] ToggleProtection called") end
    
    if not IsHouseEditorActive() then 
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[Housing] ToggleProtection: Editor not active") end
        return 
    end
    
    -- 获取悬停的装饰
    local info = GetHoveredDecorInfo()
    if ADT and ADT.DebugPrint then 
        ADT.DebugPrint("[Housing] ToggleProtection: HoveredInfo=" .. tostring(info and info.decorGUID or "nil")) 
    end
    
    if not info or not info.decorGUID then
        if ADT and ADT.Notify then
            ADT.Notify(L["Hover a decor to lock"], "warning")
        end
        return
    end
    
    -- 切换保护状态
    local isProtected = self.Protection:IsProtected(info.decorGUID, info.decorID)
    if ADT and ADT.DebugPrint then 
        ADT.DebugPrint("[Housing] ToggleProtection: isProtected=" .. tostring(isProtected) .. ", name=" .. tostring(info.name)) 
    end
    
    if isProtected then
        self.Protection:UnprotectInstance(info.decorGUID)
        if ADT and ADT.Notify then
            ADT.Notify("|A:BonusChest-Lock:16:16|a " .. string.format(L["Unlocked %s"], (info.name or L["Unknown Decor"])) , "success")
        end
    else
        self.Protection:ProtectInstance(info.decorGUID, info.name)
        if ADT and ADT.Notify then
            ADT.Notify("|A:BonusChest-Lock:16:16|a " .. string.format(L["Locked %s"], (info.name or L["Unknown Decor"])) , "success")
        end
    end
end

-- 确认弹窗定义
StaticPopupDialogs["ADT_CONFIRM_EDIT_PROTECTED"] = {
    text = "⚠️ " .. L["Decor is locked"] .. "\n\n%s\n\n" .. L["Confirm edit?"],
    button1 = L["Continue Edit"],
    button2 = L["Cancel Select"],
    button3 = L["Unlock"],
    
    OnAccept = function(self, data)
        -- 用户选择"继续编辑"，不做任何事，保持当前选中
        if ADT and ADT.Notify then
            ADT.Notify(L["Edit allowed"], "info")
        end
    end,
    
    OnCancel = function(self, data, reason)
        -- 用户选择"取消选中"
        if reason == "clicked" then
            pcall(function()
                if C_HousingBasicMode and C_HousingBasicMode.CancelActiveEditing then
                    C_HousingBasicMode.CancelActiveEditing()
                elseif C_HousingExpertMode and C_HousingExpertMode.CancelActiveEditing then
                    C_HousingExpertMode.CancelActiveEditing()
                end
            end)
            if ADT and ADT.Notify then
                ADT.Notify(L["Selection cancelled"], "info")
            end
        end
    end,
    
    OnAlt = function(self, data)
        -- 用户选择"解除保护"
        if data and data.decorGUID then
            if ADT and ADT.Housing and ADT.Housing.Protection then
                ADT.Housing.Protection:UnprotectInstance(data.decorGUID)
            end
            if ADT and ADT.Notify then
                ADT.Notify("🔓 " .. string.format(L["Unlocked %s"], (data.name or L["Unknown Decor"])) , "success")
            end
        end
    end,
    
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

--
-- UI
--
local DisplayFrameMixin = {}
do
    function DisplayFrameMixin:UpdateVisuals() end
    function DisplayFrameMixin:UpdateControl() end

    function DisplayFrameMixin:SetHotkey(instruction, bindingText)
        self.InstructionText:SetText(instruction)

        self.Control.Text:SetText(bindingText)
        self.Control.Text:Show()
        self.Control.Background:Show()
        self.Control.Icon:Hide()

        local textWidth = (self.Control.Text:GetWrappedWidth()) + 20
        self.Control.Background:SetWidth(textWidth)
        self.Control:SetWidth(textWidth)

        self.InstructionText:ClearAllPoints()
        if textWidth > 50 then
            self.InstructionText:SetPoint("RIGHT", self, "RIGHT", -textWidth - 5, 0)
        else
            self.InstructionText:SetPoint("RIGHT", self, "RIGHT", -55, 0)
        end
    end

    local function FadeIn_OnUpdate(self, elapsed)
        self.alpha = self.alpha + 5 * elapsed
        if self.alpha >= 1 then
            self.alpha = 1
            self:SetScript("OnUpdate", nil)
        end
        self:SetAlpha(self.alpha)
    end

    local function FadeOut_OnUpdate(self, elapsed)
        self.alpha = self.alpha - 2 * elapsed
        if self.alpha <= 0 then
            self.alpha = 0
            self:SetScript("OnUpdate", nil)
        end
        if self.alpha > 1 then
            self:SetAlpha(1)
        else
            self:SetAlpha(self.alpha)
        end
    end

    function DisplayFrameMixin:FadeIn()
        self:SetScript("OnUpdate", FadeIn_OnUpdate)
    end

    function DisplayFrameMixin:FadeOut(delay)
        if delay then
            self.alpha = 2
        end
        self:SetScript("OnUpdate", FadeOut_OnUpdate)
    end

    function DisplayFrameMixin:SetDecorInfo(decorInstanceInfo)
        -- HoverHUD 的 DisplayFrame 只作为快捷键容器，不显示 Decor 信息
        -- Decor 信息由 SubPanel 自己监听悬停事件并显示（关注点分离）
        if self.InstructionText then self.InstructionText:SetText("") end
        if self.ItemCountText then self.ItemCountText:Hide() end
        
        -- 刷新快捷键显隐
        EL:UpdateHintVisibility()
    end
end

local function Blizzard_HouseEditor_OnLoaded()
    local container = HouseEditorFrame.BasicDecorModeFrame.Instructions

    if not DisplayFrame then
        DisplayFrame = CreateFrame("Frame", nil, container, "ADT_HouseEditorInstructionTemplate")
        DisplayFrame:SetPoint("RIGHT", HouseEditorFrame.BasicDecorModeFrame, "RIGHT", -30, 0)
        DisplayFrame:SetWidth(420)
        Mixin(DisplayFrame, DisplayFrameMixin)
        -- 初始化 alpha
        DisplayFrame.alpha = 0
        DisplayFrame:SetAlpha(0)

        local SubFrame = CreateFrame("Frame", nil, DisplayFrame, "ADT_HouseEditorInstructionTemplate")
        DisplayFrame.SubFrame = SubFrame
        SubFrame:SetPoint("TOPRIGHT", DisplayFrame, "BOTTOMRIGHT", 0, 0)
        SubFrame:SetWidth(420)
        Mixin(SubFrame, DisplayFrameMixin)
        -- 默认显示 CTRL+D，兼容旧版通过 ADT.GetDuplicateKeyName() 返回文本
        SubFrame:SetHotkey(L["Duplicate"] or "Duplicate", (ADT.GetDuplicateKeyName and ADT.GetDuplicateKeyName()) or "CTRL+D")
        if SubFrame.LockStatusText then SubFrame.LockStatusText:Hide() end

        -- 追加：显示其它热键提示（Ctrl+X / C / V / S / R / 批量放置）
        DisplayFrame.HintFrames = {}
        local CTRL = CTRL_KEY_TEXT or "CTRL"
        local function addHint(prev, label, key)
            local line = CreateFrame("Frame", nil, DisplayFrame, "ADT_HouseEditorInstructionTemplate")
            line:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0)
            line:SetWidth(420)
            Mixin(line, DisplayFrameMixin)
            line:SetHotkey(label, key)
            if line.LockStatusText then line.LockStatusText:Hide() end
            table.insert(DisplayFrame.HintFrames, line)
            return line
        end
        SubFrame.isDuplicate = true
        local prev = SubFrame
        prev = addHint(prev, L["Hotkey Cut"] or "Cut", CTRL.."+X")
        prev = addHint(prev, L["Hotkey Copy"] or "Copy", CTRL.."+C")
        prev = addHint(prev, L["Hotkey Paste"] or "Paste", CTRL.."+V")
        prev = addHint(prev, L["Hotkey Store"] or "Store", CTRL.."+S")
        prev = addHint(prev, L["Hotkey Recall"] or "Recall", CTRL.."+R")
        -- 批量放置：按住 CTRL 连续放置
        prev = addHint(prev, L["Hotkey BatchPlace"] or "Batch Place", CTRL)
        -- 一键重置变换（专家模式）
        prev = addHint(prev, L["Reset Current"] or "Reset", "T")
        prev = addHint(prev, L["Reset All"] or "Reset All", CTRL.."+T")
        -- 误操作保护：锁定/解锁
        prev = addHint(prev, L["Lock/Unlock"] or "Lock", "L")

        -- 将所有“键帽”统一宽度，避免左侧文字参差不齐
        function DisplayFrame:NormalizeKeycapWidth()
            local frames = { self.SubFrame }
            for _, f in ipairs(self.HintFrames or {}) do table.insert(frames, f) end
            local maxTextWidth = 0
            for _, f in ipairs(frames) do
                if f and f.Control and f.Control.Text then
                    local w = (f.Control.Text:GetWrappedWidth() or 0)
                    if w > maxTextWidth then maxTextWidth = w end
                end
            end
            local keycapWidth = maxTextWidth + 20
            for _, f in ipairs(frames) do
                if f and f.Control and f.Control.Background and f.InstructionText then
                    f.Control.Background:SetWidth(keycapWidth)
                    f.Control:SetWidth(keycapWidth)
                    f.InstructionText:ClearAllPoints()
                    f.InstructionText:SetPoint("RIGHT", f, "RIGHT", -keycapWidth - 5, 0)
                end
            end
        end

        DisplayFrame:NormalizeKeycapWidth()
    end

    container.UnselectedInstructions = { DisplayFrame }

    if IsDecorSelected() then
        DisplayFrame:Hide()
    end
    
    -- ============== CustomizeMode 染料提示（独立容器）==============
    local cmf = HouseEditorFrame.CustomizeModeFrame
    if cmf and not EL.DyeHintFrame then
        local dyeFrame = CreateFrame("Frame", nil, cmf, "ADT_HouseEditorInstructionTemplate")
        -- 锚点往下偏移，避免与暴雪"选中装饰"提示重叠（约 -60 像素）
        dyeFrame:SetPoint("RIGHT", cmf, "RIGHT", -30, -60)
        dyeFrame:SetWidth(420)
        Mixin(dyeFrame, DisplayFrameMixin)
        dyeFrame.alpha = 1
        dyeFrame:SetAlpha(1)
        -- 降低层级，避免覆盖染料选择弹窗
        dyeFrame:SetFrameStrata("BACKGROUND")
        
        -- 获取真实键位
        local SHIFT = SHIFT_KEY_TEXT or "Shift"
        local dyeCopyKey = SHIFT.."+C"
        if ADT.Keybinds and ADT.Keybinds.GetKeyDisplayName and ADT.Keybinds.GetKeybind then
            local rawKey = ADT.Keybinds:GetKeybind("DyeCopy")
            if rawKey and rawKey ~= "" then
                dyeCopyKey = ADT.Keybinds:GetKeyDisplayName(rawKey)
            end
        end
        dyeFrame:SetHotkey(L["Hotkey Copy Dye"] or "Copy Dyes", dyeCopyKey)
        if dyeFrame.LockStatusText then dyeFrame.LockStatusText:Hide() end
        
        -- 粘贴提示
        local pasteFrame = CreateFrame("Frame", nil, cmf, "ADT_HouseEditorInstructionTemplate")
        pasteFrame:SetPoint("TOPRIGHT", dyeFrame, "BOTTOMRIGHT", 0, 0)
        pasteFrame:SetWidth(420)
        Mixin(pasteFrame, DisplayFrameMixin)
        pasteFrame:SetHotkey(L["Hotkey Paste Dye"] or "Paste Dyes", SHIFT.."+"..(L["Click"] or "Click"))
        if pasteFrame.LockStatusText then pasteFrame.LockStatusText:Hide() end
        -- 同样降低层级
        pasteFrame:SetFrameStrata("BACKGROUND")
        
        EL.DyeHintFrame = dyeFrame
        EL.DyePasteHintFrame = pasteFrame
        
        -- 统一宽度
        local function normalizeDyeKeycaps()
            local maxW = 0
            for _, f in ipairs({ dyeFrame, pasteFrame }) do
                if f and f.Control and f.Control.Text then
                    local w = f.Control.Text:GetWrappedWidth() or 0
                    if w > maxW then maxW = w end
                end
            end
            local kw = maxW + 20
            for _, f in ipairs({ dyeFrame, pasteFrame }) do
                if f and f.Control and f.Control.Background and f.InstructionText then
                    f.Control.Background:SetWidth(kw)
                    f.Control:SetWidth(kw)
                    f.InstructionText:ClearAllPoints()
                    f.InstructionText:SetPoint("RIGHT", f, "RIGHT", -kw - 5, 0)
                end
            end
        end
        normalizeDyeKeycaps()
        
        -- 根据开关决定显隐
        local function updateDyeHintVisibility()
            local enabled = ADT.GetDBValue and ADT.GetDBValue("EnableDyeCopy")
            if enabled == nil then enabled = true end
            dyeFrame:SetShown(enabled)
            pasteFrame:SetShown(enabled)
        end
        updateDyeHintVisibility()
        
        -- 监听设置变化
        if ADT.Settings and ADT.Settings.On then
            ADT.Settings.On("EnableDyeCopy", updateDyeHintVisibility)
        end
    end
end

--
-- 事件监听与核心逻辑
--
do
    EL.dynamicEvents = {
        "HOUSE_EDITOR_MODE_CHANGED",
        "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED",
        "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED",
        "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED",
    }

    function EL:SetEnabled(state)
        if state and not self.enabled then
            self.enabled = true
            if ADT and ADT.DebugPrint then ADT.DebugPrint("[Housing] Enabled") end
            for _, e in ipairs(self.dynamicEvents) do self:RegisterEvent(e) end
            self:SetScript("OnEvent", self.OnEvent)
            local blizzardAddOnName = "Blizzard_HouseEditor"
            if C_AddOns.IsAddOnLoaded(blizzardAddOnName) then
                Blizzard_HouseEditor_OnLoaded()
            else
                EventUtil.ContinueOnAddOnLoaded(blizzardAddOnName, Blizzard_HouseEditor_OnLoaded)
            end
            if DisplayFrame then DisplayFrame:Show() end
            self:LoadSettings()
        elseif (not state) and self.enabled then
            self.enabled = nil
            if ADT and ADT.DebugPrint then ADT.DebugPrint("[Housing] Disabled") end
            for _, e in ipairs(self.dynamicEvents) do self:UnregisterEvent(e) end
            self:UnregisterEvent("MODIFIER_STATE_CHANGED")
            self:SetScript("OnUpdate", nil)
            self.t = 0
            self.isUpdating = nil
            if DisplayFrame then DisplayFrame:Hide() end
        end
    end

    function EL:OnEvent(event, ...)
        if ADT and ADT.DebugPrint and event ~= "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED" then
            ADT.DebugPrint("[Housing] OnEvent: "..tostring(event))
        end
        if event == "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED" then
            self:OnHoveredTargetChanged(...)
        elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
            self:OnEditorModeChanged()
        elseif event == "MODIFIER_STATE_CHANGED" then
            self:OnModifierStateChanged(...)
        elseif event == "HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED" 
            or event == "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED" then
            self:OnSelectedTargetChanged(...)
        end
    end

    -- 误操作保护：选中事件处理（立即阻止选中锁定装饰）
    function EL:OnSelectedTargetChanged(hasSelected, targetType)
        if not hasSelected then return end
        -- 检查开关是否启用
        local protectionEnabled = ADT.GetDBValue("EnableProtection")
        if protectionEnabled == nil then protectionEnabled = true end
        if not protectionEnabled then return end
        
        -- 获取选中装饰的信息
        local info = (C_HousingBasicMode and C_HousingBasicMode.GetSelectedDecorInfo and C_HousingBasicMode.GetSelectedDecorInfo())
            or (C_HousingExpertMode and C_HousingExpertMode.GetSelectedDecorInfo and C_HousingExpertMode.GetSelectedDecorInfo())
        if not info or not info.decorGUID then return end
        
        -- 检查是否受保护
        local isProtected, protectedName = self.Protection:IsProtected(info.decorGUID, info.decorID)
        if not isProtected then return end
        
        if ADT and ADT.DebugPrint then 
            ADT.DebugPrint("[Housing] Protected decor selected, cancelling: " .. tostring(info.name)) 
        end
        
        -- 🔥 立即取消选中（绕弯实现阻止）
        pcall(function()
            if C_HousingBasicMode and C_HousingBasicMode.CancelActiveEditing then
                C_HousingBasicMode.CancelActiveEditing()
            end
            if C_HousingExpertMode and C_HousingExpertMode.CancelActiveEditing then
                C_HousingExpertMode.CancelActiveEditing()
            end
        end)

        -- 为规避暴雪编辑器在“被强制取消后”偶发的点击失效，需要做一次“看不见的解限”：
        -- 方案：瞬时切到另一种编辑模式再切回当前模式，相当于你手动点了一次“2→1”。
        -- 注意：
        -- 1) 全走官方 C_HouseEditor.ActivateHouseEditorMode，且加可用性校验；
        -- 2) 加重入保护，避免事件递归；
        -- 3) 使用下一帧异步执行，避开同帧内的状态竞争。
        local function SoftBounceEditorMode()
            if not (C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()) then
                return
            end
            if EL._modeBounceInProgress then return end
            EL._modeBounceInProgress = true

            local currentMode = (C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode())
            local basicMode  = Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.BasicDecor
            local expertMode = Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.ExpertDecor

            -- 选择一个可用的“备用模式”以完成往返切换
            local altMode
            if currentMode == basicMode then
                altMode = expertMode
            else
                altMode = basicMode
            end

            local function modeIsAvailable(mode)
                if not (mode and C_HouseEditor.GetHouseEditorModeAvailability) then return false end
                local r = C_HouseEditor.GetHouseEditorModeAvailability(mode)
                return r == Enum.HousingResult.Success
            end

            C_Timer.After(0, function()
                if altMode and modeIsAvailable(altMode) then
                    pcall(function() C_HouseEditor.ActivateHouseEditorMode(altMode) end)
                    C_Timer.After(0, function()
                        pcall(function()
                            if currentMode then C_HouseEditor.ActivateHouseEditorMode(currentMode) end
                        end)
                        EL._modeBounceInProgress = nil
                    end)
                else
                    -- 退化处理：至少重新激活当前模式一次
                    pcall(function()
                        if currentMode then C_HouseEditor.ActivateHouseEditorMode(currentMode) end
                    end)
                    EL._modeBounceInProgress = nil
                end
            end)
        end

        SoftBounceEditorMode()
        
        -- 播放警告音效
        PlaySound(SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST or 857)
        
        -- 显示警告通知
        if ADT and ADT.Notify then
            ADT.Notify("|A:BonusChest-Lock:16:16|a " .. string.format(L["Protected cannot select %s"], (info.name or protectedName or L["Unknown Decor"])), "warning")
        end
    end

    function EL:OnHoveredTargetChanged(hasHoveredTarget, targetType)
        if hasHoveredTarget then
            if not self.isUpdating then
                self.t = 0
                self.isUpdating = true
                self:SetScript("OnUpdate", self.OnUpdate)
                self:UnregisterEvent("MODIFIER_STATE_CHANGED")
            end
            self.t = 0
            self.isUpdating = true
            self.lastHoveredTargetType = targetType
        else
            if self.decorInstanceInfo then
                self.decorInstanceInfo = nil
            end
            if DisplayFrame then
                DisplayFrame:FadeOut(0.5)
            end
        end
    end

    function EL:OnUpdate(elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t > 0.1 then
            self.t = 0
            self.isUpdating = nil
            self:SetScript("OnUpdate", nil)
            self:ProcessHoveredDecor()
        end
    end

    function EL:ProcessHoveredDecor()
        self.decorInstanceInfo = nil
        if IsHoveringDecor() then
            local info = GetHoveredDecorInfo()
            if info then
                -- 仅在使用“修饰键触发”模式时监听（Ctrl/Alt 直接松开触发）。
                if self.dupeEnabled and self.dupeKey then
                    self:RegisterEvent("MODIFIER_STATE_CHANGED")
                end
                self.decorInstanceInfo = info
                if DisplayFrame then
                    DisplayFrame:SetDecorInfo(info)
                    DisplayFrame:FadeIn()
                end
                return true
            end
        end
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        if DisplayFrame then
            DisplayFrame:FadeOut()
        end
    end

    function EL:GetHoveredDecorEntryID()
        if not self.decorInstanceInfo then return end
        local decorID = self.decorInstanceInfo.decorID
        if decorID then
            local entryInfo = GetCatalogDecorInfo(decorID)
            return entryInfo and entryInfo.entryID
        end
    end

    function EL:GetHoveredDecorRecordIDAndName()
        if not IsHoveringDecor() then return end
        local info = GetHoveredDecorInfo()
        if info and info.decorID then
            return info.decorID, info.name, info.iconTexture or info.iconAtlas
        end
    end

    function EL:GetSelectedDecorRecordIDAndName()
        -- 尝试多源：不同模块的 GetSelectedDecorInfo 名称略有差异
        local info
        if C_HousingBasicMode and C_HousingBasicMode.GetSelectedDecorInfo then
            info = C_HousingBasicMode.GetSelectedDecorInfo()
        end
        if (not info or not info.decorID) and C_HousingExpertMode and C_HousingExpertMode.GetSelectedDecorInfo then
            info = C_HousingExpertMode.GetSelectedDecorInfo()
        end
        if (not info or not info.decorID) and C_HousingCustomizeMode and C_HousingCustomizeMode.GetSelectedDecorInfo then
            info = C_HousingCustomizeMode.GetSelectedDecorInfo()
        end
        if info and info.decorID then
            return info.decorID, info.name, info.iconTexture or info.iconAtlas
        end
    end

    -- StartPlacingByRecordID 提升为顶层函数，避免局部作用域问题

    -- 重构：TryDuplicateItem 使用单一权威入口，确保室内外限制生效
    function EL:TryDuplicateItem()
        if not self.dupeEnabled then return end
        if not IsHouseEditorActive() then return end
        if IsDecorSelected() then return end

        -- 获取悬停装饰的 recordID（而非 entryID），使用 StartPlacingByRecordID 单一权威
        local recordID, _, _ = self:GetHoveredDecorRecordIDAndName()
        if not recordID then return end

        -- 预算检查已在 StartPlacingByRecordID 中处理，室内外限制也已含其中
        self:StartPlacingByRecordID(recordID)
    end


    function EL:OnEditorModeChanged()
        -- 保留扩展点
    end

    function EL:OnModifierStateChanged(key, down)
        if key == self.dupeKey and down == 0 then
            self:TryDuplicateItem()
        end
    end

    EL.DuplicateKeyOptions = {
        { name = CTRL_KEY_TEXT, key = "LCTRL" },
        { name = ALT_KEY_TEXT,  key = "LALT"  },
        -- 3: Ctrl+D（通过覆盖绑定触发，不走 MODIFIER_STATE_CHANGED）
        { name = (CTRL_KEY_TEXT and (CTRL_KEY_TEXT.."+D")) or "CTRL+D", key = nil },
    }

    function EL:LoadSettings()
        if ADT and ADT.DebugPrint then ADT.DebugPrint("[Housing] LoadSettings") end
        local dupeEnabled = ADT.GetDBBool("EnableDupe")
        local dupeKeyIndex = ADT.GetDBValue("DuplicateKey") or 3
        self.dupeEnabled = dupeEnabled

        -- 悬停高亮开关（默认开启）
        local highlightEnabled = ADT.GetDBValue("EnableHoverHighlight")
        if highlightEnabled == nil then
            highlightEnabled = true  -- 默认开启
        end
        self.highlightEnabled = highlightEnabled

        if type(dupeKeyIndex) ~= "number" or not self.DuplicateKeyOptions[dupeKeyIndex] then
            dupeKeyIndex = 3
        end

        self.currentDupeKeyName = self.DuplicateKeyOptions[dupeKeyIndex].name
        -- 仅当选择 Ctrl/Alt 时设置 dupeKey；选择 Ctrl+D 时为 nil（不监听修饰键变化）。
        self.dupeKey = self.DuplicateKeyOptions[dupeKeyIndex].key

        if DisplayFrame and DisplayFrame.SubFrame then
            DisplayFrame.SubFrame:SetHotkey(L["Duplicate"] or "Duplicate", ADT.GetDuplicateKeyName())
            if DisplayFrame.NormalizeKeycapWidth then DisplayFrame:NormalizeKeycapWidth() end
            if not dupeEnabled then
                DisplayFrame.SubFrame:Hide()
            end
        end
        
        -- 初始加载时也更新提示可见性
        self:UpdateHintVisibility()
    end
    
    -- 根据设置更新各提示行的显隐（并自动重新排列位置，避免空隙）
    function EL:UpdateHintVisibility()
        if not DisplayFrame then return end
        if ADT and ADT.DebugPrint then
            ADT.DebugPrint(string.format("[Housing] UpdateHintVisibility: Dupe=%s, Cut=%s, Copy=%s, Paste=%s, Batch=%s",
                tostring(ADT.GetDBValue("EnableDupe")), tostring(ADT.GetDBValue("EnableCut")), tostring(ADT.GetDBValue("EnableCopy")), tostring(ADT.GetDBValue("EnablePaste")), tostring(ADT.GetDBValue("EnableBatchPlace"))))
        end
        
        -- 收集所有需要根据设置显隐的帧（按顺序）
        -- SubFrame = Duplicate (CTRL+D)
        -- HintFrames[1] = Cut (CTRL+X)
        -- HintFrames[2] = Copy (CTRL+C)
        -- HintFrames[3] = Paste (CTRL+V)
        -- HintFrames[4] = Store (CTRL+S) - 始终显示
        -- HintFrames[5] = Recall (CTRL+R) - 始终显示
        -- HintFrames[6] = BatchPlace (CTRL) - 由 EnableBatchPlace 控制
        
        local allFrames = {}
        local visibilityConfig = {}
        
        -- SubFrame (Duplicate)
        if DisplayFrame.SubFrame then
            table.insert(allFrames, DisplayFrame.SubFrame)
            local dupeEnabled = ADT.GetDBValue("EnableDupe")
            if dupeEnabled == nil then dupeEnabled = true end
            table.insert(visibilityConfig, dupeEnabled)
        end
        
        -- HintFrames
        if DisplayFrame.HintFrames then
            local hintSettings = {
                [1] = { dbKey = "EnableCut", default = true },   -- Cut (CTRL+X)
                [2] = { dbKey = "EnableCopy", default = true },  -- Copy (CTRL+C)
                [3] = { dbKey = "EnablePaste", default = true }, -- Paste (CTRL+V)
                [4] = nil,  -- Store (CTRL+S) - 始终显示
                [5] = nil,  -- Recall (CTRL+R) - 始终显示
                [6] = { dbKey = "EnableBatchPlace", default = false }, -- Batch Place (CTRL)
                [7] = { dbKey = "EnableResetT", default = true },      -- Reset (T)
                [8] = { dbKey = "EnableResetAll", default = true },    -- Reset All (CTRL+T)
                [9] = { dbKey = "EnableLock", default = true },        -- Lock (L)
            }
            for i, frame in ipairs(DisplayFrame.HintFrames) do
                table.insert(allFrames, frame)
                local cfg = hintSettings[i]
                if cfg then
                    local enabled = ADT.GetDBValue(cfg.dbKey)
                    if enabled == nil then enabled = cfg.default end
                    table.insert(visibilityConfig, enabled)
                else
                    -- 没有开关的帧始终显示
                    table.insert(visibilityConfig, true)
                end
            end
        end
        
        -- 动态重新定位：只显示启用的帧，并链式排列（无空隙）
        local prevVisible = DisplayFrame -- 第一个可见帧锚定到 DisplayFrame
        for i, frame in ipairs(allFrames) do
            local visible = visibilityConfig[i]
            frame:SetShown(visible)
            if visible then
                frame:ClearAllPoints()
                frame:SetPoint("TOPRIGHT", prevVisible, "BOTTOMRIGHT", 0, 0)
                prevVisible = frame
            end
        end
    end
end

-- 语言切换时，刷新右侧提示行的本地化文本
function EL:OnLocaleChanged()
    if not DisplayFrame then return end
    local L = ADT and ADT.L or {}
    local CTRL = CTRL_KEY_TEXT or "CTRL"
    -- 顶部重复提示（键帽文本可能因设置不同而变）
    if DisplayFrame.SubFrame then
        local keyName = (ADT.GetDuplicateKeyName and ADT.GetDuplicateKeyName()) or (CTRL.."+D")
        DisplayFrame.SubFrame:SetHotkey(L["Duplicate"] or "Duplicate", keyName)
    end
    -- 其他提示行
    local map = {
        [1] = L["Hotkey Cut"]    or "Cut",
        [2] = L["Hotkey Copy"]   or "Copy",
        [3] = L["Hotkey Paste"]  or "Paste",
        [4] = L["Hotkey Store"]  or "Store",
        [5] = L["Hotkey Recall"] or "Recall",
        [6] = L["Hotkey BatchPlace"] or "Batch Place",
        [7] = L["Reset Current"] or "Reset",
        [8] = L["Reset All"] or "Reset All",
        [9] = L["Lock/Unlock"] or "Lock",
    }
    local keycaps = {
        [1] = CTRL.."+X",
        [2] = CTRL.."+C",
        [3] = CTRL.."+V",
        [4] = CTRL.."+S",
        [5] = CTRL.."+R",
        [6] = CTRL,
        [7] = "T",
        [8] = CTRL.."+T",
        [9] = "L",
    }
    if DisplayFrame.HintFrames then
        for i, line in ipairs(DisplayFrame.HintFrames) do
            if line and line.SetHotkey and map[i] and keycaps[i] then
                line:SetHotkey(map[i], keycaps[i])
            end
        end
    end
    if DisplayFrame.NormalizeKeycapWidth then
        DisplayFrame:NormalizeKeycapWidth()
    end
    -- 重新应用可见性（用户开关可能影响）
    if self.UpdateHintVisibility then self:UpdateHintVisibility() end
end

--
-- 绑定辅助：复制 / 粘贴 / 剪切
--
function EL:Binding_Copy()
    -- 检查开关
    local enabled = ADT.GetDBValue("EnableCopy")
    if enabled == nil then enabled = true end
    if not enabled then return end
    
    if not IsHouseEditorActive() then return end
    -- 优先悬停
    local rid, name, icon = self:GetHoveredDecorRecordIDAndName()
    if not rid then
        rid, name, icon = self:GetSelectedDecorRecordIDAndName()
    end
    if not rid then
        if ADT and ADT.Notify then ADT.Notify(L["No decor to copy"], 'error') end
        return
    end
    self:SetClipboard(rid, name, icon)
    if name then
        if ADT and ADT.Notify then ADT.Notify((L["ADT: Decor %s"]:format(name)) .. " " .. L["Copied to clipboard"], 'success') end
    else
        if ADT and ADT.Notify then ADT.Notify(L["Copied to clipboard"], 'success') end
    end
end

function EL:Binding_Paste()
    -- 检查开关
    local enabled = ADT.GetDBValue("EnablePaste")
    if enabled == nil then enabled = true end
    if not enabled then return end
    
    if not IsHouseEditorActive() then return end
    local clip = self:GetClipboard()
    if not clip or not clip.decorID then
        if ADT and ADT.Notify then ADT.Notify(L["Clipboard empty, cannot paste"], 'error') end
        return
    end
    local ok = self:StartPlacingByRecordID(clip.decorID)
    if not ok then
        if ADT and ADT.Notify then ADT.Notify(L["Cannot start placing"], 'error') end
    end
end

function EL:RemoveSelectedDecor()
    -- 以最兼容的方式调用移除：不同模式下提供了不同入口（单一权威）
    local removed
    if C_HousingCleanupMode and C_HousingCleanupMode.RemoveSelectedDecor then
        removed = select(2, pcall(C_HousingCleanupMode.RemoveSelectedDecor)) ~= nil or removed
        if removed == nil then removed = true end -- 多数 API 无返回值
    end
    if not removed and C_HousingDecor and C_HousingDecor.RemoveSelectedDecor then
        removed = select(2, pcall(C_HousingDecor.RemoveSelectedDecor)) ~= nil or removed
        if removed == nil then removed = true end
    end
    if not removed and C_HousingExpertMode and C_HousingExpertMode.RemoveSelectedDecor then
        removed = select(2, pcall(C_HousingExpertMode.RemoveSelectedDecor)) ~= nil or removed
        if removed == nil then removed = true end
    end
    if not removed and C_HousingBasicMode and C_HousingBasicMode.RemoveSelectedDecor then
        removed = select(2, pcall(C_HousingBasicMode.RemoveSelectedDecor)) ~= nil or removed
        if removed == nil then removed = true end
    end
    return removed
end

function EL:Binding_Cut()
    -- 检查开关
    local enabled = ADT.GetDBValue("EnableCut")
    if enabled == nil then enabled = true end
    if not enabled then return end
    
    if not IsHouseEditorActive() then return end
    -- 只能剪切“已选中”的装饰；无法直接操作“悬停”对象（选择API受保护）
    local rid, name, icon = self:GetSelectedDecorRecordIDAndName()
    if not rid then
        -- 允许在悬停时先记录剪切板，提示用户点一下选中再按一次
        local hrid, hname, hicon = self:GetHoveredDecorRecordIDAndName()
        if hrid then
            self:SetClipboard(hrid, hname, hicon)
            if ADT and ADT.Notify then ADT.Notify(L["Saved to clipboard tip"], 'info') end
        else
            if ADT and ADT.Notify then ADT.Notify(L["Select then press Ctrl+X"], 'info') end
        end
        return
    end
    self:SetClipboard(rid, name, icon)
    local ok = self:RemoveSelectedDecor()
    if ok then
        local tip = name and (L["Removed %s and saved to clipboard"]:format(name)) or L["Removed and saved to clipboard"]
        if ADT and ADT.Notify then ADT.Notify(tip, 'success') end
    else
        if ADT and ADT.Notify then ADT.Notify(L["Cannot remove decor"], 'error') end
    end
end

--
-- 一键重置变换（T / Ctrl+T）
--
function EL:ResetCurrentSubmode()
    -- 检查“启用 T 重置默认属性”开关（默认启用）
    do
        local enabled = ADT.GetDBValue("EnableResetT")
        if enabled == nil then enabled = true end
        if not enabled then return end
    end
    if not IsHouseEditorActive() then return end
    -- 仅在专家模式下可用
    local mode = C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode()
    if mode ~= Enum.HouseEditorMode.ExpertDecor then
        if ADT and ADT.Notify then
            ADT.Notify(L["Reset requires Expert Mode"], "warning")
        end
        return
    end
    -- 必须有选中的装饰
    if not (C_HousingExpertMode and C_HousingExpertMode.IsDecorSelected and C_HousingExpertMode.IsDecorSelected()) then
        if ADT and ADT.Notify then
            ADT.Notify(L["No decor selected"], "warning")
        end
        return
    end
    -- 仅重置当前子模式（activeSubmodeOnly = true）
    if C_HousingExpertMode.ResetPrecisionChanges then
        C_HousingExpertMode.ResetPrecisionChanges(true)
        PlaySound(SOUNDKIT.HOUSING_EXPERTMODE_RESET_CHANGES or 220067)
        if ADT and ADT.Notify then
            ADT.Notify(L["Current transform reset"], "success")
        end
    end
end

function EL:ResetAllTransforms()
    -- 检查“启用 Ctrl+T 全部重置”开关（默认启用）
    do
        local enabled = ADT.GetDBValue("EnableResetAll")
        if enabled == nil then enabled = true end
        if not enabled then return end
    end
    if not IsHouseEditorActive() then return end
    local mode = C_HouseEditor.GetActiveHouseEditorMode and C_HouseEditor.GetActiveHouseEditorMode()
    if mode ~= Enum.HouseEditorMode.ExpertDecor then
        if ADT and ADT.Notify then
            ADT.Notify(L["Reset requires Expert Mode"], "warning")
        end
        return
    end
    if not (C_HousingExpertMode and C_HousingExpertMode.IsDecorSelected and C_HousingExpertMode.IsDecorSelected()) then
        if ADT and ADT.Notify then
            ADT.Notify(L["No decor selected"], "warning")
        end
        return
    end
    -- 全部重置（activeSubmodeOnly = false）
    if C_HousingExpertMode.ResetPrecisionChanges then
        C_HousingExpertMode.ResetPrecisionChanges(false)
        PlaySound(SOUNDKIT.HOUSING_EXPERTMODE_RESET_CHANGES or 220067)
        if ADT and ADT.Notify then
            ADT.Notify(L["All transforms reset"], "success")
        end
    end
end

-- 启用模块：加载后默认打开（只做这一项功能）
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function()
    ADT.Housing:SetEnabled(true)
    if ADT and ADT.Housing and ADT.Housing.RefreshOverrides then
        ADT.Housing:RefreshOverrides()
    end
    bootstrap:UnregisterEvent("PLAYER_LOGIN")
end)

--
-- 在编辑模式下“强制覆盖”按键（合法 API）
-- 使用 SetOverrideBindingClick(owner, true, key, buttonName) 以优先级覆盖
-- 仅在房屋编辑器激活时生效，离开时清理，避免污染全局键位。
do
    local owner
    local btnTempStore, btnTempRecall
    local btnToggleUI
    local btnDuplicate
    -- 住宅剪切板：复制/粘贴/剪切（强制覆盖）
    local btnCopy, btnPaste, btnCut
    -- 一键重置变换（T / CTRL-T）
    local btnResetSubmode, btnResetAll
    -- 高级编辑：虚拟多选 按键按钮（不做强制覆盖，仅提供绑定接口）
    local btnAdvToggle, btnAdvToggleHovered, btnAdvClear, btnAdvAnchorHover, btnAdvAnchorSelected

    local function EnsureOwner()
        if owner then return end
        owner = CreateFrame("Frame", "ADT_HousingOverrideOwner", UIParent)
        -- 创建“临时板”点击代理按钮（仅两项）
        btnTempStore = CreateFrame("Button", "ADT_HousingOverride_TempStore", owner, "SecureActionButtonTemplate")
        btnTempRecall = CreateFrame("Button", "ADT_HousingOverride_TempRecall", owner, "SecureActionButtonTemplate")

        -- 创建 复制/粘贴/剪切 的点击代理按钮（强制覆盖键位：CTRL-C / CTRL-V / CTRL-X）
        btnCopy  = CreateFrame("Button", "ADT_HousingOverride_Copy", owner, "SecureActionButtonTemplate")
        btnPaste = CreateFrame("Button", "ADT_HousingOverride_Paste", owner, "SecureActionButtonTemplate")
        btnCut   = CreateFrame("Button", "ADT_HousingOverride_Cut", owner, "SecureActionButtonTemplate")
        -- 创建“复制同款（Duplicate）”点击代理按钮（CTRL-D）
        btnDuplicate = CreateFrame("Button", "ADT_HousingOverride_Duplicate", owner, "SecureActionButtonTemplate")

        -- 设置面板切换（/adt 同效）
        btnToggleUI = CreateFrame("Button", "ADT_HousingOverride_ToggleUI", owner, "SecureActionButtonTemplate")

        -- 高级编辑按钮（调用 Bindings.lua 中的全局函数）
        btnAdvToggle = CreateFrame("Button", "ADT_HousingOverride_AdvToggle", owner, "SecureActionButtonTemplate")
        btnAdvToggleHovered = CreateFrame("Button", "ADT_HousingOverride_AdvToggleHovered", owner, "SecureActionButtonTemplate")
        btnAdvClear = CreateFrame("Button", "ADT_HousingOverride_AdvClear", owner, "SecureActionButtonTemplate")
        btnAdvAnchorHover = CreateFrame("Button", "ADT_HousingOverride_AdvAnchorHover", owner, "SecureActionButtonTemplate")
        btnAdvAnchorSelected = CreateFrame("Button", "ADT_HousingOverride_AdvAnchorSelected", owner, "SecureActionButtonTemplate")

        -- 临时板调用
        btnTempStore:SetScript("OnClick", function() if _G.ADT_Temp_StoreSelected then ADT_Temp_StoreSelected() end end)
        btnTempRecall:SetScript("OnClick", function() if _G.ADT_Temp_RecallTop then ADT_Temp_RecallTop() end end)

        -- 设置面板切换（调用 UI.lua 中的集中逻辑）
        btnToggleUI:SetScript("OnClick", function()
            if ADT and ADT.ToggleMainUI then ADT.ToggleMainUI() end
        end)

        -- 复制/粘贴/剪切 调用（调用当前文件中的实现）
        btnCopy:SetScript("OnClick", function()
            if ADT and ADT.Housing and ADT.Housing.Binding_Copy then ADT.Housing:Binding_Copy() end
        end)
        btnPaste:SetScript("OnClick", function()
            if ADT and ADT.Housing and ADT.Housing.Binding_Paste then ADT.Housing:Binding_Paste() end
        end)
        btnCut:SetScript("OnClick", function()
            if ADT and ADT.Housing and ADT.Housing.Binding_Cut then ADT.Housing:Binding_Cut() end
        end)
        -- Duplicate（同款复制并开始放置）
        btnDuplicate:SetScript("OnClick", function()
            if ADT and ADT.Housing and ADT.Housing.TryDuplicateItem then ADT.Housing:TryDuplicateItem() end
        end)

        -- 绑定高级编辑调用
        btnAdvToggle:SetScript("OnClick", function() if _G.ADT_Adv_Toggle then ADT_Adv_Toggle() end end)
        btnAdvToggleHovered:SetScript("OnClick", function() if _G.ADT_Adv_ToggleHovered then ADT_Adv_ToggleHovered() end end)
        btnAdvClear:SetScript("OnClick", function() if _G.ADT_Adv_ClearSelection then ADT_Adv_ClearSelection() end end)
        btnAdvAnchorHover:SetScript("OnClick", function() if _G.ADT_Adv_SetAnchor_Hovered then ADT_Adv_SetAnchor_Hovered() end end)
        btnAdvAnchorSelected:SetScript("OnClick", function() if _G.ADT_Adv_SetAnchor_Selected then ADT_Adv_SetAnchor_Selected() end end)

        -- 一键重置变换按钮
        btnResetSubmode = CreateFrame("Button", "ADT_HousingOverride_ResetSub", owner, "SecureActionButtonTemplate")
        btnResetAll = CreateFrame("Button", "ADT_HousingOverride_ResetAll", owner, "SecureActionButtonTemplate")
        btnResetSubmode:SetScript("OnClick", function()
            if ADT and ADT.Housing and ADT.Housing.ResetCurrentSubmode then ADT.Housing:ResetCurrentSubmode() end
        end)
        btnResetAll:SetScript("OnClick", function()
            if ADT and ADT.Housing and ADT.Housing.ResetAllTransforms then ADT.Housing:ResetAllTransforms() end
        end)

        -- 误操作保护按钮（L 键锁定/解锁）
        btnToggleLock = CreateFrame("Button", "ADT_HousingOverride_ToggleLock", owner, "SecureActionButtonTemplate")
        btnToggleLock:SetScript("OnClick", function()
            if ADT and ADT.DebugPrint then ADT.DebugPrint("[Housing] btnToggleLock OnClick triggered") end
            if ADT and ADT.Housing and ADT.Housing.ToggleProtection then ADT.Housing:ToggleProtection() end
        end)
    end

    local OVERRIDE_KEYS = {
        -- 仅强制覆盖这六大类：S/R/X/C/V/D + Q
        -- 临时板：存入/取出
        { key = "CTRL-S", button = function() return btnTempStore end },
        { key = "CTRL-R", button = function() return btnTempRecall end },
        -- 住宅剪切板：复制/粘贴/剪切
        { key = "CTRL-C", button = function() return btnCopy end },
        { key = "CTRL-V", button = function() return btnPaste end },
        { key = "CTRL-X", button = function() return btnCut end },
        -- 住宅：悬停复制同款（新的默认：CTRL-D）
        { key = "CTRL-D", button = function() return btnDuplicate end },
        -- 设置面板：开关（等价 /adt）
        { key = "CTRL-Q", button = function() return btnToggleUI end },
        -- 一键重置变换
        { key = "T", button = function() return btnResetSubmode end },
        { key = "CTRL-T", button = function() return btnResetAll end },
        -- 误操作保护：锁定/解锁
        { key = "L", button = function() return btnToggleLock end },
    }

    function EL:ClearOverrides()
        if not owner then return end
        ClearOverrideBindings(owner)
    end

    function EL:ApplyOverrides()
        EnsureOwner()
        ClearOverrideBindings(owner)
        -- 注意：优先级覆盖，确保高于默认与其他非优先覆盖
        for _, cfg in ipairs(OVERRIDE_KEYS) do
            local btn = cfg.button()
            local allowed = true
            if cfg.key == "T" then
                local en = ADT.GetDBValue("EnableResetT")
                if en == nil then en = true end
                allowed = en
            elseif cfg.key == "CTRL-T" then
                local en2 = ADT.GetDBValue("EnableResetAll")
                if en2 == nil then en2 = true end
                allowed = en2
            elseif cfg.key == "L" then
                local en3 = ADT.GetDBValue("EnableLock")
                if en3 == nil then en3 = true end
                allowed = en3
            end
            if btn and allowed then
                SetOverrideBindingClick(owner, true, cfg.key, btn:GetName())
            end
        end
    end

    function EL:RefreshOverrides()
        -- 仅在房屋编辑器激活时启用
        local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
        if isActive then
            -- 下一帧应用，避免与暴雪自身在同一事件中设置的覆盖发生顺序竞争
            C_Timer.After(0, function() if ADT and ADT.Housing then ADT.Housing:ApplyOverrides() end end)
        else
            self:ClearOverrides()
        end
    end

    -- 接管编辑器模式变化
    hooksecurefunc(EL, "OnEditorModeChanged", function()
        EL:RefreshOverrides()
    end)

    -- 其它刷新点：由 EL:OnEditorModeChanged() 的 hook 触发
end
