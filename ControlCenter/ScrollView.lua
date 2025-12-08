-- ScrollView：通用滚动视图实现（含完整方法集）

local ADDON_NAME, ADT = ...
local API = ADT.API
local LandingPageUtil = ADT.LandingPageUtil

local CreateFrame = CreateFrame
local DeltaLerp = API.DeltaLerp

local ScrollViewMixin = {}

local function CreateScrollView(parent, externalScrollBar)
    local f = CreateFrame('Frame', nil, parent)
    API.Mixin(f, ScrollViewMixin)
    f:SetClipsChildren(true)
    -- 明确开启鼠标滚轮支持：在“通用”分类条目多且窗口较小时，
    -- 允许用户直接使用滚轮滚动列表（与“最近放置/临时板”弹窗体验一致）。
    -- 为避免父级抢占滚轮导致的拦截失效，这里显式启用。
    if f.EnableMouseWheel then f:EnableMouseWheel(true) end

    f.ScrollRef = CreateFrame('Frame', nil, f)
    f.ScrollRef:SetSize(4, 4)
    f.ScrollRef:SetPoint('TOP', f, 'TOP', 0, 0)

    f.pools = {}
    f.content = {}
    f.indexedObjects = {}
    f.offset, f.scrollTarget, f.range, f.viewportSize = 0, 0, 0, 0
    f.blendSpeed = 0.15
    f:SetStepSize(32)
    f:SetBottomOvershoot(0)

    f:SetScript('OnMouseWheel', f.OnMouseWheel)
    f:SetScript('OnHide', f.OnHide)

    f.ScrollBar = externalScrollBar

    local NoContentAlert = CreateFrame('Frame', nil, f)
    f.NoContentAlert = NoContentAlert
    NoContentAlert:Hide()
    NoContentAlert:SetAllPoints(true)
    local fs1 = NoContentAlert:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    NoContentAlert.AlertText = fs1
    fs1:SetPoint('LEFT', f, 'LEFT', 16, 16)
    fs1:SetPoint('RIGHT', f, 'RIGHT', -16, 16)
    fs1:SetSpacing(4)
    fs1:SetJustifyH('CENTER')
    fs1:SetText(ADT.L and ADT.L['List Is Empty'] or 'Empty')
    fs1:SetTextColor(0.5, 0.5, 0.5)

    return f
end
API.CreateScrollView = CreateScrollView

function ScrollViewMixin:GetOffset() return self.offset end
function ScrollViewMixin:SetOffset(offset)
    self.offset = offset
    self.ScrollRef:SetPoint('TOP', self, 'TOP', 0, offset)
    if self.scrollable and self.ScrollBar and self.ScrollBar.SetValueByRatio then
        self.ScrollBar:SetValueByRatio(offset/(self.range > 0 and self.range or 1))
    end
end

function ScrollViewMixin:UpdateView(useScrollTarget)
    local top = (useScrollTarget and self.scrollTarget) or self.offset
    local bottom = self.offset + self.viewportSize
    local fromIndex, toIndex
    for idx, v in ipairs(self.content) do
        if not fromIndex and (v.top >= top or v.bottom >= top) then fromIndex = idx end
        if not toIndex and ((v.top <= bottom and v.bottom >= bottom) or (v.top >= bottom)) then toIndex = idx break end
    end
    toIndex = toIndex or #self.content
    for i, obj in pairs(self.indexedObjects) do
        if i < (fromIndex or 0) or i > (toIndex or 0) then
            obj:Release()
            self.indexedObjects[i] = nil
        end
    end
    if fromIndex then
        for i = fromIndex, toIndex do
            if not self.indexedObjects[i] then
                local d = self.content[i]
                local obj = self:AcquireObject(d.templateKey)
                if obj then
                    if d.setupFunc then d.setupFunc(obj) end
                    obj:SetPoint(d.point or 'TOP', self.ScrollRef, d.relativePoint or 'TOP', d.offsetX or 0, -d.top)
                    self.indexedObjects[i] = obj
                end
            end
        end
    end
end

function ScrollViewMixin:OnSizeChanged(forceUpdate)
    self.viewportSize = API.Round(self:GetHeight())
    self.ScrollRef:SetWidth(API.Round(self:GetWidth()))
    if forceUpdate and self.ScrollBar and self.ScrollBar.UpdateVisibleExtentPercentage then
        self.ScrollBar:UpdateVisibleExtentPercentage()
    end
end

function ScrollViewMixin:SetStepSize(step) self.stepSize = step end
function ScrollViewMixin:SetBottomOvershoot(v) self.bottomOvershoot = v or 0 end
function ScrollViewMixin:SetAlwaysShowScrollBar(state) self.alwaysShowScrollBar = state end
function ScrollViewMixin:EnableMouseBlocker(_) end
function ScrollViewMixin:SetShowNoContentAlert(state) self.showNoContentAlert = state end
function ScrollViewMixin:SetNoContentAlertText(text) self.NoContentAlert.AlertText:SetText(text) end

function ScrollViewMixin:GetScrollRange()
    return self.range or 0
end

function ScrollViewMixin:SetScrollRange(range)
    range = (range and range > 0) and range or 0
    self.range = range
    self.scrollable = range > 0
    if not self.scrollable then self:ScrollToTop() end
    if self.ScrollBar then
        if self.ScrollBar.SetScrollable then self.ScrollBar:SetScrollable(self.scrollable) end
        if self.ScrollBar.SetShown then self.ScrollBar:SetShown(self.scrollable or self.alwaysShowScrollBar) end
    end
end

function ScrollViewMixin:SetContent(content, retainPosition)
    self.content = content or {}
    local n = #self.content
    if n > 0 then
        local range = self.content[n].bottom - self.viewportSize
        if range > 0 then range = range + (self.bottomOvershoot or 0) end
        self:SetScrollRange(range)
        self.NoContentAlert:Hide()
    else
        self:SetScrollRange(0)
        if self.showNoContentAlert then self.NoContentAlert:Show() else self.NoContentAlert:Hide() end
    end
    for _, obj in pairs(self.indexedObjects) do obj:Release() end
    self.indexedObjects = {}
    if retainPosition then
        local offset = self.scrollTarget
        if offset > self.range then offset = self.range end
        self.scrollTarget = offset
    else
        self.scrollTarget = 0
    end
    self:SnapToScrollTarget()
    -- 内容更新后，强制刷新滚动条的可见比例与位置，
    -- 避免在窗口缩放/条目增删后出现“滚动条不显示或尺寸不对”的情况。
    if self.ScrollBar and self.ScrollBar.UpdateVisibleExtentPercentage then
        self.ScrollBar:UpdateVisibleExtentPercentage()
        if self.alwaysShowScrollBar and self.ScrollBar.SetShown then
            self.ScrollBar:SetShown(true)
        end
    end
end

function ScrollViewMixin:AddTemplate(key, create, remove, onAcquire)
    self.pools[key] = API.CreateObjectPool(create, remove, onAcquire)
end
function ScrollViewMixin:AcquireObject(key)
    return self.pools[key]:Acquire()
end
function ScrollViewMixin:ReleaseAllObjects()
    self.indexedObjects = {}
    for _, pool in pairs(self.pools) do pool:ReleaseAll() end
end
function ScrollViewMixin:CallObjectMethod(key, method, ...)
    local pool = self.pools[key]
    if not pool then return end
    for _, obj in pool:EnumerateActive() do
        if obj[method] then obj[method](obj, ...) end
    end
end

function ScrollViewMixin:OnMouseWheel(delta)
    if (delta > 0 and self.scrollTarget <= 0) or (delta < 0 and self.scrollTarget >= self.range) then return end
    local a = IsShiftKeyDown() and 2 or 1
    self:ScrollBy(-(self.stepSize or 30) * a * delta)
end

function ScrollViewMixin:ScrollBy(dy)
    self.scrollTarget = math.min(self.range, math.max(0, self.scrollTarget + dy))
    self:SetScript('OnUpdate', self.OnUpdate_Easing)
end

function ScrollViewMixin:OnUpdate_Easing(elapsed)
    self.offset = DeltaLerp(self.offset, self.scrollTarget, self.blendSpeed, elapsed)
    if math.abs(self.offset - self.scrollTarget) < 0.5 then
        self.offset = self.scrollTarget
        self:SetScript('OnUpdate', nil)
        self:UpdateView(true)
    end
    self:UpdateView()
    self:SetOffset(self.offset)
end

function ScrollViewMixin:ScrollTo(offset)
    self.scrollTarget = math.min(self.range, math.max(0, offset or 0))
    self:SnapToScrollTarget()
end
function ScrollViewMixin:ScrollToTop() self:ScrollTo(0) end
function ScrollViewMixin:SnapToScrollTarget()
    self:SetOffset(self.scrollTarget)
    self:SetScript('OnUpdate', nil)
    self:UpdateView(true)
end

function ScrollViewMixin:IsScrollable() return self.scrollable end
function ScrollViewMixin:IsAtTop() return self.scrollTarget <= 0 end
function ScrollViewMixin:IsAtBottom() return self.scrollTarget >= self.range end

-- 按比率滚动相关方法
function ScrollViewMixin:ScrollToRatio(ratio)
    ratio = math.min(1, math.max(0, ratio or 0))
    local offset = ratio * self.range
    self.scrollTarget = offset
    self:SetScript('OnUpdate', self.OnUpdate_Easing)
end

function ScrollViewMixin:SnapToRatio(ratio)
    ratio = math.min(1, math.max(0, ratio or 0))
    local offset = ratio * self.range
    self.scrollTarget = offset
    self:SnapToScrollTarget()
end

function ScrollViewMixin:SteadyScroll(direction)
    direction = direction or 1
    self:ScrollBy((self.stepSize or 30) * direction)
end

function ScrollViewMixin:StopSteadyScroll()
    -- 停止持续滚动（如果有的话）
end

function ScrollViewMixin:OnHide()
    self:SetScript('OnUpdate', nil)
    if self.ScrollBar and self.ScrollBar.StopUpdating then self.ScrollBar:StopUpdating() end
end
