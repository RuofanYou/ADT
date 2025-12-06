local ADDON_NAME, ADT = ...

-- 仅实现我们现有的“装饰复制”设置，界面结构参考 Referrence/Plumber：
-- - 独立主框体（可居中显示，ESC 关闭）
-- - 在暴雪设置（Settings）中作为画布分类嵌入（外观与布局复用同一套）

ADT = ADT or {}
ADT.UI = ADT.UI or {}

local UI = ADT.UI
local L = ADT.L or {}

local function CreateMainFrame()
    local f = CreateFrame("Frame", "ADTSettingsMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(680, 520)
    f:SetPoint("CENTER")
    f:Hide()

    -- 背景与边框（使用通用 NineSlice，避免依赖外部素材）
    f:SetBackdrop({
        bgFile = "Interface/FrameGeneral/UI-Background-Rock",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 64, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.9)

    -- 标题栏
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("AdvancedDecorationTools")
    f.Title = title

    -- 关闭按钮
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)
    f.CloseButton = close

    -- 左侧区域标题（模拟 Plumber 左列）
    local leftTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
    leftTitle:SetText(L["ModuleName Housing_DecorHover"] or "住宅：名称与复制")

    -- 描述
    local desc = f:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    desc:SetPoint("TOPLEFT", leftTitle, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(2)
    desc:SetText(L["ModuleDescription Housing_DecorHover"] or "")
    f.Description = desc

    -- 复选：启用复制
    local enable = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
    enable:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -18)
    -- 自建标签，避免模板 Text/text 差异
    local enableLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    enableLabel:SetPoint("LEFT", enable, "RIGHT", 4, 0)
    enableLabel:SetText(L["Enable Duplicate"] or "启用 \"复制\"")
    enable:SetHitRectInsets(0, -enableLabel:GetStringWidth() - 8, 0, 0)
    enable:SetChecked(ADT.GetDBBool("EnableDupe"))
    enable:SetScript("OnClick", function(self)
        ADT.SetDBValue("EnableDupe", self:GetChecked())
        if ADT.Housing and ADT.Housing.LoadSettings then
            ADT.Housing:LoadSettings()
        end
    end)

    local enableTip = L["Enable Duplicate tooltip"]
    if enableTip and enableTip ~= "" then
        enable:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(enableLabel:GetText(), 1, 1, 1)
            GameTooltip:AddLine(enableTip, 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        enable:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- 单选：热键选择
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -16)
    header:SetText(L["Duplicate Decor Key"] or "\"复制\" 热键")

    local r1, r2

    local function CreateRadio(text, idx, x)
        local b = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
        b:SetPoint("TOPLEFT", header, "BOTTOMLEFT", x or 0, -8)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", b, "RIGHT", 4, 0)
        label:SetText(text)
        b:SetHitRectInsets(0, -label:GetStringWidth() - 8, 0, 0)
        b:SetChecked((ADT.GetDBValue("DuplicateKey") or 2) == idx)
        b:SetScript("OnClick", function(self)
            ADT.SetDBValue("DuplicateKey", idx)
            r1:SetChecked(idx == 1)
            r2:SetChecked(idx == 2)
            if ADT.Housing and ADT.Housing.LoadSettings then
                ADT.Housing:LoadSettings()
            end
        end)
        return b
    end

    r1 = CreateRadio(CTRL_KEY_TEXT or "CTRL", 1, 0)
    r2 = CreateRadio(ALT_KEY_TEXT or "ALT", 2, 120)

    -- ESC 关闭支持
    f:HookScript("OnShow", function()
        if not f._addedToSpecialFrames then
            table.insert(UISpecialFrames, f:GetName())
            f._addedToSpecialFrames = true
        end
    end)

    -- 对外方法
    function f:ShowStandalone()
        self:ClearAllPoints()
        self:SetParent(UIParent)
        self:SetPoint("CENTER")
        self:Show()
    end

    function f:ShowInContainer(container)
        self:Hide()
        self:ClearAllPoints()
        self:SetParent(container)
        self:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -8)
        self:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 8)
        self:Show()
    end

    return f
end

function UI:GetOrCreate()
    if not self.Main then
        self.Main = CreateMainFrame()
    end
    return self.Main
end

function UI:Show()
    self:GetOrCreate():ShowStandalone()
end

function UI:Hide()
    if self.Main then self.Main:Hide() end
end

function UI:Toggle()
    local f = self:GetOrCreate()
    if f:IsShown() then f:Hide() else f:ShowStandalone() end
end

function UI:ShowInContainer(container)
    self:GetOrCreate():ShowInContainer(container)
end

-- Slash：/adt
SLASH_ADT1 = "/adt"
SlashCmdList["ADT"] = function(msg)
    -- 若玩家在“设置”内，可以跳转到分类；否则显示独立面板
    if Settings and ADT.SettingsCategory then
        if SettingsPanel and SettingsPanel:IsShown() then
            Settings.OpenToCategory(ADT.SettingsCategory)
            return
        end
    end
    UI:Toggle()
end
