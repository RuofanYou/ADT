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

        -- 与主面板下边无缝拼接；宽度与“中央区域”一致。
        -- 关键改动：左侧锚点不再使用“创建时的固定像素偏移”（sideSectionWidth），
        -- 改为直接锚到 CentralSection 的 BOTTOMLEFT，从而在语言切换/字体变化
        -- 导致左侧分类栏宽度变动时，子面板能即时跟随，无需额外刷新。
        if self.CentralSection then
            sub:SetPoint("TOPLEFT", self.CentralSection, "BOTTOMLEFT", 0, 0)
        else
            -- 极早期调用：CentralSection 尚未就绪时，按“侧栏宽度计算（单一权威）”锚定到右侧区域。
            local leftOffset = ComputeSideSectionWidth()
            sub:SetPoint("TOPLEFT", self, "BOTTOMLEFT", leftOffset, 0)
        end
        sub:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, 0)
        sub:SetHeight(192)
        sub:SetFrameStrata(self:GetFrameStrata())
        sub:SetFrameLevel(self:GetFrameLevel())

        -- 边框与背景：保持与主面板一致
        local borderFrame = CreateFrame("Frame", nil, sub)
        borderFrame:SetAllPoints(sub)
        borderFrame:SetFrameLevel(sub:GetFrameLevel() + 100)
        sub.BorderFrame = borderFrame

        -- 与 DockUI 主框体保持一致：边框严格贴合容器，不做 ±4 像素外扩，
        -- 以免视觉上比右侧面板“略宽”。
        local border = borderFrame:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
        border:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)
        border:SetAtlas("housing-wood-frame")
        border:SetTextureSliceMargins(16, 16, 16, 16)
        border:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        borderFrame.WoodFrame = border

        local bg = sub:CreateTexture(nil, "BACKGROUND")
        bg:SetAtlas("housing-basic-panel-background")
        -- 背景也与 DockUI 右侧区域的 inset 规则保持一致（参考 DockUI.Def）。
        local rightInset = (Def.RightBGInsetRight ~= nil) and Def.RightBGInsetRight or -2
        local bottomInset = (Def.CenterBGInsetBottom ~= nil) and Def.CenterBGInsetBottom or 2
        bg:SetPoint("TOPLEFT", sub, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", sub, "BOTTOMRIGHT", rightInset, bottomInset)
        sub.Background = bg

        -- 统一内容容器
        local content = CreateFrame("Frame", nil, sub)
        content:SetPoint("TOPLEFT", sub, "TOPLEFT", 10, -14)
        content:SetPoint("BOTTOMRIGHT", sub, "BOTTOMRIGHT", -10, 10)
        -- 当 SubPanel 被 LayoutManager 压缩时，正文可能超出容器底部；
        -- 这里启用裁剪：超出部分直接不渲染（符合“显示不下就不显示”的交互预期）。
        content:SetClipsChildren(true)
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

        -- 自适应高度 + 判空显隐：完全依据“正文存在性”的单一权威扫描结果。
        do
            local CFG = ADT.GetHousingCFG and ADT.GetHousingCFG() or nil
            local L   = CFG and CFG.Layout or {}
            local AUTO_MIN     = tonumber(L.subPanelMinHeight)      or 160
            local AUTO_MAX     = tonumber(L.subPanelMaxHeight)      or 1024
            local INSET_TOP    = tonumber(L.contentTopPadding)      or 14
            local INSET_BOTTOM = tonumber(L.contentBottomPadding)   or 10
            local HEADER_NUDGE = tonumber(L.headerTopNudge)         or 10
            local HEADER_GAP   = tonumber(L.headerToInstrGap)       or 8
            local ALPHA_TH     = tonumber(L.contentAlphaThreshold)  or 0.01
            local LEAF_MIN_PX  = tonumber(L.leafMinAreaPx)          or 2

            local pendingTicker
            local lastApplied

            local InteractiveTypes = {
                Button      = true,
                CheckButton = true,
                EditBox     = true,
                Slider      = true,
                ScrollFrame = true,
                Frame       = false,
            }

            local function IsEffectivelyVisible(obj)
                if not obj then return false end
                if obj.IsShown and not obj:IsShown() then return false end
                local a = obj.GetAlpha and (obj:GetAlpha() or 0) or 1
                if a <= ALPHA_TH then return false end
                return true
            end

            local function HasArea(obj)
                local w = (obj.GetWidth and obj:GetWidth()) or 0
                local h = (obj.GetHeight and obj:GetHeight()) or 0
                return w > LEAF_MIN_PX and h > LEAF_MIN_PX
            end

            local function HeaderHasMeaningfulText(header)
                if not (header and header.Label) then return false end
                local label = header.Label
                if not IsEffectivelyVisible(label) then return false end
                local t = label.GetText and label:GetText() or ""
                return type(t) == "string" and t:match("%S") ~= nil
            end

            local function EvaluateContent(root, header)
                local hasBody = false
                local bottomMost

                local function UpdateBottom(obj)
                    local b = obj and obj.GetBottom and obj:GetBottom() or nil
                    if b then bottomMost = bottomMost and math.min(bottomMost, b) or b end
                end

                local function ScanRegions(frame)
                    if not (frame and frame.GetRegions) then return end
                    for _, r in ipairs({frame:GetRegions()}) do
                        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                            if IsEffectivelyVisible(r) then
                                local text = r.GetText and r:GetText() or ""
                                if type(text) == "string" and text:match("%S") then
                                    hasBody = true
                                    UpdateBottom(r)
                                end
                            end
                        end
                    end
                end

                local function ScanFrame(frame)
                    if not frame or frame == header then return end
                    if not IsEffectivelyVisible(frame) then return end

                    ScanRegions(frame)

                    local ot = frame.GetObjectType and frame:GetObjectType() or nil
                    if ot and InteractiveTypes[ot] and HasArea(frame) then
                        hasBody = true
                        UpdateBottom(frame)
                    end

                    if frame.GetChildren then
                        local children = {frame:GetChildren()}
                        if #children > 0 then
                            for _, ch in ipairs(children) do
                                ScanFrame(ch)
                            end
                        end
                    end
                end

                ScanRegions(root)
                if root and root.GetChildren then
                    for _, ch in ipairs({root:GetChildren()}) do
                        ScanFrame(ch)
                    end
                end

                return hasBody, bottomMost
            end

            local function ComputeRequiredHeight()
                if not (sub and sub.Content and sub.Header) then return nil end
                local cont   = sub.Content
                local header = sub.Header

                local hasBody, bottomMost = EvaluateContent(cont, header)
                local hasHeaderText = HeaderHasMeaningfulText(header)
                if not hasBody and not hasHeaderText then
                    return 0
                end

                local headerHeight = (header.GetHeight and header:GetHeight()) or ((Def.ButtonSize or 28) + 2)
                local headerBottom = header.GetBottom and header:GetBottom() or nil
                local headerTop    = header.GetTop and header:GetTop() or nil
                local headerRefBottom = headerBottom or (headerTop and (headerTop - headerHeight)) or 0
                local topRef = headerRefBottom - HEADER_GAP

                local contentPixels = 0
                if bottomMost then
                    contentPixels = math.max(0, topRef - bottomMost)
                end

                local topPadding = INSET_TOP + HEADER_NUDGE + headerHeight + HEADER_GAP
                local target = math.floor(topPadding + contentPixels + INSET_BOTTOM + 0.5)
                target = math.max(AUTO_MIN, math.min(AUTO_MAX, target))
                return target
            end

            local function ApplyAutoHeightOnce()
                local h = ComputeRequiredHeight()
                if h == nil then return false end
                if lastApplied and math.abs((lastApplied or 0) - h) <= 1 then
                    return true
                end
                sub._ADT_DesiredHeight = h
                sub:SetHeight(h)
                lastApplied = h
                return false
            end

            local function EvaluateAutoHide()
                if not (sub and sub.Content and sub.Header) then return end
                local hasBody, _ = EvaluateContent(sub.Content, sub.Header)
                local hasHeaderText = HeaderHasMeaningfulText(sub.Header)
                if not hasBody and not hasHeaderText then
                    sub._ADT_DesiredHeight = 0
                    sub:SetHeight(0)
                    if sub.IsShown and sub:IsShown() then sub:Hide() end
                else
                    if sub.IsShown and not sub:IsShown() then sub:Show() end
                end
            end

            local function RequestAutoResize()
                if pendingTicker then return end
                local count, maxSample = 0, 12
                pendingTicker = C_Timer.NewTicker(0.02, function(t)
                    count = count + 1
                    local stable = ApplyAutoHeightOnce()
                    if stable or count >= maxSample then
                        t:Cancel(); pendingTicker = nil
                        EvaluateAutoHide()
                        if ADT and ADT.CommandDock and ADT.CommandDock.SettingsPanel then
                            local main = ADT.CommandDock.SettingsPanel
                            if main.UpdateAutoWidth then main:UpdateAutoWidth() end
                        end
                        if ADT and ADT.HousingLayoutManager and ADT.HousingLayoutManager.RequestLayout then
                            ADT.HousingLayoutManager:RequestLayout("SubPanelAutoResize")
                        end
                    end
                end)
            end

            sub._ADT_RequestAutoResize = function()
                RequestAutoResize()
            end

            -- 宽度需求上报：返回“在不换行前提下正文所需的中心区域宽度”。
            -- 注意：不直接设宽；DockUI.UpdateAutoWidth 作为唯一裁决者。
            do
                local meter
                local function ensureMeter()
                    if not meter then
                        meter = sub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        meter:Hide()
                    end
                    return meter
                end

                local function measureFS(fs)
                    if not (fs and fs.GetText) then return 0 end
                    local text = fs:GetText() or ""
                    if text == "" then return 0 end
                    local m = ensureMeter()
                    -- 尝试复制字体
                    if fs.GetFont then
                        local file, h, flags = fs:GetFont()
                        if file and h then m:SetFont(file, h, flags) end
                    elseif fs.GetFontObject and fs:GetFontObject() then
                        m:SetFontObject(fs:GetFontObject())
                    end
                    m:SetText(text)
                    local w = m:GetStringWidth() or 0
                    return math.ceil(w)
                end

                local function isRightAnchored(region)
                    if not (region and region.GetNumPoints) then return false end
                    local n = region:GetNumPoints() or 0
                    for i=1,n do
                        local p = region:GetPoint(i)
                        if type(p) == 'string' and p:find("RIGHT") then return true end
                    end
                    return false
                end

                function sub:GetDesiredCenterWidth()
                    if not (self and self.Content) then return 0 end
                    local content = self.Content
                    local maxRow, headerW = 0, 0

                    -- Header 文本（若存在且可见）
                    if self.Header and self.Header.Label and (self.Header.Label:IsShown() or true) then
                        headerW = measureFS(self.Header.Label) or 0
                    end

                    local GAP = 10
                    for _, row in ipairs({content:GetChildren()}) do
                        if row and row ~= self.Header then
                            local leftMax, rightSum, anyFS = 0, 0, false
                            -- 仅测 FontString，其他控件（如 Key 按钮）通常自带文本区域，以其 FontString 为准
                            if row.GetRegions then
                                for _, r in ipairs({row:GetRegions()}) do
                                    if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                                        anyFS = true
                                        local w = measureFS(r)
                                        if isRightAnchored(r) then
                                            rightSum = rightSum + w
                                        else
                                            if w > leftMax then leftMax = w end
                                        end
                                    end
                                end
                            end

                            local rowW
                            if anyFS and rightSum > 0 and leftMax > 0 then
                                rowW = leftMax + GAP + rightSum
                            elseif anyFS then
                                rowW = math.max(leftMax, rightSum)
                            else
                                -- 兜底：没有可测文本时，不以“容器当前宽度”反推，避免与父容器形成正反馈导致无限增宽。
                                -- 此类行（纯分隔/纯图形）对“无换行宽度”的决策应为 0。
                                rowW = 0
                            end
                            if type(rowW) == 'number' and rowW > maxRow then maxRow = rowW end
                        end
                    end

                    local pad = GetRightPadding()
                    local safe = 16 -- 轻微安全边
                    local want = math.max(headerW, maxRow) + pad + safe
                    -- 保护：避免把不合理的大值（例如异常字体测量）一路放大到接近屏幕宽
                    local parent = (self:GetParent() or UIParent)
                    local viewport = (parent and parent.GetWidth and parent:GetWidth()) or 1600
                    local capRatio = 0.8
                    if ADT and ADT.GetHousingCFG then
                        local C = ADT.GetHousingCFG()
                        if C and C.Layout and type(C.Layout.subPanelMaxViewportRatio) == 'number' then
                            capRatio = C.Layout.subPanelMaxViewportRatio
                        end
                    end
                    if type(capRatio) ~= 'number' or capRatio <= 0 or capRatio > 1 then capRatio = 0.8 end
                    local hardCap = math.floor(viewport * capRatio)
                    if want > hardCap then want = hardCap end
                    want = math.max(0, math.floor(want + 0.5))
                    return want
                end
            end

            -- 尺寸/可见性变动时触发一次
            sub:HookScript("OnShow", function()
                RequestAutoResize()
                -- 次帧保持常驻可见（不做隐藏判定）。
                C_Timer.After(0.05, EvaluateAutoHide)
            end)
            if sub.Content.HookScript then
                sub.Content:HookScript("OnSizeChanged", function() RequestAutoResize() end)
            end
            
            -- 对外暴露：允许业务侧在特殊时点主动触发判空
            ADT.DockUI.EvaluateSubPanelAutoHide = EvaluateAutoHide
        end
        -- 规则调整：创建即显示，避免调用方忘记显式打开导致“再入编辑模式后子面板缺失”。
        sub:Show()
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

-- Header 淡入：若 fromCurrent 为 true，则从当前 Alpha 继续补完，不重置到 0。
function ADT.DockUI.FadeInHeader(fromCurrent)
    local f = EnsureHeaderFader(); if not f then return end
    _follow = false
    if not fromCurrent and f.SetAlpha then f:SetAlpha(0) end
    if f.FadeIn then f:FadeIn() end
end

-- 语义化别名：用于“同名切换时补完淡入”，避免重复播放动画
function ADT.DockUI.FinishHeaderFadeIn()
    return ADT.DockUI.FadeInHeader(true)
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

--
-- SubPanel 悬停信息显示（关注点分离：自己监听悬停事件，自己获取 Decor 信息）
--
do
    local L = ADT.L or {}
    local GetCatalogEntryInfoByRecordID = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByRecordID
    local IsHouseEditorActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive
    local GetActiveHouseEditorMode = C_HouseEditor and C_HouseEditor.GetActiveHouseEditorMode

    local BasicMode = Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.BasicDecor
    local ExpertMode = Enum and Enum.HouseEditorMode and Enum.HouseEditorMode.ExpertDecor
    
    local function GetCatalogDecorInfo(decorID)
        if not GetCatalogEntryInfoByRecordID then return nil end
        return GetCatalogEntryInfoByRecordID(1, decorID, true)
    end

    -- 单一权威：根据当前编辑模式选用对应 API，避免“看起来能用”的跨命名空间假设。
    local function GetActiveDecorInfo()
        local mode = GetActiveHouseEditorMode and GetActiveHouseEditorMode() or nil
        local api
        if mode == BasicMode then
            api = C_HousingBasicMode
        elseif mode == ExpertMode then
            api = C_HousingExpertMode
        else
            return nil
        end

        if api and api.IsHoveringDecor and api.IsHoveringDecor() then
            return api.GetHoveredDecorInfo and api.GetHoveredDecorInfo() or nil
        end

        if api and api.IsDecorSelected and api.IsDecorSelected() then
            return api.GetSelectedDecorInfo and api.GetSelectedDecorInfo() or nil
        end

        return nil
    end
    
    -- 语义着色工具：从配置读取颜色
    local function Colorize(key, text)
        local cfg = ADT and ADT.HousingInstrCFG
        local colors = cfg and cfg.Colors
        local hex = colors and colors[key]
        if not hex then return tostring(text or "") end
        return "|c" .. hex .. tostring(text or "") .. "|r"
    end
    
    -- InfoLine 框架（延迟创建）
    local infoLine = nil
    
    local function EnsureInfoLine()
        if infoLine then return infoLine end
        
        local main = ADT.CommandDock and ADT.CommandDock.SettingsPanel
        if not (main and main.EnsureSubPanel) then return nil end
        local sub = main:EnsureSubPanel()
        if not (sub and sub.Content and sub.Header) then return nil end
        
        -- 获取统一边距配置（单一权威）
        local pad = GetRightPadding()
        
        -- 创建信息行（在 Header 下方）
        infoLine = CreateFrame("Frame", nil, sub.Content)
        infoLine:SetHeight(24)
        infoLine:SetPoint("TOPLEFT", sub.Header, "BOTTOMLEFT", 0, -4)
        infoLine:SetPoint("TOPRIGHT", sub.Header, "BOTTOMRIGHT", 0, -4)
        
        -- 左侧文本：室内/外 | 库存（应用左边距）
        local leftText = infoLine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        leftText:SetPoint("LEFT", infoLine, "LEFT", pad, 0)
        leftText:SetJustifyH("LEFT")
        infoLine.LeftText = leftText
        
        -- 右侧文本：染色槽信息（应用右边距）
        local rightText = infoLine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rightText:SetPoint("RIGHT", infoLine, "RIGHT", -pad, 0)
        rightText:SetJustifyH("RIGHT")
        infoLine.RightText = rightText
        
        infoLine:Hide()
        return infoLine
    end
    
    -- 更新 Header 和 InfoLine 显示悬停的 Decor 信息
    local function UpdateDecorHeader()
        if not IsHouseEditorActive or not IsHouseEditorActive() then return end
        
        local line = EnsureInfoLine()
        
        local info = GetActiveDecorInfo()

        if not info then
            ADT.DockUI.SetSubPanelHeaderText("")
            if line then line:Hide() end
            ADT.DockUI.RequestSubPanelAutoResize()
            return
        end
        
        -- 标题：装饰名（带锁图标如果受保护）
        local displayName = info.name or ""
        if ADT.Housing and ADT.Housing.Protection and ADT.Housing.Protection.IsProtected then
            local isProtected = ADT.Housing.Protection:IsProtected(info.decorGUID, info.decorID)
            if isProtected then
                displayName = "|A:BonusChest-Lock:16:16|a " .. displayName
            end
        end
        ADT.DockUI.SetSubPanelHeaderText(displayName)
        ADT.DockUI.SetSubPanelHeaderAlpha(1)
        
        -- InfoLine：显示详细信息
        if line then
            -- 左侧：室内/室外 | 库存
            local indoor = not not info.isAllowedIndoors
            local outdoor = not not info.isAllowedOutdoors
            local placeText = (indoor and outdoor) and (L["Indoor & Outdoor"] or "Indoor & Outdoor")
                or (indoor and (L["Indoor"] or "Indoor"))
                or (outdoor and (L["Outdoor"] or "Outdoor"))
                or (L["Indoor"] or "Indoor")
            
            local entryInfo = info.decorID and GetCatalogDecorInfo(info.decorID)
            local stored = 0
            if entryInfo then
                stored = (entryInfo.quantity or 0) + (entryInfo.remainingRedeemable or 0)
            end
            
            local stockLabel = L["Stock"] or "Stock"
            local labelSep = Colorize('separatorMuted', ' | ')
            local colon = Colorize('separatorMuted', ": ")
            local placeC = Colorize('labelMuted', placeText)
            local stockLbl = Colorize('labelMuted', stockLabel)
            local stockVal = (stored and stored > 0)
                and Colorize('valueGood', tostring(stored))
                or Colorize('valueBad', tostring(stored or 0))
            
            line.LeftText:SetText(placeC .. labelSep .. stockLbl .. colon .. stockVal)
            
            -- 右侧：染色槽信息（直接显示颜色色块）
            local rightStr = ""
            local slots = info.dyeSlots or {}
            local total = #slots
            if total and total > 0 then
                -- 按 orderIndex 排序
                local sortedSlots = {}
                for i, s in ipairs(slots) do sortedSlots[i] = s end
                table.sort(sortedSlots, function(a, b)
                    return (a.orderIndex or 0) < (b.orderIndex or 0)
                end)
                
                -- 为每个槽位生成颜色色块
                local colorBlocks = ""
                for i = 1, #sortedSlots do
                    local slot = sortedSlots[i]
                    local colorID = slot and slot.dyeColorID
                    if colorID and colorID > 0 then
                        -- 获取颜色信息并生成色块
                        local colorData = C_DyeColor and C_DyeColor.GetDyeColorInfo(colorID)
                        if colorData and colorData.swatchColorStart then
                            local r, g, b = colorData.swatchColorStart:GetRGBAsBytes()
                            colorBlocks = colorBlocks .. string.format("|cff%02x%02x%02x█|r", r, g, b)
                        else
                            colorBlocks = colorBlocks .. "|cff888888█|r"
                        end
                    else
                        -- 未染色的槽位显示灰色
                        colorBlocks = colorBlocks .. "|cff444444█|r"
                    end
                end
                rightStr = "|A:catalog-palette-icon:16:16|a " .. colorBlocks
            end
            
            if rightStr ~= "" then
                line.RightText:SetText(rightStr)
                line.RightText:Show()
            else
                line.RightText:SetText("")
                line.RightText:Hide()
            end
            
            line:Show()
        end
        
        ADT.DockUI.RequestSubPanelAutoResize()
    end
    
    -- 创建事件监听帧
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    eventFrame:RegisterEvent("HOUSING_BASIC_MODE_HOVERED_TARGET_CHANGED")
    eventFrame:RegisterEvent("HOUSING_EXPERT_MODE_HOVERED_TARGET_CHANGED")
    eventFrame:RegisterEvent("HOUSING_BASIC_MODE_SELECTED_TARGET_CHANGED")
    eventFrame:RegisterEvent("HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        -- 目标：无论基础/专家模式，只要“悬停/抓取(选中)” Decor 发生变化，都刷新 SubPanel。
        -- 说明：UpdateDecorHeader 内部自行判定优先级（悬停优先，其次选中）。
        UpdateDecorHeader()
    end)
    
    -- 对外暴露刷新接口
    ADT.DockUI.UpdateDecorHeader = UpdateDecorHeader
end
