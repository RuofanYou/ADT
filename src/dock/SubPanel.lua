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
        -- 子面板左偏移与左侧分类栏宽度保持一致
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
        -- 默认不显示任何占位文本，便于“无正文时自动隐藏”
        header:SetText("")

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

        -- 自适应高度：根据 Content 子节点的“实际可见范围”动态调节 SubPanel 高度
        -- 说明：
        -- - 不依赖业务侧（Housing）的行数/字体/布局细节，完全依据可见像素范围计算；
        -- - 避免双实现（DRY）：高度唯一权威改为由 SubPanel 自身测量；业务侧只需触发一次“请求自适应”。
        do
            local AUTO_MIN = 160
            local AUTO_MAX = 1024
            local INSET_TOP = 14   -- content 与 sub 顶边的内边距（CreateFrame 时的锚点偏移）
            local INSET_BOTTOM = 10 -- content 与 sub 底边的内边距
            local pendingTicker
            local lastApplied
            
            -- 判空：除 Header 外是否存在“可见且占据面积”的子节点
            local function AnyNonHeaderVisible(frame, header)
                if not frame then return false end
                for _, ch in ipairs({frame:GetChildren()}) do
                    if ch and ch ~= header and (not ch.IsShown or ch:IsShown()) then
                        -- 若存在可见后代，则认为“正文存在”
                        if AnyNonHeaderVisible(ch, header) then return true end
                        -- 无后代或后代不可见时，仅在自己具备有效绘制面积且非透明时才算可见
                        local alphaOK = (not ch.GetAlpha) or (ch:GetAlpha() or 0) > 0.01
                        local w = (ch.GetWidth and ch:GetWidth()) or 0
                        local h = (ch.GetHeight and ch:GetHeight()) or 0
                        local hasArea = (w or 0) > 2 and (h or 0) > 2
                        if alphaOK and hasArea and (not ch.GetChildren or select('#', ch:GetChildren()) == 0) then
                            return true
                        end
                    end
                end
                return false
            end

            local function HeaderHasMeaningfulText(header)
                if not (header and header.Label) then return false end
                if not (header.Label.IsShown and header.Label:IsShown()) then return false end
                local a = header.Label.GetAlpha and header.Label:GetAlpha() or 1
                if a <= 0.01 then return false end
                local t = header.Label.GetText and header.Label:GetText() or nil
                return type(t) == 'string' and t:match('%S') ~= nil
            end

            local function DeepestBottom(frame)
                if not (frame and frame.GetBottom) then return nil end
                local minB = frame:GetBottom()
                if frame.GetChildren then
                    for _, ch in ipairs({frame:GetChildren()}) do
                        if ch and (not ch.IsShown or ch:IsShown()) then
                            local b = DeepestBottom(ch)
                            if b then minB = (minB and math.min(minB, b)) or b end
                        end
                    end
                end
                return minB
            end

            local function ComputeRequiredHeight()
                if not (sub and sub.Content) then return end
                local cont = sub.Content
                local topMost, bottomMost
                for _, ch in ipairs({cont:GetChildren()}) do
                    if ch and (not ch.IsShown or ch:IsShown()) then
                        local ct = ch.GetTop and ch:GetTop()
                        local cb = DeepestBottom(ch) or (ch.GetBottom and ch:GetBottom())
                        if ct and cb then
                            topMost = topMost and math.max(topMost, ct) or ct
                            bottomMost = bottomMost and math.min(bottomMost, cb) or cb
                        end
                    end
                end
                if not (topMost and bottomMost) then return nil end
                local contentPixels = math.max(0, topMost - bottomMost)
                local target = math.floor(contentPixels + INSET_TOP + INSET_BOTTOM + 0.5)
                target = math.max(AUTO_MIN, math.min(AUTO_MAX, target))
                return target
            end

            local function ApplyAutoHeightOnce()
                local h = ComputeRequiredHeight()
                if not h then return false end
                if lastApplied and math.abs((lastApplied or 0) - h) <= 1 then
                    -- 变化很小则认为已稳定
                    return true
                end
                sub:SetHeight(h)
                lastApplied = h
                return false
            end

            local function EvaluateAutoHide()
                -- 仅当“没有有效正文 + 标题也无意义”时隐藏，并把高度压到 0 以消除与下方清单之间的空隙。
                local noBody = not AnyNonHeaderVisible(sub.Content, sub.Header)
                local noHeader = not HeaderHasMeaningfulText(sub.Header)
                if noBody and noHeader then
                    sub:SetHeight(0)
                    sub:Hide()
                end
            end

            local function RequestAutoResize()
                if pendingTicker then return end
                -- 短期采样多次以等待暴雪 VerticalLayout 完成排版（字体缩放/行隐藏等）
                local count, maxSample = 0, 12
                pendingTicker = C_Timer.NewTicker(0.02, function(t)
                    count = count + 1
                    local stable = ApplyAutoHeightOnce()
                    if stable or count >= maxSample then
                        t:Cancel(); pendingTicker = nil
                        -- 排版稳定后判空一次
                        EvaluateAutoHide()
                    end
                end)
            end

            -- 对外暴露统一入口：ADT.DockUI.RequestSubPanelAutoResize()
            ADT.DockUI = ADT.DockUI or {}
            ADT.DockUI.RequestSubPanelAutoResize = function()
                if sub:IsShown() then RequestAutoResize() end
            end

            -- 尺寸/可见性变动时触发一次
            sub:HookScript("OnShow", function()
                RequestAutoResize()
                -- 次帧再判一次，覆盖“先显示后刷新”的时序
                C_Timer.After(0.05, EvaluateAutoHide)
            end)
            if sub.Content.HookScript then
                sub.Content:HookScript("OnSizeChanged", function() RequestAutoResize() end)
            end
            
            -- 对外暴露：允许业务侧在特殊时点主动触发判空
            ADT.DockUI.EvaluateSubPanelAutoHide = EvaluateAutoHide
        end
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
    if not (sub and sub.Header and sub.Header.Label) then return end
    sub.Header:SetText(text or "")
    if text and text ~= "" then sub.Header.Label:Show() end
end

ADT.DockUI.SetSubPanelHeaderAlpha = function(alpha)
    local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not (main and main.SubPanel and main.SubPanel.Header and main.SubPanel.Header.Label) then return end
    local label = main.SubPanel.Header.Label
    local a = tonumber(alpha) or 0
    a = math.max(0, math.min(1, a))
    label:SetAlpha(a)
    if a <= 0.001 then label:Hide() else label:Show() end
end

-- 统一：是否让 Header Alpha 跟随 HoverHUD 的 DisplayFrame OnUpdate
local _follow = true
function ADT.DockUI.SetHeaderAlphaFollow(state)
    _follow = not not state
    if _follow then
        -- 取消任何正在运行的 Header 专用淡入/淡出，以避免与“悬停跟随”双源竞争
        local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
        if main and main.SubPanel and main.SubPanel.Header then
            local f = main.SubPanel.Header._ADT_HeaderFader
            if f and f.SetScript then f:SetScript("OnUpdate", nil) end
        end
    end
end
function ADT.DockUI.IsHeaderAlphaFollowEnabled() return _follow end

-- 供“选中场景”使用的 Header 专用 fader（仍然使用 HoverHUD 的 FadeMixin，以保持节奏一致）
local function EnsureHeaderFader()
    local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not (main and main.SubPanel and main.SubPanel.Header and main.SubPanel.Header.Label) then return nil end
    local header = main.SubPanel.Header
    if not header._ADT_HeaderFader then
        local f = CreateFrame("Frame", nil, header)
        f.target = header.Label
        function f:SetAlpha(a)
            self.alpha = a or 0
            if self.target and self.target.SetAlpha then self.target:SetAlpha(self.alpha) end
        end
        function f:GetAlpha()
            if self.target and self.target.GetAlpha then return self.target:GetAlpha() end
            return self.alpha or 0
        end
        if ADT.Housing and ADT.Housing.FadeMixin then
            Mixin(f, ADT.Housing.FadeMixin)
        end
        header._ADT_HeaderFader = f
    end
    return header._ADT_HeaderFader
end

function ADT.DockUI.FadeInHeader()
    local f = EnsureHeaderFader(); if not f then return end
    _follow = false
    if f.SetAlpha then f:SetAlpha(0) end
    if f.FadeIn then f:FadeIn() end
end

function ADT.DockUI.FadeOutHeader(delay)
    local f = EnsureHeaderFader(); if not f then return end
    _follow = false
    if f.FadeOut then f:FadeOut(tonumber(delay) or 0.5) end
end

-- 只读：获取当前 Header 文本与 Alpha，供上层判重/智能节流
function ADT.DockUI.GetSubPanelHeaderText()
    local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not (main and main.SubPanel and main.SubPanel.Header and main.SubPanel.Header.Label) then return nil end
    return main.SubPanel.Header.Label:GetText()
end

function ADT.DockUI.GetSubPanelHeaderAlpha()
    local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not (main and main.SubPanel and main.SubPanel.Header and main.SubPanel.Header.Label) then return 0 end
    local a = main.SubPanel.Header.Label:GetAlpha()
    if type(a) ~= 'number' then return 0 end
    return a
end
