-- Scroll.lua
-- 单一权威：ADT 统一滚动物理引擎（滚轮/滚动条/程序化滚动统一走此模块）

local ADDON_NAME, ADT = ...
ADT = ADT or {}

ADT.Scroll = ADT.Scroll or {}
local Scroll = ADT.Scroll

-- 设计目标（与 2025 移动端交互一致）：
-- - 目标追踪式平滑滚动（DeltaLerp 到目标），预测性和一致性更强；
-- - 轻量“软钳制”边界：接近边界时采用非线性压缩，减少生硬撞边；
-- - 仅在运动期间启用 OnUpdate，零常驻开销；
-- - 允许宿主自定义步长/超界显示上限；

-- 全局默认参数（经验值，兼顾 PC 鼠标滚轮与触控板）
local DEFAULT = {
    blendSpeed = 0.20,       -- 稍微提高初速，改善“起步迟滞”感
    overscroll = 40,         -- 视觉超界上限（px；对不支持超界的宿主被忽略）
    renderFPS = 45,          -- 轻提节流频率，减少“卡一拍”的错觉
}

local function clamp(v, a, b) if v < a then return a elseif v > b then return b else return v end end

-- 创建独立驱动帧，避免占用宿主的 OnUpdate 槽位
local function CreateDriver()
    local f = CreateFrame('Frame')
    f:Hide()
    return f
end

-- 目标追踪式 Scroller（不使用速度/弹簧；避免“过度弹性”带来的不适）
-- adapter 需要实现：
--   getRange() -> number        最大滚动范围（px，>=0）
--   getPosition() -> number     当前显示位置（px）
--   setPosition(pos)            即时设置显示位置（px）
--   render?()                   可选：节流的内容回收/填充（如虚拟列表 Render）
--   supportsOverscroll -> bool  是否支持视觉超界
local function CreateScroller(adapter, cfg)
    local cfg2 = {}
    for k, v in pairs(DEFAULT) do cfg2[k] = v end
    if type(cfg) == 'table' then for k, v in pairs(cfg) do if cfg2[k] ~= nil then cfg2[k] = v end end end

    local self = {
        a = adapter,
        c = cfg2,
        p = 0,                -- 当前显示位置
        target = 0,           -- 目标位置
        active = false,
        driver = CreateDriver(),
        renderTimer = 0,
        firstKick = false,    -- 首次滚动时给一点“起步推进”以增强灵敏度
    }

    local function softClamp(pos, range, limit)
        if not adapter.supportsOverscroll then
            return clamp(pos, 0, range)
        end
        if pos < 0 then
            -- 负向超界：使用 tanh 压缩到 [-limit, 0]
            return -limit * math.tanh((-pos) / math.max(1, limit))
        elseif pos > range then
            return range + limit * math.tanh((pos - range) / math.max(1, limit))
        else
            return pos
        end
    end

    function self:SetPositionInstant(pos)
        self.p = pos or 0
        local r = math.max(0, self.a.getRange())
        self.a.setPosition(softClamp(self.p, r, self.c.overscroll))
    end

    function self:SyncFromHost()
        self.p = self.a.getPosition()
        self.target = self.p
    end

    function self:SyncRange()
        local r = math.max(0, self.a.getRange())
        local minP = -self.c.overscroll * 2
        local maxP = r + self.c.overscroll * 2
        if self.p < minP then self.p = minP end
        if self.p > maxP then self.p = maxP end
        if self.target < minP then self.target = minP end
        if self.target > maxP then self.target = maxP end
    end

    function self:AddWheelImpulse(deltaPixels)
        -- 直接修改目标位置（目标追踪），支持快速连击自然叠加
        local dv = deltaPixels or 0
        self.target = (self.target or 0) + dv
        -- 若处于静止状态，给一个起步推进，避免“滚了但画面不动”的迟滞感
        if not self.active then
            local diff = self.target - self.p
            local sign = (diff >= 0) and 1 or -1
            local kick = math.min(18, math.abs(diff) * 0.5) -- 最高 18px，或差值的一半
            self.p = self.p + sign * kick
            self.firstKick = true
        end
        self:Start()
    end

    function self:Start()
        if self.active then return end
        self.active = true
        self.driver:Show()
        self.driver:SetScript('OnUpdate', function(_, dt)
            dt = math.min(dt or 0, 0.033)
            if dt <= 0 then return end
            local r = math.max(0, self.a.getRange())

            -- DeltaLerp 到目标（时间无关手感）
            local blend = self.c.blendSpeed or 0.15
            if ADT and ADT.API and ADT.API.DeltaLerp then
                -- 首帧已做 kick，这里正常趋近
                self.p = ADT.API.DeltaLerp(self.p, self.target, blend, dt)
            else
                -- 兜底线性插值（不应该触发）
                local t = math.min(1, blend * dt * 60)
                self.p = (1 - t) * self.p + t * self.target
            end

            -- 呈现（软钳制）
            self.a.setPosition(softClamp(self.p, r, self.c.overscroll))

            -- 节流调用 render（如虚拟化回收）
            if self.a.render then
                self.renderTimer = self.renderTimer + dt
                local interval = 1 / math.max(1, self.c.renderFPS or 30)
                if self.renderTimer >= interval then
                    self.renderTimer = 0
                    self.a.render()
                end
            end

            -- 结束条件：接近目标
            local diff = self.p - self.target
            if diff < 0 then diff = -diff end
            if diff < 0.4 then
                -- 最终吸附
                self.p = self.target
                self.a.setPosition(softClamp(self.p, r, self.c.overscroll))
                if self.a.render then self.a.render() end
                self:Stop()
            end
        end)
    end

    function self:Stop()
        self.active = false
        self.driver:SetScript('OnUpdate', nil)
        self.driver:Hide()
    end

    return self
end

-- 适配：ListView（支持视觉超界）
function Scroll.AttachListView(view)
    if not view or view._adtScroller then return end

    local adapter = {
        getRange = function() return math.max(0, view._range or 0) end,
        getPosition = function() return view._offset or 0 end,
        setPosition = function(p)
            view:SetOffset(p or 0)
        end,
        render = function() view:Render() end,
        supportsOverscroll = true,
    }
    local scroller = CreateScroller(adapter, nil)
    view._adtScroller = scroller

    -- 统一鼠标滚轮 → 速度脉冲
    view:EnableMouseWheel(true)
    view:SetScript('OnMouseWheel', function(self, delta)
        if not delta or delta == 0 then return end
        -- 与旧实现保持相对尺度：step 越大，单位冲量越大
        local step = self._step or 30
        if IsShiftKeyDown and IsShiftKeyDown() then step = step * 2 end
        scroller:AddWheelImpulse(-delta * step)
    end)

    -- 隐藏时停止
    local origOnHide = view:GetScript('OnHide')
    view:SetScript('OnHide', function(self)
        scroller:Stop()
        if origOnHide then origOnHide(self) end
    end)

    -- 尺寸/内容变化时更新范围（由外部在 SetContent/OnSizeChanged 后调用）
    function view:_SyncScrollRange()
        scroller:SyncRange()
    end
end

-- 适配：UIPanelScrollFrame（不支持视觉超界，仅呈现钳制位置）
function Scroll.AttachScrollFrame(scrollFrame)
    if not scrollFrame or scrollFrame._adtScroller then return end
    local child = scrollFrame:GetScrollChild()
    local adapter = {
        getRange = function()
            local r = 0
            if scrollFrame.GetVerticalScrollRange then r = scrollFrame:GetVerticalScrollRange() or 0 end
            return math.max(0, r)
        end,
        getPosition = function()
            if scrollFrame.GetVerticalScroll then return scrollFrame:GetVerticalScroll() or 0 end
            return 0
        end,
        setPosition = function(p)
            local r = 0
            if scrollFrame.GetVerticalScrollRange then r = scrollFrame:GetVerticalScrollRange() or 0 end
            local v = clamp(p or 0, 0, r)
            if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(v) end
        end,
        supportsOverscroll = false,
    }
    local scroller = CreateScroller(adapter, { overscroll = 0 })
    scrollFrame._adtScroller = scroller

    -- 统一鼠标滚轮
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript('OnMouseWheel', function(self, delta)
        if not delta or delta == 0 then return end
        local step = 32
        if IsShiftKeyDown and IsShiftKeyDown() then step = step * 2 end
        scroller:AddWheelImpulse(-delta * step)
    end)

    -- 内容变更后外部可调用以校正范围
    function scrollFrame:_SyncScrollRange()
        scroller:SyncRange(); scroller:SyncFromHost()
    end

    local origOnHide = scrollFrame:GetScript('OnHide')
    scrollFrame:SetScript('OnHide', function(self)
        scroller:Stop()
        if origOnHide then origOnHide(self) end
    end)
end
