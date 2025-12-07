-- Housing_PaintMode.lua
-- 仅包含 Paint Mode (Ctrl键批量放置) 功能

local ADDON_NAME, ADT = ...
local L = ADT.L

local PaintMode = CreateFrame("Frame")
ADT.PaintMode = PaintMode

-- Global APIs
local C_HousingBasicMode = C_HousingBasicMode

-- State
PaintMode.lastPlacedEntryID = nil

-- Paint Mode Logic: If Ctrl is held when placing, continue placing same item
function PaintMode:OnDecorPlaced()
    -- 读取开关：仅当用户在“通用”里勾选了“按住CTRL以批量放置”时才启用
    local enabled = ADT and ADT.GetDBValue and ADT.GetDBValue('EnableBatchPlace')
    if not enabled then return end

    if not IsControlKeyDown() then return end
    if not self.lastPlacedEntryID then return end

    C_Timer.After(0.1, function()
        C_HousingBasicMode.StartPlacingNewDecor(self.lastPlacedEntryID)
    end)
end

-- Hook StartPlacing to capture EntryID
hooksecurefunc(C_HousingBasicMode, "StartPlacingNewDecor", function(entryID)
    PaintMode.lastPlacedEntryID = entryID
end)

PaintMode:SetScript("OnEvent", function(self, event, ...)
    if event == "HOUSING_DECOR_PLACE_SUCCESS" then
        self:OnDecorPlaced()
    end
end)

PaintMode:RegisterEvent("HOUSING_DECOR_PLACE_SUCCESS")
