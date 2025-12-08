-- Housing_ClipboardPanel.lua：临时板弹窗（ADT 独立实现）

local ADDON_NAME, ADT = ...

local ClipboardPopup = {}
ADT.ClipboardPopup = ClipboardPopup

local POPUP_WIDTH = 260
local POPUP_HEIGHT = 300
local ITEM_HEIGHT = 36
local ICON_SIZE = 28

local MainFrame

local function GetBestParent()
    if HouseEditorFrame and HouseEditorFrame:IsShown() then
        return HouseEditorFrame
    end
    return UIParent
end

local function CreatePopupFrame()
    if MainFrame then return MainFrame end

    MainFrame = CreateFrame("Frame", "ADTClipboardPopup", GetBestParent(), "BackdropTemplate")
    MainFrame:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    MainFrame:SetPoint("CENTER", UIParent, "CENTER", 250, 30)
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ADT and ADT.SaveFramePosition then
            ADT.SaveFramePosition("ClipboardPopupPos", self)
        end
    end)
    MainFrame:SetClampedToScreen(true)
    MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    MainFrame:SetToplevel(true)
    MainFrame:Hide()

    MainFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    MainFrame:SetBackdropColor(0.1, 0.08, 0.06, 0.95)
    MainFrame:SetBackdropBorderColor(0.6, 0.5, 0.4, 1)

    local Title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetPoint("TOP", MainFrame, "TOP", 0, -10)
    Title:SetText("临时板")
    MainFrame.Title = Title

    local CloseBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
    CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -2, -2)
    CloseBtn:SetScript("OnClick", function() MainFrame:Hide() end)

    local ScrollFrame = CreateFrame("ScrollFrame", nil, MainFrame, "UIPanelScrollFrameTemplate")
    ScrollFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 8, -36)
    ScrollFrame:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -28, 8)
    MainFrame.ScrollFrame = ScrollFrame

    local Content = CreateFrame("Frame", nil, ScrollFrame)
    Content:SetSize(POPUP_WIDTH - 36, 1)
    ScrollFrame:SetScrollChild(Content)
    if ADT and ADT.Scroll and ADT.Scroll.AttachScrollFrame then
        ADT.Scroll.AttachScrollFrame(ScrollFrame)
    end
    MainFrame.Content = Content

    MainFrame.buttonPool = {}

    tinsert(UISpecialFrames, "ADTClipboardPopup")

    return MainFrame
end

local function CreateItemButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(POPUP_WIDTH - 44, ITEM_HEIGHT)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (ITEM_HEIGHT + 2))

    btn.Highlight = btn:CreateTexture(nil, "BACKGROUND")
    btn.Highlight:SetAllPoints()
    btn.Highlight:SetColorTexture(1, 1, 1, 0.1)
    btn.Highlight:Hide()

    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    btn.Icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.CountText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.CountText:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.CountText:SetJustifyH("RIGHT")

    btn.Name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.Name:SetPoint("LEFT", btn.Icon, "RIGHT", 8, 0)
    btn.Name:SetPoint("RIGHT", btn.CountText, "LEFT", -8, 0)
    btn.Name:SetJustifyH("LEFT")
    btn.Name:SetWordWrap(false)

    btn:SetScript("OnEnter", function(self)
        if not self.isDisabled then
            self.Highlight:Show(); self.Name:SetTextColor(1,1,1)
        end
        if self.decorID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.Name:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine("左键：开始放置", 0, 1, 0)
            GameTooltip:AddLine("右键：从临时板移除", 1, 0.4, 0.4)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.Highlight:Hide(); self.Name:SetTextColor(0.9,0.8,0.7); GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function(self)
        if self.isDisabled then return end
        if self.decorID then
            if ADT and ADT.Clipboard and ADT.Clipboard.StartPlacing then
                ADT.Clipboard:StartPlacing(self.decorID)
            end
        end
    end)
    btn:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self.index then
            if ADT and ADT.Clipboard and ADT.Clipboard.RemoveAt then
                ADT.Clipboard:RemoveAt(self.index)
                ClipboardPopup:Refresh()
            end
        end
    end)

    return btn
end

function ClipboardPopup:Refresh()
    local frame = CreatePopupFrame()
    local content = frame.Content
    for _, b in ipairs(frame.buttonPool) do b:Hide() end

    local list = (ADT and ADT.Clipboard and ADT.Clipboard.GetAll and ADT.Clipboard:GetAll()) or {}
    if not list then list = {} end

    -- 构建/复用按钮
    local function acquire(i)
        local b = frame.buttonPool[i]
        if not b then b = CreateItemButton(content, i); frame.buttonPool[i] = b end
        return b
    end

    for i, item in ipairs(list) do
        local btn = acquire(i)
        btn.index = i
        btn.decorID = item.decorID
        btn.Icon:SetTexture(item.icon or 134400)

        -- 查询库存数量（与历史相同口径）
        local entryInfo = C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, item.decorID, true)
        local available = 0
        if entryInfo then
            available = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
            if not item.name then item.name = entryInfo.name end
            if not item.icon and entryInfo.iconTexture then btn.Icon:SetTexture(entryInfo.iconTexture) end
        end
        local clipCount = tonumber(item.count or 1) or 1
        local displayName = item.name or ("装饰 #" .. tostring(item.decorID))
        if clipCount > 1 then
            displayName = string.format("[x%d] %s", clipCount, displayName)
        end
        btn.Name:SetText(displayName)
        btn.CountText:SetText(tostring(available))

        btn.isDisabled = available <= 0
        if btn.isDisabled then
            btn.Name:SetTextColor(0.5,0.5,0.5)
            if btn.Icon.SetDesaturated then btn.Icon:SetDesaturated(true) end
        else
            btn.Name:SetTextColor(0.9,0.8,0.7)
            if btn.Icon.SetDesaturated then btn.Icon:SetDesaturated(false) end
        end

        btn:Show()
    end

    content:SetHeight(math.max(1, #list * (ITEM_HEIGHT + 2)))

    if #list == 0 then
        if not frame.EmptyText then
            frame.EmptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            frame.EmptyText:SetPoint("CENTER", content, "CENTER", 0, 50)
            frame.EmptyText:SetText("临时板为空\nCtrl+S 存入；Ctrl+R 取出")
        end
        frame.EmptyText:Show()
    elseif frame.EmptyText then
        frame.EmptyText:Hide()
    end
end

function ClipboardPopup:Show()
    local frame = CreatePopupFrame()
    local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
    if isActive and HouseEditorFrame then
        frame:SetParent(HouseEditorFrame)
        frame:SetFrameStrata("TOOLTIP")
    else
        frame:SetParent(UIParent)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    if ADT and ADT.RestoreFramePosition then
        ADT.RestoreFramePosition("ClipboardPopupPos", frame, function(f)
            f:SetPoint("CENTER", UIParent, "CENTER", 250, 30)
        end)
    end
    self:Refresh()
    frame:Show()
end

function ClipboardPopup:Hide()
    if MainFrame then MainFrame:Hide() end
end

function ClipboardPopup:Toggle()
    if MainFrame and MainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- 存储/库存变化时刷新
local Watcher = CreateFrame("Frame")
Watcher:RegisterEvent("HOUSING_STORAGE_UPDATED")
Watcher:RegisterEvent("HOUSING_STORAGE_ENTRY_UPDATED")
Watcher:RegisterEvent("HOUSE_DECOR_ADDED_TO_CHEST")
Watcher:RegisterEvent("HOUSING_DECOR_REMOVED")
Watcher:RegisterEvent("HOUSING_DECOR_PLACE_SUCCESS")
Watcher:SetScript("OnEvent", function()
    if MainFrame and MainFrame:IsShown() then
        C_Timer.After(0.05, function()
            ClipboardPopup:Refresh()
        end)
    end
end)

-- 列表变化时刷新（与 History 的 OnHistoryChanged 一致的约定）
if ADT and ADT.Clipboard then
    ADT.Clipboard.OnChanged = function()
        if MainFrame and MainFrame:IsShown() then
            ClipboardPopup:Refresh()
        end
    end
end

-- 弹窗已整合到 ADT 控制中心 GUI，不再自动打开独立弹窗
-- 进入编辑模式时由 GUI 负责显示
local EditWatcher = CreateFrame("Frame")
local wasActive = false
local function UpdateOpenState()
    local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
    if isActive then
        -- 不再自动打开独立弹窗
        if MainFrame and HouseEditorFrame then
            MainFrame:SetParent(HouseEditorFrame)
            MainFrame:SetFrameStrata("TOOLTIP")
        end
    else
        if MainFrame then
            MainFrame:SetParent(UIParent)
            MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            MainFrame:Hide()
        end
    end
    wasActive = isActive
end
EditWatcher:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
EditWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
EditWatcher:RegisterEvent("ADDON_LOADED")
EditWatcher:SetScript("OnEvent", function()
    C_Timer.After(0.1, UpdateOpenState)
end)
