-- Bindings.lua
-- 为 ADT 注册按键绑定对应的全局函数

local ADDON_NAME, ADT = ...

-- 绑定头与名称（用于按键设置界面显示）
-- 注意：这些全局常量是暴雪的约定命名，必须是全局。
BINDING_HEADER_ADT = "AdvancedDecorationTools"
BINDING_NAME_ADT_TOGGLE_HISTORY = "打开/关闭：最近放置（历史弹窗）"
BINDING_NAME_ADT_COPY_DECOR = "复制（Ctrl+C）：将悬停/选中装饰加入剪切板"
BINDING_NAME_ADT_PASTE_DECOR = "粘贴（Ctrl+V）：从剪切板开始放置"
BINDING_NAME_ADT_CUT_DECOR = "剪切（Ctrl+X）：移除选中并加入剪切板"

-- 高级编辑（虚拟多选）相关绑定名称
BINDING_NAME_ADT_ADV_TOGGLE = "切换：虚拟多选开关（录制并批量同步）"
BINDING_NAME_ADT_ADV_TOGGLE_HOVER = "选集：将悬停装饰加入/移出选集"
BINDING_NAME_ADT_ADV_CLEAR = "选集：清空"
BINDING_NAME_ADT_ADV_ANCHOR_HOVER = "锚点：设为悬停装饰"
BINDING_NAME_ADT_ADV_ANCHOR_SELECTED = "锚点：设为当前选中"

-- 历史面板切换
function ADT_ToggleHistory()
    if ADT and ADT.HistoryPopup and ADT.HistoryPopup.Toggle then
        ADT.HistoryPopup:Toggle()
    else
        if ADT and ADT.Notify then ADT.Notify("历史模块未加载", 'error') end
    end
end

-- 复制（Ctrl+C）：优先悬停，其次选中
function ADT_CopyDecor()
    if not (ADT and ADT.Housing and ADT.Housing.Binding_Copy) then
        if ADT and ADT.Notify then ADT.Notify("住宅模块未加载，无法复制", 'error') end
        return
    end
    ADT.Housing:Binding_Copy()
end

-- 粘贴（Ctrl+V）：使用剪切板 recordID 进入放置
function ADT_PasteDecor()
    if not (ADT and ADT.Housing and ADT.Housing.Binding_Paste) then
        if ADT and ADT.Notify then ADT.Notify("住宅模块未加载，无法粘贴", 'error') end
        return
    end
    ADT.Housing:Binding_Paste()
end

-- 剪切（Ctrl+X）：仅支持“当前已选中”的装饰
function ADT_CutDecor()
    if not (ADT and ADT.Housing and ADT.Housing.Binding_Cut) then
        if ADT and ADT.Notify then ADT.Notify("住宅模块未加载，无法剪切", 'error') end
        return
    end
    ADT.Housing:Binding_Cut()
end

-- ===== 高级编辑：虚拟多选 =====
local function AdvLoaded()
    return ADT and ADT.AdvancedEdit
end

function ADT_Adv_Toggle()
    if not AdvLoaded() then print("ADT: 高级编辑模块未加载") return end
    ADT.AdvancedEdit:ToggleEnabled()
end

function ADT_Adv_ToggleHovered()
    if not AdvLoaded() then print("ADT: 高级编辑模块未加载") return end
    ADT.AdvancedEdit:ToggleHovered()
end

function ADT_Adv_ClearSelection()
    if not AdvLoaded() then print("ADT: 高级编辑模块未加载") return end
    ADT.AdvancedEdit:ClearSelection()
    print("ADT: 选集已清空")
end

function ADT_Adv_SetAnchor_Hovered()
    if not AdvLoaded() then print("ADT: 高级编辑模块未加载") return end
    ADT.AdvancedEdit:SetAnchorByHovered()
end

function ADT_Adv_SetAnchor_Selected()
    if not AdvLoaded() then print("ADT: 高级编辑模块未加载") return end
    ADT.AdvancedEdit:SetAnchorBySelected()
end
