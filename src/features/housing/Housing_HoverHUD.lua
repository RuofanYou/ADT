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
-- 注意：专家/基础模式有不同的 IsDecorSelected，这里统一封装为单一权威
local function IsAnyDecorSelected()
    local mode = GetActiveHouseEditorMode and GetActiveHouseEditorMode()
    if mode == (Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.ExpertDecor) then
        if C_HousingExpertMode and C_HousingExpertMode.IsDecorSelected then
            return not not C_HousingExpertMode.IsDecorSelected()
        end
    else
        if C_HousingBasicMode and C_HousingBasicMode.IsDecorSelected then
            return not not C_HousingBasicMode.IsDecorSelected()
        end
    end
    return false
end
-- 注意：SetPlacedDecorEntryHovered 是受保护 API，不能被第三方插件使用

local DisplayFrame

-- 模式判断工具：是否处于专家模式
local function InExpertMode()
    local mode = GetActiveHouseEditorMode and GetActiveHouseEditorMode()
    return mode == (Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.ExpertDecor)
end

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

    -- 统一样式访问（单一权威）：强制从 Housing_Config.lua 暴露的 ADT.HousingInstrCFG 读取
    local function GetCFG()
        return assert(ADT and ADT.HousingInstrCFG, "ADT.HousingInstrCFG 缺失：请确认 Housing_Config.lua 已加载")
    end

    -- 计算并设置顶层 DisplayFrame 的高度，使其完整包裹自建的子行
    function DisplayFrameMixin:RecalculateHeight()
        local CFG = GetCFG(); if not CFG or not CFG.Row then return end
        if not self.InstructionText then
            -- 作为容器：按“可见子行数量”计算整体高度
            local rowH = math.max(tonumber(CFG.Row.minHeight or 0) or 0, tonumber(CFG.Control and CFG.Control.height or 0) or 0)
            local gap  = math.abs(CFG.Row.vSpacing or 0)
            local n = 0
            local function vshown(f) return f and f.IsShown and f:IsShown() end
            if self.SubFrame and vshown(self.SubFrame) then n = n + 1 end
            if self.HintFrames then
                for _, f in ipairs(self.HintFrames) do if vshown(f) then n = n + 1 end end
            end
            if n == 0 then n = 1 end
            local total = n * rowH + (n - 1) * gap
            self:SetHeight(total)
            if ADT and ADT.DockUI and ADT.DockUI.RequestSubPanelAutoResize then
                ADT.DockUI.RequestSubPanelAutoResize()
            end
            local parent = self:GetParent()
            if parent and parent.UpdateLayout then pcall(parent.UpdateLayout, parent) end
            return
        end
        -- 行：按统一行高与间距估算高度
        local rowH = math.max(tonumber(CFG.Row.minHeight or 0) or 0, tonumber(CFG.Control and CFG.Control.height or 0) or 0)
        local gap = math.abs(CFG.Row.vSpacing or 0)
        local total = rowH
        local function vshown(f) return f and f.IsShown and f:IsShown() end
        if self.SubFrame and vshown(self.SubFrame) then total = total + rowH + gap end
        if self.HintFrames then
            for _, f in ipairs(self.HintFrames) do
                if vshown(f) then total = total + rowH + gap end
            end
        end
        total = total - gap
        if total < rowH then total = rowH end
        self:SetHeight(total)
        local parent = self:GetParent()
        if parent and parent.UpdateLayout then pcall(parent.UpdateLayout, parent) end
        if ADT and ADT.DockUI and ADT.DockUI.RequestSubPanelAutoResize then
            ADT.DockUI.RequestSubPanelAutoResize()
        end
    end

    function DisplayFrameMixin:SetHotkey(instruction, bindingText)
        -- 文本内容
        if self.InstructionText then self.InstructionText:SetText(instruction) end
        if self.Control and self.Control.Text then self.Control.Text:SetText(bindingText) end
        -- 仅控制“显示哪种形态”：使用键帽文本，不用鼠标图标
        if self.Control and self.Control.Text then self.Control.Text:Show() end
        if self.Control and self.Control.Background then self.Control.Background:Show() end
        if self.Control and self.Control.Icon then self.Control.Icon:Hide() end
        -- 样式（字号/行高/间距/键帽宽度）全部交给唯一权威 ADT.ApplyHousingInstructionStyle 处理，避免二次缩放
        if ADT and ADT.ApplyHousingInstructionStyle then ADT.ApplyHousingInstructionStyle(self) end
    end

    function DisplayFrameMixin:OnLoad()
        self.alpha = 0
        self:SetAlpha(0)

        -- 改为跟随父容器缩放，保证与 Dock 子面板同一坐标系，避免右侧键帽越界
        pcall(function()
            if self.SetIgnoreParentScale then self:SetIgnoreParentScale(false) end
        end)

        -- 需求：顶部这一行仅显示“装饰名(+库存)”，不显示任何鼠标类图标/键帽
        if self.Control and self.Control.Icon then self.Control.Icon:Hide() end
        if self.Control and self.Control.Background then self.Control.Background:Hide() end
        if self.Control and self.Control.Text then self.Control.Text:Hide() end
        -- 注意：这里若设置为 HOUSING_DECOR_SELECT_INSTRUCTION，会在
        -- Housing_BlizzardGraft.lua 的 stripLine() 中被识别为“官方选择装饰行”而强制隐藏，
        -- 导致我们自建的 HoverHUD 整块不可见。为避免被误杀，初始化为""，
        -- 实际悬停时会由 SetDecorInfo() 把装饰名同步到右侧 Header，不依赖本行文本。
        self.InstructionText:SetText("")
        -- 字体交由 Housing_BlizzardGraft 的统一样式驱动，不在本地强制覆盖
        if self.InstructionText.SetJustifyV then self.InstructionText:SetJustifyV("MIDDLE") end
        -- 容器（VerticalLayoutFrame）不设置左右内边距，避免与行级 leftPadding/rightPadding 叠加。
        -- 仅维持行间距，其他都交给 BlizzardGraft 的样式在“行级”生效（单一权威）。
        local parent = self:GetParent()
        if parent then
            parent.leftPadding = 0
            parent.rightPadding = 0
            local cfg = ADT and ADT.HousingInstrCFG
            parent.spacing = (cfg and cfg.Row and cfg.Row.vSpacing) or 0
            if parent.MarkDirty then parent:MarkDirty() end
            if parent.Layout then pcall(parent.Layout, parent) end
            if parent.UpdateLayout then pcall(parent.UpdateLayout, parent) end
        end
    end

    local function FadeIn_OnUpdate(self, elapsed)
        -- 兼容：某些使用 FadeMixin 的“代理帧”（如 Header 专用 fader）
        -- 并未调用 OnLoad 初始化 alpha，此处以当前可见 Alpha 作为起点。
        local cur = tonumber(self.alpha)
        if cur == nil then
            cur = (self.GetAlpha and self:GetAlpha()) or 0
        end
        self.alpha = cur + 5 * (elapsed or 0)
        if self.alpha >= 1 then
            self.alpha = 1
            self:SetScript("OnUpdate", nil)
        end
        self:SetAlpha(self.alpha)
        -- 与下方面板标题严格同步 alpha
        if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
            ADT.DockUI.SetSubPanelHeaderAlpha(self.alpha)
        end
    end

    local function FadeOut_OnUpdate(self, elapsed)
        local cur = tonumber(self.alpha)
        if cur == nil then
            cur = (self.GetAlpha and self:GetAlpha()) or 0
        end
        self.alpha = cur - 2 * (elapsed or 0)
        if self.alpha <= 0 then
            self.alpha = 0
            self:SetScript("OnUpdate", nil)
        end
        if self.alpha > 1 then
            self:SetAlpha(1)
            if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
                ADT.DockUI.SetSubPanelHeaderAlpha(1)
            end
        else
            self:SetAlpha(self.alpha)
            if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
                ADT.DockUI.SetSubPanelHeaderAlpha(self.alpha)
            end
        end
    end

    function DisplayFrameMixin:FadeIn()
        -- 若 alpha 未初始化，则以当前可见 Alpha 作为起点，避免 nil 运算
        if self.alpha == nil then
            local a = (self.GetAlpha and self:GetAlpha()) or 0
            self.alpha = tonumber(a) or 0
        end
        if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
            ADT.DockUI.SetSubPanelHeaderAlpha(0)
        end
        self:SetScript("OnUpdate", FadeIn_OnUpdate)
    end

    function DisplayFrameMixin:FadeOut(delay)
        if self.alpha == nil then
            local a = (self.GetAlpha and self:GetAlpha()) or 0
            self.alpha = tonumber(a) or 0
        end
        if delay then
            self.alpha = 2
        end
        self:SetScript("OnUpdate", FadeOut_OnUpdate)
    end

    -- 向外暴露与“说明行”一致的淡入/淡出方法，供其它控件（如右侧 Header.Label）复用。
    if ADT and ADT.Housing then
        ADT.Housing.FadeMixin = ADT.Housing.FadeMixin or {}
        if not ADT.Housing.FadeMixin.FadeIn then
            ADT.Housing.FadeMixin.FadeIn = function(self, ...) return DisplayFrameMixin.FadeIn(self, ...) end
        end
        if not ADT.Housing.FadeMixin.FadeOut then
            ADT.Housing.FadeMixin.FadeOut = function(self, ...) return DisplayFrameMixin.FadeOut(self, ...) end
        end
    end

    function DisplayFrameMixin:SetDecorInfo(decorInstanceInfo)
        -- 检查是否受保护，如果是则在名称前添加锁图标（使用 BonusChest-Lock atlas）
        local displayName = decorInstanceInfo.name or ""
        if EL and EL.Protection and EL.Protection.IsProtected then
            local isProtected = EL.Protection:IsProtected(decorInstanceInfo.decorGUID, decorInstanceInfo.decorID)
            if isProtected then
                -- 使用 |A:atlas:height:width|a 格式显示atlas图标
                displayName = "|A:BonusChest-Lock:16:16|a " .. displayName
            end
        end
        -- 行内不再显示装饰名（避免与右侧标题重复）；本行仅承担库存数字展示
        self.InstructionText:SetText("")
        -- 同步到 Dock 下方面板 Header：用与“操作说明”同一字号/字色的标题显示当前悬停装饰名
        if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderText then
            ADT.DockUI.SetSubPanelHeaderText(displayName)
            if ADT.DockUI.SetSubPanelHeaderAlpha then
                ADT.DockUI.SetSubPanelHeaderAlpha(self.alpha or 0)
            end
        end
        
        local decorID = decorInstanceInfo.decorID
        local entryInfo = GetCatalogDecorInfo(decorID)
        local stored = 0
        if entryInfo then
            stored = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
        end
        self.ItemCountText:SetText(stored)
        self.ItemCountText:SetShown(stored > 0)
        
        -- 单一权威：始终由 UpdateHintVisibility 控制各提示行的显隐
        -- 不再无条件显示，而是读取唯一的设置数据
        EL:UpdateHintVisibility()
    end
end

local function Blizzard_HouseEditor_OnLoaded()
    local container = HouseEditorFrame.BasicDecorModeFrame.Instructions
    for _, v in ipairs(container.UnselectedInstructions) do
        v:Hide()
    end
    container.UnselectedInstructions = {}

    if not DisplayFrame then
        -- 改为“垂直布局容器”，其子项为若干条与暴雪一致的行模板。
        -- 这样所有行的行间距/左右对齐完全由 VerticalLayout + 统一样式驱动，杜绝初始与二次刷新不一致。
        -- 重要：避免将 DisplayFrame 直接挂在 Instructions 容器下，否则其缺少
        -- HouseEditorInstructionMixin:UpdateVisuals/UpdateControl 等方法，
        -- 会在容器的 CallOnChildrenThenUpdateLayout 中被调用而报错。
        -- 初始挂到 HouseEditorFrame（编辑器级父容器），稍后由 Graft 调用
        -- ADT.Housing:ReparentHoverHUD() 迁移到 Dock 下方面板。
        DisplayFrame = CreateFrame("Frame", nil, HouseEditorFrame, "VerticalLayoutFrame")
        -- 容器不设左右内边距（避免与行级 left/rightPadding 叠加），仅设置行间距。
        do
            local cfg = ADT and ADT.HousingInstrCFG
            DisplayFrame.leftPadding = 0
            DisplayFrame.rightPadding = 0
            DisplayFrame.spacing = (cfg and cfg.Row and cfg.Row.vSpacing) or 0
        end
        -- 初次创建即按统一权威样式应用，尽量减少“首帧未贴齐”
        if ADT and ADT.ApplyHousingInstructionStyle then ADT.ApplyHousingInstructionStyle(DisplayFrame) end
        DisplayFrame.expand = true
        -- 组级淡入/淡出控制（对子项统一 Alpha），避免仅子行褪色导致快捷键常驻可见
        -- 当前组透明度（0~1）。
        DisplayFrame._alpha = 0
        -- 淡出前的延时（秒），独立于 alpha，避免用“>1 的 alpha”临时代码带来的闪烁。
        DisplayFrame._fadeDelay = 0
        function DisplayFrame:SetGroupAlpha(a)
            a = tonumber(a) or 0
            if a < 0 then a = 0 elseif a > 1 then a = 1 end
            if self.SubFrame and self.SubFrame.SetAlpha then self.SubFrame:SetAlpha(a) end
            if self.HintFrames then
                for _, f in ipairs(self.HintFrames) do
                    if f and f.SetAlpha then f:SetAlpha(a) end
                end
            end
            self._alpha = a
        end
        DisplayFrame:SetGroupAlpha(0)
        -- 读取淡入/淡出节奏配置（配置为单一权威，见 Housing_Config.lua）
        local function GetFadeCFG()
            local cfg = ADT and ADT.HousingInstrCFG
            local fading = cfg and cfg.Fading or nil
            return {
                fadeInInstant = not (fading and fading.fadeInInstant == false),
                fadeInRate    = (fading and fading.fadeInRate) or 8,   -- 秒^-1
                fadeOutRate   = (fading and fading.fadeOutRate) or 3,  -- 秒^-1
            }
        end
        local function GroupFadeOut_OnUpdate(self, elapsed)
            local cfg = GetFadeCFG()
            -- 若设置了延时，则先倒计时，不改变当前可见度
            if (self._fadeDelay or 0) > 0 then
                self._fadeDelay = math.max(0, (self._fadeDelay or 0) - (elapsed or 0))
                return
            end
            local nextA = (self._alpha or 1) - (cfg.fadeOutRate or 3) * (elapsed or 0)
            if nextA <= 0 then
                self:SetGroupAlpha(0)
                self:SetScript("OnUpdate", nil)
            else
                self:SetGroupAlpha(nextA)
            end
            if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha
               and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
                ADT.DockUI.SetSubPanelHeaderAlpha(self._alpha)
            end
            -- 淡出也触发一次，以便在完全隐藏后收缩子面板高度
            if ADT and ADT.DockUI and ADT.DockUI.RequestSubPanelAutoResize then
                ADT.DockUI.RequestSubPanelAutoResize()
            end
        end
        function DisplayFrame:FadeInGroup()
            -- 专家模式下彻底不使用“悬停驱动”的 Header alpha
            if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow and ADT.DockUI.SetSubPanelHeaderAlpha then
                if not InExpertMode() then
                    ADT.DockUI.SetHeaderAlphaFollow(true)
                    -- 悬停开始即满不透明，避免“先半透明”的错觉
                    ADT.DockUI.SetSubPanelHeaderAlpha(1)
                end
            end
            local cfg = GetFadeCFG()
            if cfg.fadeInInstant then
                self._fadeDelay = 0
                self:SetGroupAlpha(1)
                self:SetScript("OnUpdate", nil)
            else
                -- 若需要动画淡入（可配置），采用给定速度向 1 逼近
                self:SetScript("OnUpdate", function(s, elapsed)
                    local rate = (GetFadeCFG().fadeInRate or 8)
                    local nextA = (s._alpha or 0) + rate * (elapsed or 0)
                    if nextA >= 1 then
                        s:SetGroupAlpha(1)
                        s:SetScript("OnUpdate", nil)
                    else
                        s:SetGroupAlpha(nextA)
                    end
                    if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha
                       and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
                        ADT.DockUI.SetSubPanelHeaderAlpha(s._alpha)
                    end
                    if ADT and ADT.DockUI and ADT.DockUI.RequestSubPanelAutoResize then
                        ADT.DockUI.RequestSubPanelAutoResize()
                    end
                end)
            end
        end
        function DisplayFrame:FadeOutGroup(delay)
            -- 仅记录延时，不再通过“alpha>1”实现延迟，避免离开时突变为完全可见
            self._fadeDelay = tonumber(delay) or 0
            self:SetScript("OnUpdate", GroupFadeOut_OnUpdate)
        end
        -- 关键工具：立刻停止一切淡入/淡出并把整组提示隐藏（透明度归零）
        -- 用于“瞬时切换到其它状态（如选中/切换模式）”时避免文本叠层。
        function DisplayFrame:InstantHideGroup()
            -- 停止组级 OnUpdate
            self:SetScript("OnUpdate", nil)
            -- 终止子行的 OnUpdate 并置零透明度
            local function kill(f)
                if not f then return end
                if f.SetScript then f:SetScript("OnUpdate", nil) end
                if f.SetAlpha then f:SetAlpha(0) end
                if f.alpha then f.alpha = 0 end
            end
            kill(self.SubFrame)
            if self.HintFrames then for _, ch in ipairs(self.HintFrames) do kill(ch) end end
            if self.SetGroupAlpha then self:SetGroupAlpha(0) end
            -- 保持与右侧 Header alpha 同步（若处于跟随模式）
            if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha
               and ADT.DockUI.IsHeaderAlphaFollowEnabled and ADT.DockUI.IsHeaderAlphaFollowEnabled() then
                ADT.DockUI.SetSubPanelHeaderAlpha(0)
            end
        end
        -- 跟随父容器缩放（Dock 子面板）；之前强制忽略父缩放会导致与内容区像素系不一致，
        -- 右侧键帽相对“弹窗内部右缘”的对齐出现偏差
        pcall(function()
            if DisplayFrame.SetIgnoreParentScale then DisplayFrame:SetIgnoreParentScale(false) end
        end)

        local SubFrame = CreateFrame("Frame", nil, DisplayFrame, "ADT_HouseEditorInstructionTemplate")
        DisplayFrame.SubFrame = SubFrame
        Mixin(SubFrame, DisplayFrameMixin)
        SubFrame:OnLoad()
        -- 默认显示 CTRL+D，兼容旧版通过 ADT.GetDuplicateKeyName() 返回文本
        SubFrame:SetHotkey(L["Duplicate"] or "Duplicate", (ADT.GetDuplicateKeyName and ADT.GetDuplicateKeyName()) or "CTRL+D")
        if SubFrame.LockStatusText then SubFrame.LockStatusText:Hide() end

        -- 追加：显示其它热键提示（Ctrl+X / C / V / S / R / 批量放置）
        DisplayFrame.HintFrames = {}
        local CTRL = CTRL_KEY_TEXT or "CTRL"
        local function addHint(prev, label, key)
            local line = CreateFrame("Frame", nil, DisplayFrame, "ADT_HouseEditorInstructionTemplate")
            -- 不再手动 SetPoint，交由 VerticalLayoutFrame 根据 spacing 自动排布
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
            -- 废弃“自定义统一键帽宽度”的实现，改为完全依赖 ADT.ApplyHousingInstructionStyle
            -- 根据内容宽度与行内文本自动收缩键帽（单一权威）。
            if ADT and ADT.ApplyHousingInstructionStyle then ADT.ApplyHousingInstructionStyle(self) end
            if self.RecalculateHeight then self:RecalculateHeight() end
        end

        -- 统一样式：延后由 ADT.ApplyHousingInstructionStyle 应用（加载顺序可能晚于本文件）
        if ADT and ADT.ApplyHousingInstructionStyle then ADT.ApplyHousingInstructionStyle(DisplayFrame) end
        DisplayFrame:NormalizeKeycapWidth()
        if DisplayFrame.RecalculateHeight then DisplayFrame:RecalculateHeight() end
        -- 关键：在子行全部创建完之后，再次统一设为透明，避免初始常驻
        if DisplayFrame.SetGroupAlpha then DisplayFrame:SetGroupAlpha(0) end
    end

    -- 不再把 DisplayFrame 塞进 Instructions 的 Unselected 列表，
    -- 等到被重挂到 Dock 时再按需告知（见 ReparentHoverHUD）。
    -- container.UnselectedInstructions = { DisplayFrame }

        if IsAnyDecorSelected() then
        DisplayFrame:Hide()
    end
end

-- 允许 Blizzard_Graft 在“采纳/切换模式后”把 HoverHUD 挂到当前正在使用的 Instructions 容器下
-- 解决：当活跃模式不是 Basic 时，原先挂在 Basic.Instructions 下的 HoverHUD 不可见的问题。
function EL:ReparentHoverHUD(newParent)
    if not (DisplayFrame and newParent and newParent.GetName) then return end
    local cur = DisplayFrame:GetParent()
    if cur == newParent then return end
    DisplayFrame:ClearAllPoints()
    DisplayFrame:SetParent(newParent)
    -- 明确锚到“Header 下方”，避免被标题遮挡；高度由 RecalculateHeight 驱动
    DisplayFrame:ClearAllPoints()
    local headerGap = 0
    local header
    pcall(function()
        local dock = ADT.CommandDock and ADT.CommandDock.SettingsPanel
        local sub  = dock and (dock.SubPanel or (dock.EnsureSubPanel and dock:EnsureSubPanel()))
        header = sub and sub.Header
    end)
    do
        local cfg = ADT and ADT.HousingInstrCFG
        headerGap = (cfg and cfg.Layout and tonumber(cfg.Layout.headerToInstrGap)) or 8
    end
    if header then
        DisplayFrame:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, -headerGap)
        DisplayFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -headerGap)
    else
        DisplayFrame:SetPoint("TOPLEFT",  newParent, "TOPLEFT",  0, -30)
        DisplayFrame:SetPoint("TOPRIGHT", newParent, "TOPRIGHT", 0, -30)
    end
    DisplayFrame.expand = true
    -- 提升层级：确保悬停提示绘制在官方 Instructions 之上（不被遮挡）
    pcall(function()
        local strata = newParent:GetFrameStrata() or "DIALOG"
        DisplayFrame:SetFrameStrata(strata)
        DisplayFrame:SetFrameLevel((newParent:GetFrameLevel() or 1) + 20)
    end)
    -- 再次同步容器行距（容器左右内边距保持 0，避免与“行级内边距”叠加）
    do
        local cfg = ADT and ADT.HousingInstrCFG
        DisplayFrame.leftPadding = 0
        DisplayFrame.rightPadding = 0
        DisplayFrame.spacing = (cfg and cfg.Row and cfg.Row.vSpacing) or 0
        if DisplayFrame.MarkDirty then DisplayFrame:MarkDirty() end
        if DisplayFrame.Layout then pcall(DisplayFrame.Layout, DisplayFrame) end
        if DisplayFrame.UpdateLayout then pcall(DisplayFrame.UpdateLayout, DisplayFrame) end
    end
    -- 与官方行保持同样的缩放策略（忽略父缩放）
    pcall(function()
        if DisplayFrame.SetIgnoreParentScale then DisplayFrame:SetIgnoreParentScale(false) end
        for _, ch in ipairs({DisplayFrame:GetChildren()}) do
            if ch.SetIgnoreParentScale then ch:SetIgnoreParentScale(false) end
        end
    end)
    -- 告诉 Instructions 容器：本帧即为“未选中状态”的唯一说明行（单一权威）
    pcall(function()
        if type(newParent.UnselectedInstructions) ~= 'table' then newParent.UnselectedInstructions = {} end
        wipe(newParent.UnselectedInstructions)
        table.insert(newParent.UnselectedInstructions, DisplayFrame)
        if newParent.UpdateAllVisuals then newParent:UpdateAllVisuals() end
        if newParent.UpdateLayout then newParent:UpdateLayout() end
    end)
    if DisplayFrame.NormalizeKeycapWidth then DisplayFrame:NormalizeKeycapWidth() end
    if ADT and ADT.ApplyHousingInstructionStyle then ADT.ApplyHousingInstructionStyle(DisplayFrame) end
    -- 关键：尺寸变化时强制重算键帽宽度与左右留白（修复“HoverHUD 不贴右”的根因：
    -- 初次 Reparent 后父容器在下一帧才会拉伸到最终宽度）。
    if newParent.HookScript and not DisplayFrame._hookedForResize then
        DisplayFrame._hookedForResize = true
        newParent:HookScript("OnSizeChanged", function()
            if ADT and ADT.ApplyHousingInstructionStyle then ADT.ApplyHousingInstructionStyle(DisplayFrame) end
            if DisplayFrame.NormalizeKeycapWidth then DisplayFrame:NormalizeKeycapWidth() end
            if DisplayFrame.RecalculateHeight then DisplayFrame:RecalculateHeight() end
        end)
    end
    DisplayFrame:Show()
    -- 初次重挂后保持隐藏状态，等待真正的悬停再淡入
    if DisplayFrame.SetGroupAlpha then DisplayFrame:SetGroupAlpha(0) end
    -- 重新应用一次显隐与标题联动
    if self.UpdateHintVisibility then self:UpdateHintVisibility() end
    if DisplayFrame.RecalculateHeight then DisplayFrame:RecalculateHeight() end
end

--
-- 事件监听与核心逻辑
--
do
    EL.dynamicEvents = {
        "HOUSE_EDITOR_MODE_CHANGED",
        -- 悬停：基础/专家模式均需要显示装饰名
        "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED",
        "HOUSING_EXPERT_MODE_HOVERED_TARGET_CHANGED",
        -- 选中：基础/专家模式
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
        -- 专家模式下完全忽略悬停事件
        if InExpertMode() and (event == "HOUSING_EXPERT_MODE_HOVERED_TARGET_CHANGED" or event == "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED") then
            return
        end
        if event == "HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED" or event == "HOUSING_EXPERT_MODE_HOVERED_TARGET_CHANGED" then
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
        -- 统一：选中/取消选中都要处理 UI
        if not hasSelected then
            -- 取消选中：若仍在悬停，则不做淡出，直接交回“悬停跟随”；否则才淡出
            -- 专家模式下：若 API 抖动产生假“未选中”，但实际仍选中（IsAnyDecorSelected=true），则忽略
            if InExpertMode() and IsAnyDecorSelected() then return end
            local hovered = IsHoveringDecor() and GetHoveredDecorInfo()
            if hovered and hovered.name then
                if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then ADT.DockUI.SetHeaderAlphaFollow(true) end
                if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderText then ADT.DockUI.SetSubPanelHeaderText(hovered.name) end
                -- alpha 后续由悬停 OnUpdate 统一驱动
            else
                if ADT and ADT.DockUI and ADT.DockUI.FadeOutHeader then ADT.DockUI.FadeOutHeader(0.5) end
                -- 悬停恢复后再由 OnUpdate 接手
            end
            return
        end
        -- 进入“选中”态：
        if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then ADT.DockUI.SetHeaderAlphaFollow(false) end
        if DisplayFrame and DisplayFrame.InstantHideGroup then DisplayFrame:InstantHideGroup() end
        -- 检查开关是否启用（仅用于“误操作保护”拦截；显示标题不受此开关影响）
        local protectionEnabled = ADT.GetDBValue("EnableProtection")
        if protectionEnabled == nil then protectionEnabled = true end
        
        -- 获取选中装饰的信息
        local info = (C_HousingBasicMode and C_HousingBasicMode.GetSelectedDecorInfo and C_HousingBasicMode.GetSelectedDecorInfo())
            or (C_HousingExpertMode and C_HousingExpertMode.GetSelectedDecorInfo and C_HousingExpertMode.GetSelectedDecorInfo())
        if info and info.name then
            -- 切换到“选中”态时的标题策略：
            -- 1) 若名称不变，仅“补完”正在进行的淡入（从当前 alpha 继续到 1），不重播；
            -- 2) 若名称改变，则直接换文案，保持当前 alpha，不触发额外淡入/淡出；
            local headerText = ADT and ADT.DockUI and ADT.DockUI.GetSubPanelHeaderText and ADT.DockUI.GetSubPanelHeaderText()
            local headerAlpha = ADT and ADT.DockUI and ADT.DockUI.GetSubPanelHeaderAlpha and ADT.DockUI.GetSubPanelHeaderAlpha()
            local sameName = (headerText == info.name)
            if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then ADT.DockUI.SetHeaderAlphaFollow(false) end
            if not sameName then
                -- 修复：专家模式切换到“不同名称”的装饰时，若此前 Header 仍在执行“淡出”
                --（例如来自悬停阶段的 FadeOutHeader 计时器），仅设置新文本无法停止旧动画，
                -- 会出现“标题短暂显示后又自己淡出”的错觉。
                -- 方案：名称变化时也显式触发一次 Header 淡入（从当前 Alpha 补完），
                -- 以此终止任何正在运行的淡出并保证标题常亮。
                if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderText then
                    ADT.DockUI.SetSubPanelHeaderText(info.name)
                end
                if ADT and ADT.DockUI and ADT.DockUI.FadeInHeader then
                    ADT.DockUI.FadeInHeader(true) -- 从当前 Alpha 补完到 1，并取消旧的 OnUpdate
                end
            else
                if (tonumber(headerAlpha) or 0) < 1 then
                    if ADT and ADT.DockUI and ADT.DockUI.FinishHeaderFadeIn then ADT.DockUI.FinishHeaderFadeIn() end
                end
            end
            -- 专家模式下：标题常亮，不受悬停影响
            if InExpertMode() then
                if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderAlpha then ADT.DockUI.SetSubPanelHeaderAlpha(1) end
            end
        end
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
        -- 专家模式：直接忽略所有悬停变化（不驱动任何 UI）
        if InExpertMode() then return end
        if hasHoveredTarget then
            -- 未选中时才切回“跟随悬停”；选中状态保持 Header 由专用 fader 管控
            if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then
                ADT.DockUI.SetHeaderAlphaFollow(not IsAnyDecorSelected())
            end
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
                -- 如果此时用户发生“选中/切换模式”，立即隐藏以避免叠层；
                -- 否则正常走淡出。
                if IsAnyDecorSelected() then
                    -- 保留当前 Header Alpha：先退出跟随再隐藏组
                    if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then ADT.DockUI.SetHeaderAlphaFollow(false) end
                    if DisplayFrame.InstantHideGroup then DisplayFrame:InstantHideGroup() end
                else
                    if DisplayFrame.FadeOutGroup then DisplayFrame:FadeOutGroup(0.5) end
                end
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
                -- 若处于“选中”状态：不启用 Header 跟随，也不重放悬停淡入；仅保留当前选中标题
                if IsAnyDecorSelected() then
                    if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then
                        ADT.DockUI.SetHeaderAlphaFollow(false)
                    end
                    return true
                end
                -- 智能跟随：
                -- 若标题文本与当前悬停名称一致且已完全可见，则不再切回“跟随”，
                -- 以避免重复将 Header alpha 拉回 0 造成二次淡入；否则进入跟随模式。
                do
                    local curText = ADT and ADT.DockUI and ADT.DockUI.GetSubPanelHeaderText and ADT.DockUI.GetSubPanelHeaderText()
                    local curAlpha = ADT and ADT.DockUI and ADT.DockUI.GetSubPanelHeaderAlpha and ADT.DockUI.GetSubPanelHeaderAlpha() or 0
                    local shouldFollow = not (curText == (info.name or "") and (tonumber(curAlpha) or 0) >= 0.99)
                    if ADT and ADT.DockUI and ADT.DockUI.SetHeaderAlphaFollow then
                        ADT.DockUI.SetHeaderAlphaFollow(shouldFollow)
                    end
                end
                -- 仅在使用“修饰键触发”模式时监听（Ctrl/Alt 直接松开触发）。
                if self.dupeEnabled and self.dupeKey then
                    self:RegisterEvent("MODIFIER_STATE_CHANGED")
                end
                self.decorInstanceInfo = info
                if DisplayFrame then
                    -- 统一由组级淡入驱动，避免先只显示第一行（“重复”）再显示其它行
                    if DisplayFrame.FadeInGroup then DisplayFrame:FadeInGroup() end
                    -- 悬停新增可见内容后，立即请求 SubPanel 自适应一次（随后还会在淡入过程中多次触发）
                    if ADT and ADT.DockUI and ADT.DockUI.RequestSubPanelAutoResize then
                        ADT.DockUI.RequestSubPanelAutoResize()
                    end
                    -- 更新右侧标题与库存数量（仅数据更新，不篡改 SubFrame 的 InstructionText）
                    if ADT and ADT.DockUI and ADT.DockUI.SetSubPanelHeaderText then
                        local name = info.name or ""
                        -- 若该装饰被保护，标题前加锁图标（与旧实现保持一致）
                        if EL and EL.Protection and EL.Protection.IsProtected and info.decorGUID then
                            local isProt = EL.Protection:IsProtected(info.decorGUID, info.decorID)
                            if isProt then name = "|A:BonusChest-Lock:16:16|a " .. name end
                        end
                        ADT.DockUI.SetSubPanelHeaderText(name)
                    end
                    -- 更新库存数字到 SubFrame 的 ItemCountText
                    local decorID = info.decorID
                    local entryInfo = decorID and GetCatalogDecorInfo(decorID)
                    local stored = 0
                    if entryInfo then
                        stored = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
                    end
                    if DisplayFrame.SubFrame and DisplayFrame.SubFrame.ItemCountText then
                        DisplayFrame.SubFrame.ItemCountText:SetText(stored)
                        DisplayFrame.SubFrame.ItemCountText:SetShown(stored > 0)
                    end
                end
                return true
            end
        end
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        if DisplayFrame and DisplayFrame.FadeOutGroup then DisplayFrame:FadeOutGroup(0.5) end
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
        if IsAnyDecorSelected() then return end

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
        -- 切换基础/专家/自定义等模式时，暴雪会刷新右侧说明。
        -- 为做到“无缝衔接”，这里即时清空我们自绘的 HoverHUD，交给新模式接管。
        if DisplayFrame and DisplayFrame.InstantHideGroup then
            DisplayFrame:InstantHideGroup()
        end
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
            if ADT and ADT.ApplyHousingInstructionStyle then
                ADT.ApplyHousingInstructionStyle(DisplayFrame)
            end
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
        
        -- 按“可见行”链式锚点（与旧实现一致），避免部分环境下 VerticalLayout 首帧不排版
        -- 注意：仍由统一样式器控制左右留白/键帽宽度，此处只负责垂直堆叠。
        local CFG = ADT and ADT.HousingInstrCFG
        local ygap = (CFG and CFG.Row and tonumber(CFG.Row.vSpacing)) or 0
        local prevVisible = DisplayFrame
        for i, frame in ipairs(allFrames) do
            local visible = visibilityConfig[i]
            frame:SetShown(visible)
            frame.ignoreInLayout = true  -- 交由我们手工锚点
            frame:ClearAllPoints()
            if visible then
                -- 关键修复：上一版只锚到 TOPRIGHT，行本身没有固定宽度时（例如父容器宽度尚未
                -- 完成布局，GetWidth 返回 0），row 的 LEFT 会贴近 RIGHT，导致左侧文本看上去
                -- “靠着键帽挤在一起”。这里同步锚 TOPLEFT 到上一行的 BOTTOMLEFT，保证行宽由
                -- 父容器左右边界确定，即刻拥有稳定宽度，随后再由样式器计算左列与键帽的边界。
                frame:SetPoint("TOPRIGHT", prevVisible, "BOTTOMRIGHT", 0, -ygap)
                frame:SetPoint("TOPLEFT",  prevVisible, "BOTTOMLEFT",  0, -ygap)
                -- 同帧补一把：若样式器已加载，立即按“单一权威”应用一次，确保键帽贴右。
                if ADT and ADT.ApplyHousingInstructionStyle then
                    ADT.ApplyHousingInstructionStyle(frame)
                end
                prevVisible = frame
            end
        end

        -- 触发布局与统一样式应用，确保宽度、左右留白与键帽收缩即时生效
        if ADT and ADT.ApplyHousingInstructionStyle then
            ADT.ApplyHousingInstructionStyle(DisplayFrame)
        end
        if DisplayFrame then
            if DisplayFrame.RecalculateHeight then DisplayFrame:RecalculateHeight() end
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
        if ADT and ADT.ApplyHousingInstructionStyle then
            ADT.ApplyHousingInstructionStyle(DisplayFrame)
        end
        if ADT and ADT.ApplyHousingInstructionStyle then
            ADT.ApplyHousingInstructionStyle(DisplayFrame)
        end
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
