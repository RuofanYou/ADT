
-- 为 SettingsPanelNew 提供所有必需的 API 函数

local ADDON_NAME, ADT = ...

ADT = ADT or {}
ADT.L = ADT.L or {}

-- 核心 API 模块
ADT.API = ADT.API or {}
local API = ADT.API

-- Mixin
function API.Mixin(object, ...)
    for i = 1, select('#', ...) do
        local mixin = select(i, ...)
        for k, v in pairs(mixin) do
            object[k] = v
        end
    end
    return object
end

-- 数学函数
function API.Round(n)
    return math.floor((n or 0) + 0.5)
end

function API.Clamp(value, min, max)
    if value > max then return max
    elseif value < min then return min
    end
    return value
end

function API.Saturate(x)
    if x < 0 then return 0 elseif x > 1 then return 1 else return x end
end

function API.Lerp(a, b, t)
    return (1 - t) * a + t * b
end

function API.DeltaLerp(a, b, amount, dt)
    return API.Lerp(a, b, API.Saturate((amount or 0.15) * (dt or 0) * 60))
end

-- 纹理锐化控制
function API.DisableSharpening(obj)
    if not obj then return end
    if obj.SetSnapToPixelGrid then pcall(obj.SetSnapToPixelGrid, obj, false) end
    if obj.SetTexelSnappingBias then pcall(obj.SetTexelSnappingBias, obj, 0) end
end

-- 字符串处理
function API.StringTrim(str)
    if not str or str == "" then return nil end
    return str:match("^%s*(.-)%s*$")
end

-- 兼容函数：判断 ToC 版本
function ADT.IsToCVersionEqualOrNewerThan(target)
    local _, _, _, toc = GetBuildInfo()
    toc = tonumber(toc or 0)
    return toc >= (tonumber(target) or 0)
end

-- 缓动函数（动画用）
ADT.EasingFunctions = ADT.EasingFunctions or {}
function ADT.EasingFunctions.outQuart(t, b, c, d)
    t = t / d - 1
    return -c * (t*t*t*t - 1) + b
end
function ADT.EasingFunctions.outQuint(t, b, c, d)
    t = t / d - 1
    return c * (t*t*t*t*t + 1) + b
end

-- UI 声音
ADT.LandingPageUtil = ADT.LandingPageUtil or {}
function ADT.LandingPageUtil.PlayUISound(key)
    local kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 1204
    if key == 'CheckboxOff' then
        kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 1203
    elseif key == 'ScrollBarStep' or key == 'ScrollBarThumbDown' then
        kit = SOUNDKIT and SOUNDKIT.IG_MINIMAP_OPEN or 891
    elseif key == 'SwitchTab' then
        kit = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION or 857
    end
    if PlaySound then pcall(PlaySound, kit) end
end

-- 对象池（与 Plumber 一致的 API）
function API.CreateObjectPool(createObjectFunc, onRemovedFunc, onAcquiredFunc)
    local pool = {}

    local objects, active, unused = {}, {}, {}
    local numUnused = 0

    local function removeObject(obj)
        obj:Hide()
        obj:ClearAllPoints()
        if obj.OnRemoved then obj:OnRemoved() end
        if onRemovedFunc then onRemovedFunc(obj) end
    end

    local function recycleObject(obj)
        for i, v in ipairs(active) do
            if v == obj then
                table.remove(active, i)
                removeObject(obj)
                numUnused = numUnused + 1
                unused[numUnused] = obj
                break
            end
        end
    end

    local function createObject()
        local obj = createObjectFunc()
        table.insert(objects, obj)
        obj.Release = function(o) recycleObject(o) end
        return obj
    end

    function pool:Acquire()
        local obj
        if numUnused > 0 then
            obj = table.remove(unused, numUnused)
            numUnused = numUnused - 1
        end
        if not obj then
            obj = createObject()
        end
        table.insert(active, obj)
        obj:Show()
        if onAcquiredFunc then onAcquiredFunc(obj) end
        return obj
    end

    function pool:ReleaseAll()
        if #active == 0 then return end
        for _, obj in ipairs(active) do removeObject(obj) end
        active = {}
        unused = {}
        for i, obj in ipairs(objects) do unused[i] = obj end
        numUnused = #objects
    end

    function pool:EnumerateActive()
        return ipairs(active)
    end

    function pool:CallMethod(method, ...)
        for _, obj in ipairs(active) do
            if obj[method] then obj[method](obj, ...) end
        end
    end

    return pool
end

-- LandingPageUtil.CreateObjectPool（Plumber 使用的版本）
ADT.LandingPageUtil.CreateObjectPool = function(createFunc, onAcquiredFunc, onRemovedFunc)
    return API.CreateObjectPool(createFunc, onRemovedFunc, onAcquiredFunc)
end

-- NineSlice 边框（完全照抄 Plumber 的 SliceFrameMixin）
function ADT.CreateNineSliceFrame(parent, themeName)
    local f = CreateFrame('Frame', nil, parent)
    f.pieces = {}
    f.numSlices = 9
    
    -- 创建9个贴图切片
    -- 1 2 3
    -- 4 5 6
    -- 7 8 9
    for i = 1, 9 do
        f.pieces[i] = f:CreateTexture(nil, 'BORDER')
        API.DisableSharpening(f.pieces[i])
        f.pieces[i]:ClearAllPoints()
    end
    
    -- 布局（与 Plumber 完全一致：角的 CENTER 锚定到父级的角）
    f.pieces[1]:SetPoint('CENTER', f, 'TOPLEFT', 0, 0)
    f.pieces[3]:SetPoint('CENTER', f, 'TOPRIGHT', 0, 0)
    f.pieces[7]:SetPoint('CENTER', f, 'BOTTOMLEFT', 0, 0)
    f.pieces[9]:SetPoint('CENTER', f, 'BOTTOMRIGHT', 0, 0)
    
    f.pieces[2]:SetPoint('TOPLEFT', f.pieces[1], 'TOPRIGHT', 0, 0)
    f.pieces[2]:SetPoint('BOTTOMRIGHT', f.pieces[3], 'BOTTOMLEFT', 0, 0)
    f.pieces[4]:SetPoint('TOPLEFT', f.pieces[1], 'BOTTOMLEFT', 0, 0)
    f.pieces[4]:SetPoint('BOTTOMRIGHT', f.pieces[7], 'TOPRIGHT', 0, 0)
    f.pieces[5]:SetPoint('TOPLEFT', f.pieces[1], 'BOTTOMRIGHT', 0, 0)
    f.pieces[5]:SetPoint('BOTTOMRIGHT', f.pieces[9], 'TOPLEFT', 0, 0)
    f.pieces[6]:SetPoint('TOPLEFT', f.pieces[3], 'BOTTOMLEFT', 0, 0)
    f.pieces[6]:SetPoint('BOTTOMRIGHT', f.pieces[9], 'TOPRIGHT', 0, 0)
    f.pieces[8]:SetPoint('TOPLEFT', f.pieces[7], 'TOPRIGHT', 0, 0)
    f.pieces[8]:SetPoint('BOTTOMRIGHT', f.pieces[9], 'BOTTOMLEFT', 0, 0)
    
    -- 默认纹理坐标
    f.pieces[1]:SetTexCoord(0, 0.25, 0, 0.25)
    f.pieces[2]:SetTexCoord(0.25, 0.75, 0, 0.25)
    f.pieces[3]:SetTexCoord(0.75, 1, 0, 0.25)
    f.pieces[4]:SetTexCoord(0, 0.25, 0.25, 0.75)
    f.pieces[5]:SetTexCoord(0.25, 0.75, 0.25, 0.75)
    f.pieces[6]:SetTexCoord(0.75, 1, 0.25, 0.75)
    f.pieces[7]:SetTexCoord(0, 0.25, 0.75, 1)
    f.pieces[8]:SetTexCoord(0.25, 0.75, 0.75, 1)
    f.pieces[9]:SetTexCoord(0.75, 1, 0.75, 1)
    
    -- 默认角尺寸函数（先定义再调用，避免调用未定义方法）
    function f:SetCornerSize(a)
        self.pieces[1]:SetSize(a, a)
        self.pieces[3]:SetSize(a, a)
        self.pieces[7]:SetSize(a, a)
        self.pieces[9]:SetSize(a, a)
    end
    -- 默认角尺寸
    f:SetCornerSize(16)
    
    function f:SetDisableSharpening(state)
        for _, piece in ipairs(self.pieces) do
            piece:SetSnapToPixelGrid(not state)
        end
    end
    
    function f:SetTexture(texture)
        for _, piece in ipairs(self.pieces) do
            piece:SetTexture(texture)
        end
    end
    
    function f:SetUsingParentLevel(state)
        -- 不做任何操作，保持默认行为
    end
    
    function f:CoverParent(padding)
        padding = padding or 0
        local p = self:GetParent()
        if p then
            self:ClearAllPoints()
            self:SetPoint('TOPLEFT', p, 'TOPLEFT', -padding, padding)
            self:SetPoint('BOTTOMRIGHT', p, 'BOTTOMRIGHT', padding, -padding)
        end
    end
    
    function f:ShowBackground(state)
        for _, piece in ipairs(self.pieces) do
            piece:SetShown(state)
        end
    end
    
    return f
end


-- LandingPageUtil.CreateExpansionThemeFrame（与 Plumber 完全一致）
function ADT.LandingPageUtil.CreateExpansionThemeFrame(parent, level)
    local tex = "Interface/AddOns/AdvancedDecorationTools/Art/ExpansionLandingPage/ExpansionBorder_TWW"
    
    local f = ADT.CreateNineSliceFrame(parent, 'ExpansionBorder_TWW')
    f:SetUsingParentLevel(true)
    f:SetCornerSize(64, 64)
    f:SetDisableSharpening(false)
    f:CoverParent(-30)
    
    -- 背景（覆盖 NineSlice 默认的）
    local Background = f:CreateTexture(nil, 'BACKGROUND')
    f.Background = Background
    Background:SetPoint('TOPLEFT', f.pieces[1], 'TOPLEFT', 4, -4)
    Background:SetPoint('BOTTOMRIGHT', f.pieces[9], 'BOTTOMRIGHT', -4, 4)
    Background:SetColorTexture(0.067, 0.040, 0.024)
    
    f:SetTexture(tex)
    f.pieces[1]:SetTexCoord(0/1024, 128/1024, 0/1024, 128/1024)
    f.pieces[2]:SetTexCoord(128/1024, 384/1024, 0/1024, 128/1024)
    f.pieces[3]:SetTexCoord(384/1024, 512/1024, 0/1024, 128/1024)
    f.pieces[4]:SetTexCoord(0/1024, 128/1024, 128/1024, 384/1024)
    f.pieces[5]:SetTexCoord(128/1024, 384/1024, 128/1024, 384/1024)
    f.pieces[6]:SetTexCoord(384/1024, 512/1024, 128/1024, 384/1024)
    f.pieces[7]:SetTexCoord(0/1024, 128/1024, 384/1024, 512/1024)
    f.pieces[8]:SetTexCoord(128/1024, 384/1024, 384/1024, 512/1024)
    f.pieces[9]:SetTexCoord(384/1024, 512/1024, 384/1024, 512/1024)
    
    -- 关闭按钮（与 Plumber 完全一致）
    local CloseButton = CreateFrame('Button', nil, f)
    f.CloseButton = CloseButton
    CloseButton:Hide()
    CloseButton:SetSize(32, 32)
    CloseButton:SetPoint('CENTER', f.pieces[3], 'TOPRIGHT', -20.5, -20.5)
    
    CloseButton.Texture = CloseButton:CreateTexture(nil, 'OVERLAY')
    CloseButton.Texture:SetPoint('CENTER', CloseButton, 'CENTER', 0, 0)
    CloseButton.Texture:SetSize(24, 24)
    CloseButton.Texture:SetTexture(tex)
    CloseButton.Texture:SetTexCoord(646/1024, 694/1024, 48/1024, 96/1024)
    
    CloseButton.Highlight = CloseButton:CreateTexture(nil, 'HIGHLIGHT')
    CloseButton.Highlight:SetPoint('CENTER', CloseButton, 'CENTER', 0, 0)
    CloseButton.Highlight:SetSize(24, 24)
    CloseButton.Highlight:SetTexture(tex)
    CloseButton.Highlight:SetTexCoord(646/1024, 694/1024, 48/1024, 96/1024)
    CloseButton.Highlight:SetBlendMode('ADD')
    CloseButton.Highlight:SetAlpha(0.5)
    
    CloseButton:SetScript('OnClick', function(self)
        if self.frameToClose then
            if self.frameToClose.Close then
                self.frameToClose:Close()
            else
                self.frameToClose:Hide()
            end
        end
    end)
    
    -- ExpansionThemeFrameMixin（与 Plumber 一致）
    function f:ShowCloseButton(state)
        if state then
            self.pieces[3]:SetTexCoord(518/1024, 646/1024, 48/1024, 176/1024)
        else
            self.pieces[3]:SetTexCoord(384/1024, 512/1024, 0/1024, 128/1024)
        end
        self.CloseButton:SetShown(state)
    end
    
    function f:SetCloseButtonOwner(owner)
        self.CloseButton.frameToClose = owner
    end
    
    return f
end




-- Settings 面板最小依赖
function ADT.AnyShownModuleOptions() return false end
function ADT.CloseAllModuleOptions() return false end

-- ControlCenter 模块注册
local ControlCenter = ADT.ControlCenter or {}
ADT.ControlCenter = ControlCenter

local L = ADT.L

-- 内部：构建默认模块，并初始化映射
local function buildModules()
    local modules = {}
    local data = {
        name = L["ModuleName Housing_DecorHover"] or "住宅：名称与复制",
        dbKey = 'EnableDupe',
        description = L["ModuleDescription Housing_DecorHover"],
        toggleFunc = function(state)
            if ADT and ADT.SetDBValue then ADT.SetDBValue('EnableDupe', state) end
            if ADT and ADT.Housing and ADT.Housing.LoadSettings then ADT.Housing:LoadSettings() end
        end,
        categoryKeys = { 'Housing' },
        uiOrder = 1,
    }

    modules[1] = {
        key = 'Housing',
        categoryName = (L and L['SC Housing']) or 'Housing',
        modules = { data },
        numModules = 1,
    }

    -- 初始化映射
    ControlCenter._dbKeyMap = { [data.dbKey] = data }
    return modules
end

local function ensureSorted(self)
    if not self._sorted then self._sorted = buildModules() end
    if not self._dbKeyMap then self._dbKeyMap = {} end
end

function ControlCenter:GetSortedModules()
    ensureSorted(self)
    return self._sorted
end

local function getCategoryDisplayName(key)
    if key == 'Housing' then
        return (L and L['SC Housing']) or 'Housing'
    end
    return tostring(key)
end

local function sortCategory(cat)
    table.sort(cat.modules, function(a, b)
        local ao, bo = tonumber(a.uiOrder) or 9999, tonumber(b.uiOrder) or 9999
        if ao ~= bo then return ao < bo end
        local at, bt = tonumber(a.moduleAddedTime) or 0, tonumber(b.moduleAddedTime) or 0
        if at ~= bt then return at > bt end
        local an, bn = tostring(a.name or ''), tostring(b.name or '')
        return an < bn
    end)
    cat.numModules = #cat.modules
end

-- 动态注册模块（供各功能文件调用）
function ControlCenter:AddModule(moduleData)
    if type(moduleData) ~= 'table' then return end
    ensureSorted(self)

    local dbKey = moduleData.dbKey
    if dbKey and self._dbKeyMap and self._dbKeyMap[dbKey] then
        -- 已存在则先从原分类移除，保证单一权威（DRY）
        for _, cat in ipairs(self._sorted) do
            for i, m in ipairs(cat.modules) do
                if m.dbKey == dbKey then
                    table.remove(cat.modules, i)
                    sortCategory(cat)
                    break
                end
            end
        end
    end

    local catKey = (moduleData.categoryKeys and moduleData.categoryKeys[1]) or 'Misc'
    local category
    for _, cat in ipairs(self._sorted) do
        if cat.key == catKey then category = cat break end
    end
    if not category then
        category = {
            key = catKey,
            categoryName = getCategoryDisplayName(catKey),
            modules = {},
            numModules = 0,
        }
        table.insert(self._sorted, category)
    end

    table.insert(category.modules, moduleData)
    sortCategory(category)
    if dbKey then self._dbKeyMap[dbKey] = moduleData end
end

function ControlCenter:GetModule(dbKey)
    ensureSorted(self)
    return dbKey and self._dbKeyMap and self._dbKeyMap[dbKey]
end

function ControlCenter:GetModuleCategoryName(dbKey)
    ensureSorted(self)
    if not dbKey then return end
    for _, cat in ipairs(self._sorted) do
        for _, m in ipairs(cat.modules) do
            if m.dbKey == dbKey then
                return cat.categoryName
            end
        end
    end
end

function ControlCenter:UpdateCurrentSortMethod() return 1 end
function ControlCenter:SetCurrentSortMethod(_) end
function ControlCenter:GetNumFilters() return 1 end
function ControlCenter:AnyNewFeatureMarker() return false end
function ControlCenter:FlagCurrentNewFeatureMarkerSeen() end

function ControlCenter:GetSearchResult(text)
    ensureSorted(self)
    text = string.lower(tostring(text or ''))
    if text == '' then return self:GetSortedModules() end
    local results = {}
    for _, cat in ipairs(self._sorted) do
        local matched = { key = cat.key, categoryName = cat.categoryName, modules = {}, numModules = 0 }
        for _, m in ipairs(cat.modules) do
            local hay = table.concat({
                m.name or '',
                m.description or '',
                table.concat(m.searchTags or {}, ' '),
                cat.categoryName or '',
            }, ' ')
            if string.find(string.lower(hay), text, 1, true) then
                table.insert(matched.modules, m)
            end
        end
        if #matched.modules > 0 then
            matched.numModules = #matched.modules
            table.insert(results, matched)
        end
    end
    return results
end
