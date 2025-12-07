-- Housing_HistoryPopup.lua
-- 放置历史弹窗 UI：显示最近放置的装饰，点击快速放置
local ADDON_NAME, ADT = ...
local L = ADT.L or {}

local HistoryPopup = {}
ADT.HistoryPopup = HistoryPopup

local POPUP_WIDTH = 260
local POPUP_HEIGHT = 300
local ITEM_HEIGHT = 36
local ICON_SIZE = 28

local MainFrame

-- 选择最合适的父级（编辑器打开时挂到编辑器上层，以避免被覆盖）
local function GetBestParent()
    if HouseEditorFrame and HouseEditorFrame:IsShown() then
        return HouseEditorFrame -- 暴雪住宅编辑器的根，用它可确保位于编辑界面之上
    end
    return UIParent
end

-- 创建弹窗框架
local function CreatePopupFrame()
    if MainFrame then return MainFrame end
    
    MainFrame = CreateFrame("Frame", "ADTHistoryPopup", GetBestParent(), "BackdropTemplate")
    MainFrame:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ADT and ADT.SaveFramePosition then
            ADT.SaveFramePosition("HistoryPopupPos", self)
        end
    end)
    MainFrame:SetClampedToScreen(true)
    -- 关键：编辑模式下 Blizzard 的房屋编辑 UI 使用全屏层级，
    -- 我们需要把历史弹窗的层级抬高，否则会被遮住，看起来像“打不开”。
    -- 使用 FULLSCREEN_DIALOG 可保证位于编辑器之上，但仍低于 TOOLTIP。
    -- FULLSCREEN_DIALOG 在大多数情况下足够；在编辑器打开时我们再切换到 TOOLTIP 以确保最高层
    MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    MainFrame:SetToplevel(true)
    MainFrame:Hide()
    
    -- 背景样式
    MainFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    MainFrame:SetBackdropColor(0.1, 0.08, 0.06, 0.95)
    MainFrame:SetBackdropBorderColor(0.6, 0.5, 0.4, 1)
    
    -- 标题
    local Title = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetPoint("TOP", MainFrame, "TOP", 0, -10)
    Title:SetText(L["History Popup Title"] or "最近放置")
    MainFrame.Title = Title
    
    -- 关闭按钮
    local CloseBtn = CreateFrame("Button", nil, MainFrame, "UIPanelCloseButton")
    CloseBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -2, -2)
    CloseBtn:SetScript("OnClick", function() MainFrame:Hide() end)
    
    -- 滚动框架
    local ScrollFrame = CreateFrame("ScrollFrame", nil, MainFrame, "UIPanelScrollFrameTemplate")
    ScrollFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", 8, -36)
    ScrollFrame:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -28, 8)
    MainFrame.ScrollFrame = ScrollFrame
    
    -- 内容容器
    local Content = CreateFrame("Frame", nil, ScrollFrame)
    Content:SetSize(POPUP_WIDTH - 36, 1) -- 高度动态调整
    ScrollFrame:SetScrollChild(Content)
    MainFrame.Content = Content
    
    -- 按钮池
    MainFrame.buttonPool = {}
    
    -- ESC 关闭
    tinsert(UISpecialFrames, "ADTHistoryPopup")
    
    return MainFrame
end

-- 创建单个装饰按钮
local function CreateItemButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(POPUP_WIDTH - 44, ITEM_HEIGHT)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * (ITEM_HEIGHT + 2))
    
    -- 背景高亮
    btn.Highlight = btn:CreateTexture(nil, "BACKGROUND")
    btn.Highlight:SetAllPoints()
    btn.Highlight:SetColorTexture(1, 1, 1, 0.1)
    btn.Highlight:Hide()
    
    -- 图标
    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    btn.Icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- 裁剪边缘
    
    -- 数量（右对齐）
    btn.CountText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.CountText:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.CountText:SetJustifyH("RIGHT")
    
    -- 名称（左对齐；右侧为数量预留空间）
    btn.Name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.Name:SetPoint("LEFT", btn.Icon, "RIGHT", 8, 0)
    btn.Name:SetPoint("RIGHT", btn.CountText, "LEFT", -8, 0)
    btn.Name:SetJustifyH("LEFT")
    btn.Name:SetWordWrap(false)
    
    -- 交互
    btn:SetScript("OnEnter", function(self)
        if not self.isDisabled then
            self.Highlight:Show()
            self.Name:SetTextColor(1, 1, 1)
        end
        if self.decorID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local tipName = self.Name:GetText() or ""
            GameTooltip:AddLine(tipName, 1,1,1)
            local count = tonumber(self.CountText:GetText() or "0") or 0
            if count > 0 then
                GameTooltip:AddLine("库存："..count, 0,1,0)
            else
                GameTooltip:AddLine("库存：0（不可放置）", 1,0.2,0.2)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.Highlight:Hide()
        if self.isDisabled then
            self.Name:SetTextColor(0.5, 0.5, 0.5)
        else
            self.Name:SetTextColor(0.9, 0.8, 0.7)
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        if self.decorID and not self.isDisabled then
            ADT.History:StartPlacing(self.decorID)
        end
    end)
    
    return btn
end

-- 刷新列表
function HistoryPopup:Refresh()
    if not MainFrame then return end
    
    local list = ADT.History:GetAll()
    local content = MainFrame.Content
    
    -- 回收所有按钮
    for _, btn in ipairs(MainFrame.buttonPool) do
        btn:Hide()
    end
    
    -- 创建/复用按钮
    for i, item in ipairs(list) do
        local btn = MainFrame.buttonPool[i]
        if not btn then
            btn = CreateItemButton(content, i)
            MainFrame.buttonPool[i] = btn
        end
        
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * (ITEM_HEIGHT + 2))
        btn.Icon:SetTexture(item.icon)

        -- 获取当前库存，并在这里修正名称（如之前记录为“装饰 #xxx”）
        local info = C_HousingCatalog.GetCatalogEntryInfoByRecordID and C_HousingCatalog.GetCatalogEntryInfoByRecordID(1, item.decorID, true)
        local count = 0
        if info then
            count = (info.quantity or 0) + (info.remainingRedeemable or 0)
            if info.name and (not item.name or string.find(item.name, "^装饰 #")) then
                item.name = info.name
            end
        end
        btn.Name:SetText(item.name or ("装饰 #" .. tostring(item.decorID)))
        btn.CountText:SetText(tostring(count))

        -- 状态：可用/不可用
        btn.isDisabled = count <= 0
        if btn.isDisabled then
            btn.Name:SetTextColor(0.5, 0.5, 0.5)
            if btn.Icon.SetDesaturated then btn.Icon:SetDesaturated(true) end
        else
            btn.Name:SetTextColor(0.9, 0.8, 0.7)
            if btn.Icon.SetDesaturated then btn.Icon:SetDesaturated(false) end
        end

        btn.decorID = item.decorID
        btn:Show()
    end
    
    -- 更新内容高度
    content:SetHeight(math.max(1, #list * (ITEM_HEIGHT + 2)))
    
    -- 空列表提示
    if #list == 0 then
        if not MainFrame.EmptyText then
            MainFrame.EmptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            MainFrame.EmptyText:SetPoint("CENTER", content, "CENTER", 0, 50)
            MainFrame.EmptyText:SetText(L["History Empty"] or "暂无放置记录\n放置装饰后会自动记录")
        end
        MainFrame.EmptyText:Show()
    elseif MainFrame.EmptyText then
        MainFrame.EmptyText:Hide()
    end
end

-- 显示弹窗
function HistoryPopup:Show()
    local frame = CreatePopupFrame()
    -- 根据当前模式动态调整父级与层级
    local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
    if isActive and HouseEditorFrame then
        frame:SetParent(HouseEditorFrame)
        frame:SetFrameStrata("TOOLTIP")
    else
        frame:SetParent(UIParent)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
    -- 恢复位置（相对 UIParent 记忆）
    if ADT and ADT.RestoreFramePosition then
        ADT.RestoreFramePosition("HistoryPopupPos", frame)
    end
    self:Refresh()
    frame:Show()
end

-- 隐藏弹窗
function HistoryPopup:Hide()
    if MainFrame then
        MainFrame:Hide()
    end
end

-- 切换显示
function HistoryPopup:Toggle()
    if MainFrame and MainFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- 注册历史变化回调
if ADT.History then
    ADT.History.OnHistoryChanged = function()
        HistoryPopup:Refresh()
    end
end

-- 快捷键绑定（H 键，仅在编辑模式下生效）
local KeyFrame = CreateFrame("Frame", nil, UIParent)
KeyFrame:EnableKeyboard(false)
KeyFrame:SetPropagateKeyboardInput(true)

local function OnKeyDown(self, key)
    if key == "H" and C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive() then
        HistoryPopup:Toggle()
        self:SetPropagateKeyboardInput(false)
    else
        self:SetPropagateKeyboardInput(true)
    end
end

-- 仅在编辑模式下启用快捷键（弹窗已整合到 GUI，不再自动打开）
local wasEditorActive = false

local function UpdateKeyBinding()
    local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
    
    if isActive then
        KeyFrame:SetScript("OnKeyDown", OnKeyDown)
        KeyFrame:EnableKeyboard(true)
        -- 弹窗已整合到 GUI，不再自动打开独立弹窗
        -- 编辑模式下由 SettingsPanelNew 负责显示 GUI
        if MainFrame and HouseEditorFrame then
            MainFrame:SetParent(HouseEditorFrame)
            MainFrame:SetFrameStrata("TOOLTIP")
        end
    else
        KeyFrame:SetScript("OnKeyDown", nil)
        KeyFrame:EnableKeyboard(false)
        if MainFrame then
            MainFrame:SetParent(UIParent)
            MainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            MainFrame:Hide()
        end
    end
    
    wasEditorActive = isActive
end

KeyFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
KeyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
KeyFrame:RegisterEvent("ADDON_LOADED")
KeyFrame:SetScript("OnEvent", function(self, event)
    -- 等待一帧，确保 HouseEditorFrame（如果需要）已创建
    C_Timer.After(0.1, UpdateKeyBinding)
end)

-- 存储/库存变化时刷新（把装饰放回仓库、购买、制作等都会触发）
local StorageWatcher = CreateFrame("Frame")
StorageWatcher:RegisterEvent("HOUSING_STORAGE_UPDATED")
StorageWatcher:RegisterEvent("HOUSING_STORAGE_ENTRY_UPDATED")
StorageWatcher:RegisterEvent("HOUSE_DECOR_ADDED_TO_CHEST")
StorageWatcher:RegisterEvent("HOUSING_DECOR_REMOVED")
StorageWatcher:SetScript("OnEvent", function()
    if MainFrame and MainFrame:IsShown() then
        -- 稍等一帧，等暴雪目录数值更新完成
        C_Timer.After(0.05, function()
            HistoryPopup:Refresh()
        end)
    end
end)

-- Slash 命令
SLASH_ADTHISTORY1 = "/adthistory"
SlashCmdList["ADTHISTORY"] = function(msg)
    if msg == "clear" then
        ADT.History:Clear()
        print("ADT: 放置历史已清空")
    elseif msg == "debug" then
        ADT.History:DebugPrint()
    else
        HistoryPopup:Toggle()
    end
end
