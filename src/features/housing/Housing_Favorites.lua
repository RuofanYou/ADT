-- Housing_Favorites.lua
-- 目标：
-- 1) 在目录元素右上角提供“收藏”星标按钮（默认悬停可见；收藏后常驻显示）。
-- 2) 在暴雪自带“过滤器”下拉菜单中新增一项“仅显示收藏”，启用后列表仅展示收藏内容。
-- 3) 全链路以 decor recordID 为唯一权威，不做任何兼容映射。
-- 4) 代码风格遵循本仓库“配置驱动/单一权威/解耦”的约定，避免与 Referrence/HousingTweaks/Tweaks/Favorites.lua 的实现结构相似。

local ADDON_NAME, ADT = ...
if not ADT then return end

local Favorites = {}
ADT.Favorites = Favorites

-- DB 约定（唯一权威）
local KEY_FAV_MAP = "FavoritesByRID"       -- map<number, boolean>
local KEY_FILTER_ON = "FavoritesFilterOn"  -- boolean

local function GetFavMap()
    local db = _G.ADT_DB or {}
    db[KEY_FAV_MAP] = db[KEY_FAV_MAP] or {}
    return db[KEY_FAV_MAP]
end

local function IsFavoritedRID(recordID)
    if not recordID then return false end
    local map = GetFavMap()
    return not not map[recordID]
end

local function SetFavoritedRID(recordID, state)
    if not recordID then return end
    local map = GetFavMap()
    if state then map[recordID] = true else map[recordID] = nil end
end

function Favorites:IsFilterOn()
    return ADT.GetDBBool(KEY_FILTER_ON)
end

function Favorites:SetFilter(on, silent)
    ADT.SetDBValue(KEY_FILTER_ON, not not on)
    if not silent then
        Favorites:RefreshCatalog()
    end
end

function Favorites:ToggleFilter()
    Favorites:SetFilter(not Favorites:IsFilterOn())
end

-- 工具：从“目录条目按钮”取 decor recordID（单一权威）
local function ExtractRecordIDFromEntryFrame(frame)
    -- 优先从 entryInfo.entryID.recordID 读取（更新且稳定）
    local info = frame and frame.entryInfo
    if info and info.entryID and info.entryID.recordID then
        return info.entryID.recordID
    end
    -- 次选：从元素数据回推（仍为 recordID）
    if frame and frame.GetElementData then
        local ed = frame:GetElementData()
        local e = ed and ed.entryID
        if e and e.recordID then return e.recordID end
    end
    return nil
end

-- 星标外观（Atlas 名称来源：系统素材库）
local STAR_ATLAS = "CampCollection-icon-star"  -- 注意拼写：CampCollection

-- 为目录按钮附加/更新星标（不侵入按钮业务；完全独立）
local function EnsureStarOnButton(btn)
    if not btn or btn._ADTStar then return end

    -- 贴图层级：覆盖在按钮最上层但不遮挡Tooltip
    local star = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    star:SetAtlas(STAR_ATLAS)
    star:SetSize(22, 22)
    star:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -2)
    star:Hide() -- 默认不常驻
    btn._ADTStar = star

    -- 独立点击区域，避免影响按钮原有左键放置
    local hit = CreateFrame("Button", nil, btn)
    hit:SetAllPoints(star)
    hit:SetFrameLevel(btn:GetFrameLevel() + 10)
    btn._ADTStarHit = hit

    -- 轻量交互动效：点击时做一个 Alpha 闪烁
    local clickAG = star:CreateAnimationGroup()
    local a1 = clickAG:CreateAnimation("Alpha")
    a1:SetFromAlpha(1)
    a1:SetToAlpha(0.6)
    a1:SetDuration(0.05)
    local a2 = clickAG:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.6)
    a2:SetToAlpha(1)
    a2:SetDuration(0.08)
    star._ADTClickAG = clickAG

    hit:SetScript("OnEnter", function()
        local rid = ExtractRecordIDFromEntryFrame(btn)
        local fav = rid and IsFavoritedRID(rid)
        GameTooltip:SetOwner(hit, "ANCHOR_RIGHT")
        GameTooltip:SetText(fav and ("取消收藏") or ("收藏"))
        GameTooltip:Show()
        -- 关键修复：进入星标命中区时显式 Show，避免父按钮 OnLeave 抢先隐藏
        star:Show()
        star:SetAlpha(1)
    end)
    hit:SetScript("OnLeave", function()
        GameTooltip:Hide()
        -- 若仍在父按钮上，回退为低透明度的悬停提示
        if btn:IsMouseOver() then
            local rid = ExtractRecordIDFromEntryFrame(btn)
            if rid and not IsFavoritedRID(rid) then
                star:SetAlpha(0.85)
                star:Show()
            end
            return
        end
        -- 完全离开：按收藏态决定显隐
        local rid = ExtractRecordIDFromEntryFrame(btn)
        if not (rid and IsFavoritedRID(rid)) then
            star:Hide()
        end
    end)
    hit:SetScript("OnMouseDown", function()
        star:SetAlpha(0.8)
    end)
    hit:SetScript("OnMouseUp", function()
        star:SetAlpha(1)
    end)
    hit:SetScript("OnClick", function()
        local rid = ExtractRecordIDFromEntryFrame(btn)
        if not rid then return end
        local newState = not IsFavoritedRID(rid)
        SetFavoritedRID(rid, newState)
        Favorites:RefreshStar(btn)
        if star._ADTClickAG then star._ADTClickAG:Play() end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if newState then
            ADT.Notify("已收藏", "info")
        else
            ADT.Notify("已取消收藏", "info")
        end
        -- 若“仅显示收藏”开启，则实时刷新列表
        if Favorites:IsFilterOn() then
            Favorites:RefreshCatalog()
        end
    end)

    -- 悬停按钮卡片时，非收藏状态下短暂显示星标提示
    btn:HookScript("OnEnter", function()
        local rid = ExtractRecordIDFromEntryFrame(btn)
        if rid and not IsFavoritedRID(rid) then
            star:SetVertexColor(1, 1, 0) -- 高亮黄
            star:SetAlpha(0.9)
            star:Show()
        end
    end)
    btn:HookScript("OnLeave", function()
        -- 若鼠标已进入星标命中区，不应隐藏，避免闪烁和“消失”
        if hit:IsMouseOver() then return end
        local rid = ExtractRecordIDFromEntryFrame(btn)
        if not (rid and IsFavoritedRID(rid)) then
            star:Hide()
        end
    end)
end

function Favorites:RefreshStar(btn)
    local star = btn and btn._ADTStar
    if not star then return end
    local rid = ExtractRecordIDFromEntryFrame(btn)
    local fav = rid and IsFavoritedRID(rid)
    if fav then
        -- 收藏：常驻显示，明亮黄
        star:SetVertexColor(1, 0.9, 0)
        star:SetAlpha(1)
        star:Show()
    else
        -- 非收藏：默认隐藏（由悬停控制显示）
        star:SetVertexColor(1, 1, 0)
        star:SetAlpha(0.85)
        star:Hide()
    end
end

-- 遍历可见的目录按钮，安装星标并刷新状态
local function SweepVisibleCatalogButtons(scrollBox)
    if not (scrollBox and scrollBox.ForEachFrame) then return end
    scrollBox:ForEachFrame(function(frame)
        -- 仅对“装饰项”模板添加；其他（分割线/说明/套装）跳过
        local ed = frame.GetElementData and frame:GetElementData()
        if ed and ed.templateKey == "CATALOG_ENTRY_DECOR" then
            EnsureStarOnButton(frame)
            Favorites:RefreshStar(frame)
        end
    end)
end

-- 收集“收藏的目录条目”（按照 recordID→entryID 的权威关系组装）
local function CollectFavoriteEntries(storagePanel)
    if not (storagePanel and storagePanel.catalogSearcher) then return {} end
    local favs = GetFavMap()
    if not next(favs) then return {} end
    local results = {}
    -- 使用“搜索项全集”，避免受当前分类筛选限制
    local all = storagePanel.catalogSearcher:GetAllSearchItems()
    for _, id in ipairs(all or {}) do
        if id.entryType == Enum.HousingCatalogEntryType.Decor and favs[id.recordID] then
            table.insert(results, id)
        end
    end
    return results
end

-- 根据“仅显示收藏”的开关，刷新右侧列表
function Favorites:RefreshCatalog()
    local hf = _G.HouseEditorFrame
    local sp = hf and hf.StoragePanel
    if not sp then return end

    if Favorites:IsFilterOn() then
        local entries = CollectFavoriteEntries(sp)
        -- 为空也要设定自定义数据，以呈现“空列表”状态（遵循官方行为）
        local header = "收藏"
        sp:SetCustomCatalogData(entries, header, nil)
    else
        -- 还原官方数据流
        sp:SetCustomCatalogData(nil)
        if sp.catalogSearcher then
            sp.catalogSearcher:RunSearch()
        end
    end
end

-- 将“仅显示收藏”接入暴雪过滤下拉：在原菜单末尾追加复选项，并把重置按钮状态与之联动。
local function HookFilterDropdown(filters)
    if not (filters and filters.FilterDropdown) then return end
    local fd = filters.FilterDropdown
    if fd._ADTFavHooked then return end

    -- 1) 追加菜单项：保留官方生成器，并在其后注入“仅显示收藏”。
    local origGen = fd.menuGenerator
    fd:SetupMenu(function(dropdown, root)
        if type(origGen) == "function" then
            origGen(dropdown, root)
        end
        root:CreateDivider()
        root:CreateCheckbox("仅显示收藏", function() return Favorites:IsFilterOn() end, function()
            Favorites:ToggleFilter()
            -- 保持下拉菜单开启并刷新选中态
            return MenuResponse.Refresh
        end)
    end)

    -- 2) 重写“是否默认/重置”回调，让 Reset 按钮也管控我们的开关
    local origIsDefault = fd.isDefaultCallback
    local origDefault   = fd.defaultCallback
    fd:SetIsDefaultCallback(function()
        local ok = true
        if type(origIsDefault) == "function" then
            ok = not not origIsDefault()
        end
        return ok and (not Favorites:IsFilterOn())
    end)
    fd:SetDefaultCallback(function()
        if type(origDefault) == "function" then origDefault() end
        Favorites:SetFilter(false, true)
        Favorites:RefreshCatalog()
    end)

    fd._ADTFavHooked = true
    -- 初始校验一次重置按钮显隐
    if fd.ValidateResetState then fd:ValidateResetState() end
end

-- 在 HouseEditor 的存储面板可用时，安装滚动列表的星标刷新钩子
local function TryInstallToStoragePanel()
    local hf = _G.HouseEditorFrame
    local sp = hf and hf.StoragePanel
    local oc = sp and sp.OptionsContainer
    local sb = oc and oc.ScrollBox
    if not sb then return false end

    if not sb._ADTFavHooked then
        -- 列表刷新时检查/更新星标
        hooksecurefunc(sb, "Update", function(self)
            SweepVisibleCatalogButtons(self)
        end)
        -- 首次也走一遍
        C_Timer.After(0, function() SweepVisibleCatalogButtons(sb) end)
        sb._ADTFavHooked = true
    end

    -- 过滤下拉接入（官方在 StorageFrame:OnLoad 时已完成 Initialize，这里直接挂）
    HookFilterDropdown(sp and sp.Filters)

    return true
end

-- 入口：在编辑器出现或 UI 初始化后尝试安装
function Favorites:Init()
    -- 事件驱动：进入/离开编辑器时尝试安装
    local f = CreateFrame("Frame")
    f:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        C_Timer.After(0, TryInstallToStoragePanel)
    end)

    -- 若已在编辑器中，立即尝试
    C_Timer.After(0, TryInstallToStoragePanel)

    -- 兼容：若暴雪过滤器 Mixin 刚初始化完，再次接入我们的下拉扩展
    if _G.HousingCatalogFiltersMixin and not _G.HousingCatalogFiltersMixin._ADT_Hooked then
        hooksecurefunc(HousingCatalogFiltersMixin, "Initialize", function(mixin)
            C_Timer.After(0, function()
                local sp = _G.HouseEditorFrame and _G.HouseEditorFrame.StoragePanel
                if sp and sp.Filters == mixin then
                    HookFilterDropdown(mixin)
                end
            end)
        end)
        _G.HousingCatalogFiltersMixin._ADT_Hooked = true
    end
end

-- 模块装载即初始化
Favorites:Init()
