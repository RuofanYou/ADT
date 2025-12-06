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

local DisplayFrame

local function GetCatalogDecorInfo(decorID, tryGetOwnedInfo)
    tryGetOwnedInfo = true
    -- Enum.HousingCatalogEntryType.Decor = 1
    return GetCatalogEntryInfoByRecordID(1, decorID, tryGetOwnedInfo)
end

local EL = CreateFrame("Frame")
ADT.Housing = EL

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

-- 启用模块：加载后默认打开（只做这一项功能）
local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function()
    ADT.Housing:SetEnabled(true)
    bootstrap:UnregisterEvent("PLAYER_LOGIN")
end)
