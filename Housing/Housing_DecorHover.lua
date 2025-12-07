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

    function DisplayFrameMixin:OnLoad()
        self.alpha = 0
        self:SetAlpha(0)

        self.Control.Icon:SetAtlas("housing-hotkey-icon-leftclick")
        self.Control.Icon:Show()
        self.InstructionText:SetText(HOUSING_DECOR_SELECT_INSTRUCTION)
        self.InstructionText:SetFontObject("GameFontHighlightMedium")
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
        self.InstructionText:SetText(decorInstanceInfo.name)
        local decorID = decorInstanceInfo.decorID
        local entryInfo = GetCatalogDecorInfo(decorID)
        local stored = 0
        if entryInfo then
            stored = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
        end
        self.ItemCountText:SetText(stored)
        self.ItemCountText:SetShown(stored > 0)
        self.SubFrame:SetShown(EL.dupeEnabled and stored > 0)
    end
end

local function Blizzard_HouseEditor_OnLoaded()
    local container = HouseEditorFrame.BasicDecorModeFrame.Instructions
    for _, v in ipairs(container.UnselectedInstructions) do
        v:Hide()
    end
    container.UnselectedInstructions = {}

    if not DisplayFrame then
        DisplayFrame = CreateFrame("Frame", nil, container, "ADT_HouseEditorInstructionTemplate")
        DisplayFrame:SetPoint("RIGHT", HouseEditorFrame.BasicDecorModeFrame, "RIGHT", -30, 0)
        DisplayFrame:SetWidth(420)
        Mixin(DisplayFrame, DisplayFrameMixin)
        DisplayFrame:OnLoad()

        local SubFrame = CreateFrame("Frame", nil, DisplayFrame, "ADT_HouseEditorInstructionTemplate")
        DisplayFrame.SubFrame = SubFrame
        SubFrame:SetPoint("TOPRIGHT", DisplayFrame, "BOTTOMRIGHT", 0, 0)
        SubFrame:SetWidth(420)
        Mixin(SubFrame, DisplayFrameMixin)
        SubFrame:SetHotkey(L["Duplicate"] or "Duplicate", (ADT.GetDuplicateKeyName and ADT.GetDuplicateKeyName()) or "ALT")
        if SubFrame.LockStatusText then SubFrame.LockStatusText:Hide() end
    end

    container.UnselectedInstructions = { DisplayFrame }

    if IsDecorSelected() then
        DisplayFrame:Hide()
    end
end

--
-- 事件监听与核心逻辑
--
do
    EL.dynamicEvents = {
        "HOUSE_EDITOR_MODE_CHANGED",
        "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED",
    }

    function EL:SetEnabled(state)
        if state and not self.enabled then
            self.enabled = true
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
            for _, e in ipairs(self.dynamicEvents) do self:UnregisterEvent(e) end
            self:UnregisterEvent("MODIFIER_STATE_CHANGED")
            self:SetScript("OnUpdate", nil)
            self.t = 0
            self.isUpdating = nil
            if DisplayFrame then DisplayFrame:Hide() end
        end
    end

    function EL:OnEvent(event, ...)
        if event == "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED" then
            self:OnHoveredTargetChanged(...)
        elseif event == "HOUSE_EDITOR_MODE_CHANGED" then
            self:OnEditorModeChanged()
        elseif event == "MODIFIER_STATE_CHANGED" then
            self:OnModifierStateChanged(...)
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
                if self.dupeEnabled then
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

    function EL:TryDuplicateItem()
        if not self.dupeEnabled then return end
        if not IsHouseEditorActive() then return end
        if IsDecorSelected() then return end

        local entryID = self:GetHoveredDecorEntryID()
        if not entryID then return end

        local decorPlaced = C_HousingDecor.GetSpentPlacementBudget()
        local maxDecor = C_HousingDecor.GetMaxPlacementBudget()
        local hasMaxDecor = C_HousingDecor.HasMaxPlacementBudget()
        if hasMaxDecor and decorPlaced >= maxDecor then
            return
        end

        C_HousingBasicMode.StartPlacingNewDecor(entryID)
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
    }

    function EL:LoadSettings()
        local dupeEnabled = ADT.GetDBBool("EnableDupe")
        local dupeKeyIndex = ADT.GetDBValue("DuplicateKey") or 2
        self.dupeEnabled = dupeEnabled

        -- 悬停高亮开关（默认开启）
        local highlightEnabled = ADT.GetDBValue("EnableHoverHighlight")
        if highlightEnabled == nil then
            highlightEnabled = true  -- 默认开启
        end
        self.highlightEnabled = highlightEnabled

        if type(dupeKeyIndex) ~= "number" or not self.DuplicateKeyOptions[dupeKeyIndex] then
            dupeKeyIndex = 2
        end

        self.currentDupeKeyName = self.DuplicateKeyOptions[dupeKeyIndex].name
        self.dupeKey = self.DuplicateKeyOptions[dupeKeyIndex].key

        if DisplayFrame and DisplayFrame.SubFrame then
            DisplayFrame.SubFrame:SetHotkey(L["Duplicate"] or "Duplicate", ADT.GetDuplicateKeyName())
            if not dupeEnabled then
                DisplayFrame.SubFrame:Hide()
            end
        end
    end
end

--
-- 绑定辅助：复制 / 粘贴 / 剪切
--
function EL:Binding_Copy()
    if not IsHouseEditorActive() then return end
    -- 优先悬停
    local rid, name, icon = self:GetHoveredDecorRecordIDAndName()
    if not rid then
        rid, name, icon = self:GetSelectedDecorRecordIDAndName()
    end
    if not rid then
        if ADT and ADT.Notify then ADT.Notify("未检测到悬停或选中的装饰，无法复制", 'error') end
        return
    end
    self:SetClipboard(rid, name, icon)
    if name then
        if ADT and ADT.Notify then ADT.Notify(((L["ADT: Decor %s"] or "装饰 %s"):format(name)) .. " 已复制到剪切板", 'success') end
    else
        if ADT and ADT.Notify then ADT.Notify("装饰已复制到剪切板", 'success') end
    end
end

function EL:Binding_Paste()
    if not IsHouseEditorActive() then return end
    local clip = self:GetClipboard()
    if not clip or not clip.decorID then
        if ADT and ADT.Notify then ADT.Notify("剪切板为空，无法粘贴", 'error') end
        return
    end
    local ok = self:StartPlacingByRecordID(clip.decorID)
    if not ok then
        if ADT and ADT.Notify then ADT.Notify("无法进入放置（可能库存为 0 或已达上限）", 'error') end
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
    if not IsHouseEditorActive() then return end
    -- 只能剪切“已选中”的装饰；无法直接操作“悬停”对象（选择API受保护）
    local rid, name, icon = self:GetSelectedDecorRecordIDAndName()
    if not rid then
        -- 允许在悬停时先记录剪切板，提示用户点一下选中再按一次
        local hrid, hname, hicon = self:GetHoveredDecorRecordIDAndName()
        if hrid then
            self:SetClipboard(hrid, hname, hicon)
            if ADT and ADT.Notify then ADT.Notify("已记录剪切板；请先选中该装饰后再按 Ctrl+X 完成移除", 'info') end
        else
            if ADT and ADT.Notify then ADT.Notify("请先选中要移除的装饰，再按 Ctrl+X", 'info') end
        end
        return
    end
    self:SetClipboard(rid, name, icon)
    local ok = self:RemoveSelectedDecor()
    if ok then
        local tip = name and (((L["ADT: Decor %s"] or "装饰 %s"):format(name)) .. " 已移除，已加入剪切板") or "已移除并加入剪切板"
        if ADT and ADT.Notify then ADT.Notify(tip, 'success') end
    else
        if ADT and ADT.Notify then ADT.Notify("无法移除该装饰（可能不在可移除模式或未被选中）", 'error') end
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
    -- 住宅剪切板：复制/粘贴/剪切（强制覆盖）
    local btnCopy, btnPaste, btnCut
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

        -- 高级编辑按钮（调用 Bindings.lua 中的全局函数）
        btnAdvToggle = CreateFrame("Button", "ADT_HousingOverride_AdvToggle", owner, "SecureActionButtonTemplate")
        btnAdvToggleHovered = CreateFrame("Button", "ADT_HousingOverride_AdvToggleHovered", owner, "SecureActionButtonTemplate")
        btnAdvClear = CreateFrame("Button", "ADT_HousingOverride_AdvClear", owner, "SecureActionButtonTemplate")
        btnAdvAnchorHover = CreateFrame("Button", "ADT_HousingOverride_AdvAnchorHover", owner, "SecureActionButtonTemplate")
        btnAdvAnchorSelected = CreateFrame("Button", "ADT_HousingOverride_AdvAnchorSelected", owner, "SecureActionButtonTemplate")

        -- 临时板调用
        btnTempStore:SetScript("OnClick", function() if _G.ADT_Temp_StoreSelected then ADT_Temp_StoreSelected() end end)
        btnTempRecall:SetScript("OnClick", function() if _G.ADT_Temp_RecallTop then ADT_Temp_RecallTop() end end)

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

        -- 绑定高级编辑调用
        btnAdvToggle:SetScript("OnClick", function() if _G.ADT_Adv_Toggle then ADT_Adv_Toggle() end end)
        btnAdvToggleHovered:SetScript("OnClick", function() if _G.ADT_Adv_ToggleHovered then ADT_Adv_ToggleHovered() end end)
        btnAdvClear:SetScript("OnClick", function() if _G.ADT_Adv_ClearSelection then ADT_Adv_ClearSelection() end end)
        btnAdvAnchorHover:SetScript("OnClick", function() if _G.ADT_Adv_SetAnchor_Hovered then ADT_Adv_SetAnchor_Hovered() end end)
        btnAdvAnchorSelected:SetScript("OnClick", function() if _G.ADT_Adv_SetAnchor_Selected then ADT_Adv_SetAnchor_Selected() end end)

        -- 移除旧剪切板调用（不再设置）
    end

    local OVERRIDE_KEYS = {
        -- 仅强制覆盖这五个：S/R/X/C/V
        -- 临时板：存入/取出
        { key = "CTRL-S", button = function() return btnTempStore end },
        { key = "CTRL-R", button = function() return btnTempRecall end },
        -- 住宅剪切板：复制/粘贴/剪切
        { key = "CTRL-C", button = function() return btnCopy end },
        { key = "CTRL-V", button = function() return btnPaste end },
        { key = "CTRL-X", button = function() return btnCut end },
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
            if btn then
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
