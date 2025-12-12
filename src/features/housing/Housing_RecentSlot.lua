-- Housing_RecentSlot.lua
-- 功能："最近放置"快捷槽 - QuickBar 左侧常驻显示最新放置的装饰
-- 设计：独立脚本，数据来源 ADT.History，与设置面板 Recent 分类完全解耦

local ADDON_NAME, ADT = ...
ADT = ADT or {}

local L = ADT.L or {}

-- 常量（与 QuickbarUI 保持一致）
local SLOT_SIZE = 80
local SLOT_SPACING = 5  -- 与 QuickBar 主体的间距

-- 模块
local RecentSlot = {}
ADT.RecentSlot = RecentSlot

local slotFrame = nil

local function D(msg)
    if ADT and ADT.DebugPrint then ADT.DebugPrint(msg) end
end

-- 创建槽位
function RecentSlot:Create()
    if slotFrame then return slotFrame end
    
    D("[RecentSlot] Creating...")
    
    -- 等待 QuickBar 创建完成
    local quickbar = _G["ADTQuickbarFrame"]
    if not quickbar then
        D("[RecentSlot] ADTQuickbarFrame not found, waiting...")
        return nil
    end
    
    slotFrame = CreateFrame("Button", "ADTRecentSlot", quickbar, "BackdropTemplate")
    slotFrame:SetSize(SLOT_SIZE, SLOT_SIZE)
    -- 锚定到 QuickBar 正左方
    slotFrame:SetPoint("RIGHT", quickbar, "LEFT", -SLOT_SPACING, 0)
    slotFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    slotFrame:SetFrameLevel(quickbar:GetFrameLevel())
    
    -- 背景（与 QuickbarUI.CreateSlot 一致）
    slotFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    slotFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    slotFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- 图标
    slotFrame.icon = slotFrame:CreateTexture(nil, "ARTWORK")
    slotFrame.icon:SetSize(SLOT_SIZE - 8, SLOT_SIZE - 8)
    slotFrame.icon:SetPoint("CENTER")
    slotFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slotFrame.icon:Hide()
    
    -- 空槽位背景
    slotFrame.emptyBg = slotFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    slotFrame.emptyBg:SetSize(SLOT_SIZE - 6, SLOT_SIZE - 6)
    slotFrame.emptyBg:SetPoint("CENTER")
    slotFrame.emptyBg:SetAtlas("ui-hud-minimap-housing-indoor-static-bg")
    slotFrame.emptyBg:SetAlpha(0.7)
    slotFrame.emptyBg:Show()
    
    -- 顶部标签
    slotFrame.labelText = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotFrame.labelText:SetPoint("TOP", slotFrame, "TOP", 0, -4)
    slotFrame.labelText:SetText(L["Recent Slot"] or "最近放置")
    slotFrame.labelText:SetTextColor(0.9, 0.75, 0.3, 1)  -- 金色
    
    -- 库存数量：右下角
    slotFrame.quantity = slotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotFrame.quantity:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", -6, 6)
    slotFrame.quantity:SetTextColor(1, 1, 1)
    slotFrame.quantity:Hide()
    
    -- 高亮
    slotFrame.highlight = slotFrame:CreateTexture(nil, "HIGHLIGHT")
    slotFrame.highlight:SetAllPoints()
    slotFrame.highlight:SetColorTexture(1, 1, 1, 0.2)
    
    -- 点击逻辑
    slotFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slotFrame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            local history = ADT.History and ADT.History:GetAll()
            if history and history[1] then
                C_Timer.After(0.1, function()
                    ADT.History:StartPlacing(history[1].decorID)
                end)
            end
        end
        -- 右键暂无操作
    end)
    
    -- Tooltip
    slotFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local history = ADT.History and ADT.History:GetAll()
        if history and history[1] then
            GameTooltip:SetText(history[1].name or L["Unknown Decor"])
            GameTooltip:AddLine(L["Left-click: Place"] or "左键：放置", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText(L["Recent Slot"] or "最近放置")
            GameTooltip:AddLine(L["No recent placement"] or "暂无记录", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    slotFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    D("[RecentSlot] Created successfully")
    return slotFrame
end

-- 刷新槽位显示
function RecentSlot:Refresh()
    if not slotFrame then return end
    
    local history = ADT.History and ADT.History:GetAll()
    if history and history[1] then
        local item = history[1]
        slotFrame.icon:SetTexture(item.icon or 134400)
        slotFrame.icon:Show()
        
        -- 获取库存数量
        local qty = 0
        if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
            local entryInfo = C_HousingCatalog.GetCatalogEntryInfoByRecordID(
                Enum.HousingCatalogEntryType.Decor, item.decorID, true)
            if entryInfo then
                qty = entryInfo.quantity or 0
            end
        end
        
        -- 显示库存
        if qty > 0 then
            slotFrame.quantity:SetText(tostring(qty))
            slotFrame.quantity:SetTextColor(1, 1, 1)
            slotFrame.quantity:Show()
            slotFrame:SetBackdropBorderColor(1, 0.82, 0, 1)  -- 金色边框
        else
            slotFrame.quantity:SetText("0")
            slotFrame.quantity:SetTextColor(1, 0.3, 0.3)
            slotFrame.quantity:Show()
            slotFrame:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)  -- 红色边框
        end
        
        if slotFrame.emptyBg then slotFrame.emptyBg:Hide() end
    else
        slotFrame.icon:Hide()
        slotFrame.quantity:Hide()
        slotFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        if slotFrame.emptyBg then slotFrame.emptyBg:Show() end
    end
end

-- 显示/隐藏
function RecentSlot:Show()
    if not slotFrame then self:Create() end
    if slotFrame then 
        slotFrame:Show()
        self:Refresh()
    end
end

function RecentSlot:Hide()
    if slotFrame then slotFrame:Hide() end
end

-- 初始化（延迟等待 QuickBar 创建）
local function Initialize()
    D("[RecentSlot] Initialize")
    
    -- 等待 QuickBar 创建完成
    C_Timer.After(0.6, function()
        RecentSlot:Create()
        
        local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
        if isActive then
            RecentSlot:Show()
        else
            RecentSlot:Hide()
        end
    end)
end

C_Timer.After(0.5, Initialize)

-- 事件监听
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
eventFrame:RegisterEvent("HOUSING_DECOR_PLACE_SUCCESS")
eventFrame:RegisterEvent("HOUSING_DECOR_REMOVED")
eventFrame:RegisterEvent("HOUSING_CATALOG_CATEGORY_UPDATED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "HOUSE_EDITOR_MODE_CHANGED" then
        C_Timer.After(0.1, function()
            local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
            if isActive then
                RecentSlot:Show()
            else
                RecentSlot:Hide()
            end
        end)
    elseif event == "HOUSING_DECOR_PLACE_SUCCESS" then
        -- 放置成功后刷新显示
        C_Timer.After(0.1, function()
            RecentSlot:Refresh()
        end)
    elseif event == "HOUSING_DECOR_REMOVED" or event == "HOUSING_CATALOG_CATEGORY_UPDATED" then
        -- 装饰被移除或库存变化时刷新
        C_Timer.After(0.2, function()
            RecentSlot:Refresh()
        end)
    end
end)

-- 注册到 History 的回调（如果可用）
if ADT.History then
    ADT.History.OnHistoryChanged = function()
        RecentSlot:Refresh()
    end
end

D("[RecentSlot] Module loaded")
