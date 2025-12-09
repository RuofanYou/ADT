-- 子面板（DockUI 下方面板）
-- 目标：将 DockUI.lua 中的下方面板实现解耦为独立脚本，保持交互与视觉一致。

local ADDON_NAME, ADT = ...
if not ADT or not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local API = ADT.API
local UI  = ADT.DockUI or {}
local Def = assert(UI.Def, "DockUI.Def 不存在：请确认 DockUI.lua 已加载")

local GetRightPadding            = assert(UI.GetRightPadding, "DockUI.GetRightPadding 不存在")
local ComputeSideSectionWidth    = assert(UI.ComputeSideSectionWidth, "DockUI.ComputeSideSectionWidth 不存在")
local CreateSettingsHeader       = assert(UI.CreateSettingsHeader, "DockUI.CreateSettingsHeader 不存在")

local function AttachTo(main)
    if not main or main.__SubPanelAttached then return end

    function main:EnsureSubPanel()
        if self.SubPanel then return self.SubPanel end

        local sub = CreateFrame("Frame", nil, self)
        self.SubPanel = sub

        -- 与主面板下边无缝拼接；宽度与右侧区域一致
        local leftOffset = tonumber(self.sideSectionWidth) or ComputeSideSectionWidth() or 180
        sub:SetPoint("TOPLEFT", self, "BOTTOMLEFT", leftOffset, 0)
        sub:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, 0)
        sub:SetHeight(192)
        sub:SetFrameStrata(self:GetFrameStrata())
        sub:SetFrameLevel(self:GetFrameLevel())

        -- 边框与背景：保持与主面板一致
        local borderFrame = CreateFrame("Frame", nil, sub)
        borderFrame:SetAllPoints(sub)
        borderFrame:SetFrameLevel(sub:GetFrameLevel() + 100)
        sub.BorderFrame = borderFrame

        local border = borderFrame:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", -4, 4)
        border:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 4, -4)
        border:SetAtlas("housing-wood-frame")
        border:SetTextureSliceMargins(16, 16, 16, 16)
        border:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        borderFrame.WoodFrame = border

        local bg = sub:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("housing-basic-panel-background")
        bg:SetPoint("TOPLEFT", sub, "TOPLEFT", -4, -2)
        bg:SetPoint("BOTTOMRIGHT", sub, "BOTTOMRIGHT", -2, 2)
        sub.Background = bg

        -- 统一内容容器
        local content = CreateFrame("Frame", nil, sub)
        content:SetPoint("TOPLEFT", sub, "TOPLEFT", 10, -14)
        content:SetPoint("BOTTOMRIGHT", sub, "BOTTOMRIGHT", -10, 10)
        sub.Content = content

        -- 标题 Header（占位文案）
        local header = CreateSettingsHeader(content)
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -10)
        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -10)
        header:SetHeight((Def.ButtonSize or 28) + 2)
        header:SetText("扩展面板（占位标题）")

        -- 分隔条：下移并左右对称以居中
        if header.Divider then
            header.Divider:ClearAllPoints()
            local pad = GetRightPadding()
            header.Divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", pad, -2)
            header.Divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -pad, -2)
        end

        -- 标题样式：居中、小号 Fancy + 淡金色 + 阴影
        if header.Label then
            header.Label:ClearAllPoints()
            header.Label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 6)
            header.Label:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 6)
            header.Label:SetJustifyH("CENTER")
            if _G.Fancy24Font then
                header.Label:SetFontObject("Fancy24Font")
            elseif _G.Fancy22Font then
                header.Label:SetFontObject("Fancy22Font")
            else
                header.Label:SetFontObject("GameFontNormalLarge")
            end
            header.Label:SetTextColor(Def.TitleColorPaleGold[1], Def.TitleColorPaleGold[2], Def.TitleColorPaleGold[3])
            if header.Label.SetShadowColor then header.Label:SetShadowColor(0, 0, 0, 1) end
            if header.Label.SetShadowOffset then header.Label:SetShadowOffset(1, -1) end
        end

        sub.Header = header
        sub:Hide()
        return sub
    end

    function main:SetSubPanelShown(shown)
        if not self.SubPanel then return end
        self.SubPanel:SetShown(shown)
    end

    function main:SetSubPanelHeight(height)
        if not self.SubPanel then return end
        self.SubPanel:SetHeight(tonumber(height) or 192)
    end

    main.__SubPanelAttached = true
end

-- 将方法挂载到 Dock 主面板
AttachTo(ADT.CommandDock and ADT.CommandDock.SettingsPanel)

-- 对外：提供统一的 Header 文本设置入口，避免分散直接访问
ADT.DockUI = ADT.DockUI or {}
-- 注意：为规避某些运行环境对 "function A.B.C(...)" 语法的解析异常，这里采用赋值式匿名函数。
ADT.DockUI.SetSubPanelHeaderText = function(text)
    local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not (main and main.EnsureSubPanel) then return end
    local sub = main:EnsureSubPanel()
    if sub and sub.Header and sub.Header.SetText then sub.Header:SetText(text or "") end
end
