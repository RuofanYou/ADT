-- Housing_QuickbarUI.lua
-- 功能：快捷栏 UI - 底部横排动作条风格
-- 关键：必须在编辑器模式下将 parent 设为 HouseEditorFrame（与 DockUI 一致）

local ADDON_NAME, ADT = ...
ADT = ADT or {}

local L = ADT.L or {}

-- 常量
local SLOT_KEYS = { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8" }
local NUM_SLOTS = #SLOT_KEYS
local SLOT_SIZE = 80
local SLOT_SPACING = 4
local BAR_PADDING = 8
-- 统一厚度控制：仅暴露 BORDER_THICKNESS；角件尺寸由其按比例推导
local BORDER_THICKNESS = 10
local CORNER_MULTIPLIER = 5  -- 角件 = 厚度 * 此系数

-- 模块
local UI = {}
ADT.QuickbarUI = UI

local barFrame = nil
local slotFrames = {}
local hudAnchorPatched = false

local function D(msg)
    if ADT and ADT.DebugPrint then ADT.DebugPrint(msg) end
end

-- 将暴雪编辑器底部 HUD（ModesBar）与 Quickbar 顶部相切对齐
local function AlignEditorHUDToQuickbar()
    if not (HouseEditorFrame and HouseEditorFrame.ModeBar and barFrame and barFrame:IsShown()) then return end
    -- QuickBar 进入编辑器后 parent 也被切到 HouseEditorFrame，保持同一坐标系
    -- 只移动位置，不改外观/缩放
    local cfg = ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.QuickbarUI or nil
    local gap = (cfg and cfg.modeBarGap) or 0
    local hud = HouseEditorFrame.ModeBar
    hud:ClearAllPoints()
    hud:SetPoint("BOTTOM", barFrame, "TOP", 0, gap)
    hudAnchorPatched = true
    D("[QuickbarUI] Aligned ModeBar to Quickbar top")
end

-- 恢复暴雪 HUD 默认锚点（贴底）
local function RestoreEditorHUDAnchor()
    if not (HouseEditorFrame and HouseEditorFrame.ModeBar) then return end
    if not hudAnchorPatched then return end
    local hud = HouseEditorFrame.ModeBar
    hud:ClearAllPoints()
    hud:SetPoint("BOTTOM", 0, 0)
    hudAnchorPatched = false
    D("[QuickbarUI] Restored ModeBar default anchor")
end

-- 创建 UI（初始挂到 UIParent，稍后动态切换 parent）
function UI:Create()
    if barFrame then return barFrame end
    
    D("[QuickbarUI] Creating...")
    
    local totalWidth = (SLOT_SIZE * NUM_SLOTS) + (SLOT_SPACING * (NUM_SLOTS - 1)) + (BAR_PADDING * 2)
    local totalHeight = SLOT_SIZE + (BAR_PADDING * 2)
    
    barFrame = CreateFrame("Frame", "ADTQuickbarFrame", UIParent, "BackdropTemplate")
    barFrame:SetSize(totalWidth, totalHeight)
    -- 锚点与偏移改为“配置驱动”（Housing_Config.QuickbarUI）
    local cfg = ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.QuickbarUI or nil
    local anchor = cfg and cfg.anchor or nil
    local point    = (anchor and anchor.point) or "BOTTOM"
    local relPoint = (anchor and anchor.relPoint) or "BOTTOM"
    local x        = (anchor and anchor.x) or 0
    local y        = (anchor and anchor.bottomMargin) or 0
    barFrame:SetPoint(point, UIParent, relPoint, x, y)
    barFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    barFrame:SetFrameLevel(100)
    barFrame:SetClampedToScreen(true)
    
    -- 背景：保留柔和底色，但移除旧的黄色描边
    barFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    barFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.88)

    -- 外框：使用暴雪九宫格 WoodenNeutralFrameTemplate（Neutral 系列角件/边条）
    if not barFrame.NineSlice then
        local ns = CreateFrame("Frame", nil, barFrame, "NineSlicePanelTemplate")
        ns:SetAllPoints(true)
        -- 提升层级，保证边框不被槽位遮挡
        ns:SetFrameLevel(barFrame:GetFrameLevel() + 5)
        NineSliceUtil.ApplyLayoutByName(ns, "WoodenNeutralFrameTemplate")
        -- 强制使用 Neutral 套件，并依据 BORDER_THICKNESS 统一缩放
        local cs = math.max(1, BORDER_THICKNESS * CORNER_MULTIPLIER)
        if ns.TopLeftCorner then ns.TopLeftCorner:SetAtlas("Neutral-NineSlice-Corner", true); ns.TopLeftCorner:SetSize(cs, cs) end
        if ns.TopRightCorner then ns.TopRightCorner:SetAtlas("Neutral-NineSlice-Corner", true); ns.TopRightCorner:SetSize(cs, cs) end
        if ns.BottomLeftCorner then ns.BottomLeftCorner:SetAtlas("Neutral-NineSlice-Corner", true); ns.BottomLeftCorner:SetSize(cs, cs) end
        if ns.BottomRightCorner then ns.BottomRightCorner:SetAtlas("Neutral-NineSlice-Corner", true); ns.BottomRightCorner:SetSize(cs, cs) end

        if ns.TopEdge then ns.TopEdge:SetAtlas("_Neutral-NineSlice-EdgeTop", true); ns.TopEdge:SetHeight(BORDER_THICKNESS) end
        if ns.BottomEdge then ns.BottomEdge:SetAtlas("_Neutral-NineSlice-EdgeBottom", true); ns.BottomEdge:SetHeight(BORDER_THICKNESS) end
        if ns.LeftEdge then ns.LeftEdge:SetAtlas("!Neutral-NineSlice-EdgeLeft", true); ns.LeftEdge:SetWidth(BORDER_THICKNESS) end
        if ns.RightEdge then ns.RightEdge:SetAtlas("!Neutral-NineSlice-EdgeRight", true); ns.RightEdge:SetWidth(BORDER_THICKNESS) end
        barFrame.NineSlice = ns
    end
    
    -- 禁用拖动（KISS：不注册拖拽，不可移动；鼠标事件交由子按钮处理）
    barFrame:SetMovable(false)
    barFrame:EnableMouse(false)
    
    -- 创建槽位
    for i = 1, NUM_SLOTS do
        local slot = self:CreateSlot(barFrame, i)
        local xOffset = BAR_PADDING + ((i - 1) * (SLOT_SIZE + SLOT_SPACING))
        slot:SetPoint("LEFT", barFrame, "LEFT", xOffset, 0)
        slotFrames[i] = slot
    end
    
    -- Refresh 方法
    barFrame.Refresh = function() UI:Refresh() end
    
    -- 关联到 Quickbar 模块
    if ADT.Quickbar then
        ADT.Quickbar.uiFrame = barFrame
    end
    
    D("[QuickbarUI] Created successfully")
    return barFrame
end

function UI:CreateSlot(parent, slotIndex)
    local slot = CreateFrame("Button", "ADTQuickbarSlot" .. slotIndex, parent, "BackdropTemplate")
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    slot.slotIndex = slotIndex
    
    slot:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    slot:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetSize(SLOT_SIZE - 8, SLOT_SIZE - 8)
    slot.icon:SetPoint("CENTER")
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon:Hide()
    
    -- 空槽位背景：使用 Housing Atlas 图像
    slot.emptyBg = slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    slot.emptyBg:SetSize(SLOT_SIZE - 6, SLOT_SIZE - 6)
    slot.emptyBg:SetPoint("CENTER")
    slot.emptyBg:SetAtlas("ui-hud-minimap-housing-indoor-static-bg")
    slot.emptyBg:SetAlpha(0.7)
    slot.emptyBg:Show()
    
    -- 快捷键文字：右上角（内收像素改为配置驱动）
    local QBCFG = assert(ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.QuickbarUI,
        "ADT.HousingInstrCFG.QuickbarUI 缺失：请确认 Housing_Config.lua 已加载")
    local INSETS = assert(QBCFG.SlotTextInsets, "QuickbarUI.SlotTextInsets 缺失")
    slot.keyText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot.keyText:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -INSETS.keyRight, -INSETS.keyTop)
    -- 键帽显示与 Keybinds 保持一致（单一权威）。若玩家在 UI 中换绑为其它键位，这里自动更新。
    local keyText = SLOT_KEYS[slotIndex]
    if ADT.Keybinds and ADT.Keybinds.GetKeybind and ADT.Keybinds.GetKeyDisplayName then
        local key = ADT.Keybinds:GetKeybind('Quickbar'..tostring(slotIndex))
        local disp = ADT.Keybinds:GetKeyDisplayName(key)
        if disp and disp ~= '' then keyText = disp end
    end
    slot.keyText:SetText(keyText)
    slot.keyText:SetTextColor(0.8, 0.8, 0.8, 0.9)
    
    -- 库存数量：右下角（内收像素改为配置驱动；初始隐藏）
    slot.quantity = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot.quantity:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -INSETS.qtyRight, INSETS.qtyBottom)
    slot.quantity:SetTextColor(1, 1, 1)
    slot.quantity:Hide()
    
    -- 以前这里会在空槽位放一个居中的“·”占位符，
    -- 会让空槽视觉上出现一个小点，容易被误认为是内容。
    -- 现在取消该占位：不创建任何空态文本，由边框颜色区分空/有内容。
    
    slot.highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.highlight:SetAllPoints()
    slot.highlight:SetColorTexture(1, 1, 1, 0.2)
    
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- 延迟执行，避免鼠标点击被游戏解读为"放置"命令
            -- 参考 DreamHouse: C_Timer.After(0.1, ...) 后再调用 StartPlacingNewDecor
            C_Timer.After(0.1, function()
                if ADT.Quickbar then ADT.Quickbar:OnQuickbarKeyPressed(self.slotIndex) end
            end)
        elseif button == "RightButton" then
            if ADT.Quickbar then ADT.Quickbar:ClearSlot(self.slotIndex) end
        end
    end)
    
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local data = ADT.Quickbar and ADT.Quickbar:GetSlotData(self.slotIndex)
        if data then
            -- 装饰名称：优先使用真实名称，否则回退到“未知装饰”（本地化）
            GameTooltip:SetText(data.name or L["Unknown Decor"])
            -- 操作提示：统一走本地化（左键放置｜右键清空）
            local left = L["Left-click: Place"]
            local right = L["Right-click: Clear"]
            GameTooltip:AddLine(string.format("%s | %s", left, right), 0.7, 0.7, 0.7)
        else
            -- 空槽位提示：采用占位符格式，保持多语言
            GameTooltip:SetText(string.format(L["Empty slot %s"], SLOT_KEYS[self.slotIndex]))
            GameTooltip:AddLine(L["Quickbar bind hint"], 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    return slot
end

function UI:Refresh()
    if not barFrame then return end
    for i = 1, NUM_SLOTS do
        local slot = slotFrames[i]
        if slot then
            -- 刷新键帽文本：从 Keybinds 实时读取
            if ADT.Keybinds and ADT.Keybinds.GetKeybind and ADT.Keybinds.GetKeyDisplayName then
                local key = ADT.Keybinds:GetKeybind('Quickbar'..tostring(i))
                local disp = ADT.Keybinds:GetKeyDisplayName(key) or SLOT_KEYS[i]
                slot.keyText:SetText((disp ~= '' and disp) and disp or SLOT_KEYS[i])
            else
                slot.keyText:SetText(SLOT_KEYS[i])
            end
            local data = ADT.Quickbar and ADT.Quickbar:GetSlotData(i)
            if data and data.recordID then
                slot.icon:SetTexture(data.icon or 134400)
                slot.icon:Show()
                
                -- 获取并显示库存数量
                local qty = 0
                if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID then
                    local entryInfo = C_HousingCatalog.GetCatalogEntryInfoByRecordID(
                        Enum.HousingCatalogEntryType.Decor, data.recordID, true)
                    if entryInfo then
                        qty = entryInfo.quantity or 0
                    end
                end
                
                -- 显示库存
                if qty > 0 then
                    slot.quantity:SetText(tostring(qty))
                    slot.quantity:SetTextColor(1, 1, 1)  -- 白色
                    slot.quantity:Show()
                    slot:SetBackdropBorderColor(1, 0.82, 0, 1) -- 金色边框
                else
                    slot.quantity:SetText("0")
                    slot.quantity:SetTextColor(1, 0.3, 0.3)  -- 红色
                    slot.quantity:Show()
                    slot:SetBackdropBorderColor(0.8, 0.3, 0.3, 1)  -- 红色边框
                end
                -- 有内容时隐藏空背景
                if slot.emptyBg then slot.emptyBg:Hide() end
            else
                slot.icon:Hide()
                slot.quantity:Hide()
                slot:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                -- 空槽位时显示背景
                if slot.emptyBg then slot.emptyBg:Show() end
            end
        end
    end
end

-- 应用缩放（根据设置读取大小倍率）
function UI:ApplyScale()
    if not barFrame then return end
    local size = ADT.GetDBValue and ADT.GetDBValue('QuickbarSize') or 'medium'
    local cfg = ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.QuickbarUI or nil
    local scaleTable = cfg and cfg.scaleBySize or nil
    local scale = (scaleTable and scaleTable[size]) or 1.0
    barFrame:SetScale(scale)
    D("[QuickbarUI] Applied scale=" .. tostring(scale) .. " for size=" .. tostring(size))
end

-- 关键：进入/退出编辑器时切换 parent（与 DockUI 一致）
function UI:OnEditorEnter()
    -- 若开关关闭则不显示
    if ADT.GetDBValue and ADT.GetDBValue('EnableQuickbar') == false then
        D("[QuickbarUI] Disabled by setting, skipping")
        return
    end
    
    if not barFrame then self:Create() end
    if not barFrame then return end
    
    -- 关键：设置 parent 为 HouseEditorFrame
    if HouseEditorFrame then
        barFrame:SetParent(HouseEditorFrame)
        barFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        barFrame:SetFrameLevel(100)
        D("[QuickbarUI] Parent set to HouseEditorFrame")
    end
    
    barFrame:ClearAllPoints()
    -- 进入编辑器时同样走配置锚点
    local cfg = ADT and ADT.HousingInstrCFG and ADT.HousingInstrCFG.QuickbarUI or nil
    local anchor = cfg and cfg.anchor or nil
    local point    = (anchor and anchor.point) or "BOTTOM"
    local relPoint = (anchor and anchor.relPoint) or "BOTTOM"
    local x        = (anchor and anchor.x) or 0
    local y        = (anchor and anchor.bottomMargin) or 0
    barFrame:SetPoint(point, UIParent, relPoint, x, y)
    barFrame:Show()
    barFrame:SetAlpha(1)
    self:Refresh()
    self:ApplyScale()
    AlignEditorHUDToQuickbar()
    D("[QuickbarUI] Shown in editor mode")
end

function UI:OnEditorExit()
    if not barFrame then return end
    RestoreEditorHUDAnchor()
    barFrame:SetParent(UIParent)
    barFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    barFrame:Hide()
    D("[QuickbarUI] Hidden, parent reset to UIParent")
end

function UI:Show()
    local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
    if isActive then
        self:OnEditorEnter()
    end
end

function UI:Hide()
    if barFrame then barFrame:Hide() end
end

-- 初始化
local function Initialize()
    D("[QuickbarUI] Initialize")
    UI:Create()
    
    local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
    if isActive then
        UI:OnEditorEnter()
    else
        if barFrame then barFrame:Hide() end
    end
end

C_Timer.After(0.5, Initialize)

-- 事件监听
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
eventFrame:RegisterEvent("HOUSING_DECOR_REMOVED")
eventFrame:RegisterEvent("HOUSING_CATALOG_CATEGORY_UPDATED")
eventFrame:RegisterEvent("HOUSING_DECOR_PLACE_SUCCESS")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    D("[QuickbarUI] Event: " .. event)
    if event == "HOUSE_EDITOR_MODE_CHANGED" then
        C_Timer.After(0.1, function()
            local isActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
            if isActive then
                UI:OnEditorEnter()
            else
                UI:OnEditorExit()
            end
        end)
    elseif event == "HOUSING_DECOR_REMOVED" or event == "HOUSING_CATALOG_CATEGORY_UPDATED" or event == "HOUSING_DECOR_PLACE_SUCCESS" then
        -- 库存变化时刷新
        C_Timer.After(0.2, function()
            UI:Refresh()
        end)
    end
end)

-- 斜杠命令
SLASH_ADTQBUI1 = "/adtqbui"
SlashCmdList["ADTQBUI"] = function(msg)
    if msg == "show" then
        UI:Show()
    elseif msg == "hide" then
        UI:Hide()
    elseif msg == "debug" then
        if barFrame then
            print("barFrame exists")
            print("  IsShown=" .. tostring(barFrame:IsShown()))
            print("  Alpha=" .. tostring(barFrame:GetAlpha()))
            print("  Parent=" .. tostring(barFrame:GetParent() and barFrame:GetParent():GetName() or "unnamed"))
            print("  Strata=" .. tostring(barFrame:GetFrameStrata()))
            print("  Level=" .. tostring(barFrame:GetFrameLevel()))
        else
            print("barFrame is nil!")
        end
    else
        print("/adtqbui show|hide|debug")
    end
end

D("[QuickbarUI] Module loaded")

-- 监听 Keybinds 变化：当 Dock 的“快捷键”面板录制完成写入 DB（Key="Keybinds"）后，
-- 立即刷新底部快捷栏的键帽文本，确保玩家看到的提示与实际绑定保持一致。
if ADT and ADT.Settings and ADT.Settings.On then
    ADT.Settings.On('Keybinds', function()
        -- 下一帧刷新以规避在录制回调栈内的 UI 抖动
        C_Timer.After(0, function()
            if UI and UI.Refresh then UI:Refresh() end
        end)
    end)
    
    -- 监听"启用动作栏"开关
    ADT.Settings.On('EnableQuickbar', function(enabled)
        if enabled == false then
            UI:OnEditorExit()
        else
            local active = C_HouseEditor and C_HouseEditor.IsHouseEditorActive and C_HouseEditor.IsHouseEditorActive()
            if active then UI:OnEditorEnter() end
        end
    end)
    
    -- 监听"动作栏尺寸"变化
    ADT.Settings.On('QuickbarSize', function()
        if UI and UI.ApplyScale then UI:ApplyScale() end
    end)
end
