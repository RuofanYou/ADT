-- DockUI_Highlight.lua
-- DockUI 高亮容器逻辑（单一权威）

local ADDON_NAME, ADT = ...
if not ADT.IsToCVersionEqualOrNewerThan(110000) then return end

local API = ADT.API
local CreateFrame = CreateFrame

-- ============================================================================
-- 高亮容器实现
-- ============================================================================

-- 统一"高亮容器"实现：单实例 Frame，父到目标按钮，贴 housing-basic-container，带淡入
do
    local HL

    local function DockHLParams()
        local cfg = ADT and ADT.GetHousingCFG and ADT.GetHousingCFG()
        local d = (cfg and cfg.DockHighlight) or {}
        return {
            r = tonumber(d.color and d.color.r) or 0.96,
            g = tonumber(d.color and d.color.g) or 0.84,
            b = tonumber(d.color and d.color.b) or 0.32,
            a = tonumber(d.color and d.color.a) or 0.15,
            il = tonumber(d.insetLeft) or 0,
            ir = tonumber(d.insetRight) or 0,
            it = tonumber(d.insetTop) or 1,
            ib = tonumber(d.insetBottom) or 1,
            fadeEnabled = (d.fade and d.fade.enabled) ~= false,
            fadeInDuration = tonumber(d.fade and d.fade.inDuration) or 0.15,
        }
    end

    local function EnsureHL(mainFrame)
        if HL then return HL end
        local f = CreateFrame("Frame", nil, mainFrame, "ADTSettingsAnimSelectionTemplate")
        f:Hide()
        -- 采用模板自带三段贴片，颜色来自配置表
        local P = DockHLParams()
        if f.Left then f.Left:SetColorTexture(P.r, P.g, P.b, P.a) end
        if f.Center then f.Center:SetColorTexture(P.r, P.g, P.b, P.a) end
        if f.Right then f.Right:SetColorTexture(P.r, P.g, P.b, P.a) end
        f.BG = f.Center

        function f:SyncPieces()
            local h = math.max(1, tonumber(self:GetHeight()) or 28)
            if self.Left and self.Left.SetHeight then self.Left:SetHeight(h) end
            if self.Right and self.Right.SetHeight then self.Right:SetHeight(h) end
        end

        f:SetScript("OnSizeChanged", function(self) self:SyncPieces() end)

        -- 简单淡入
        f:SetAlpha(0)
        f._fadeTicker = nil

        function f:FadeIn()
            if self._fadeTicker then self._fadeTicker:Cancel() end
            local P = DockHLParams()
            if not P.fadeEnabled or (P.fadeInDuration or 0) <= 0 then
                self:SetAlpha(1); self:Show(); return
            end
            local step = 0.016
            local steps = math.max(1, math.floor(P.fadeInDuration / step + 0.5))
            local a = 0
            self:SetAlpha(0); self:Show()
            self._fadeTicker = C_Timer.NewTicker(step, function()
                a = a + (1/steps)
                if a >= 1 then a = 1; if self._fadeTicker then self._fadeTicker:Cancel(); self._fadeTicker = nil end end
                self:SetAlpha(a)
            end, steps)
        end

        function f:InstantHide()
            if self._fadeTicker then self._fadeTicker:Cancel(); self._fadeTicker = nil end
            self:SetAlpha(0); self:Hide(); self:ClearAllPoints()
        end

        HL = f
        return HL
    end

    -- 供外部调用的高亮函数（将被 DockUI 主模块注入到 MainFrame）
    function ADT.DockUI.HighlightButton(mainFrame, button)
        local hl = EnsureHL(mainFrame)
        hl:InstantHide()
        if not button then return end
        -- 父到按钮，覆盖整条区域
        hl:SetParent(button)
        hl:SetFrameStrata(button:GetFrameStrata() or "FULLSCREEN_DIALOG")
        pcall(hl.SetFrameLevel, hl, math.max(1, (button:GetFrameLevel() or 1)))
        local P = DockHLParams()
        hl:SetPoint("TOPLEFT", button, "TOPLEFT", P.il, -P.it)
        hl:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -P.ir, P.ib)
        if hl.SyncPieces then hl:SyncPieces() end
        hl:FadeIn()
    end
end
