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
    if IsControlKeyDown() then
        if self.lastPlacedEntryID then
            C_Timer.After(0.1, function()
                C_HousingBasicMode.StartPlacingNewDecor(self.lastPlacedEntryID)
            end)
        end
    end
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
