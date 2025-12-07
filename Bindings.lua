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

-- 历史面板切换
function ADT_ToggleHistory()
    if ADT and ADT.HistoryPopup and ADT.HistoryPopup.Toggle then
        ADT.HistoryPopup:Toggle()
    else
        print("ADT: 历史模块未加载")
    end
end

-- 复制（Ctrl+C）：优先悬停，其次选中
function ADT_CopyDecor()
    if not (ADT and ADT.Housing and ADT.Housing.Binding_Copy) then
        print("ADT: 住宅模块未加载，无法复制")
        return
    end
    ADT.Housing:Binding_Copy()
end

-- 粘贴（Ctrl+V）：使用剪切板 recordID 进入放置
function ADT_PasteDecor()
    if not (ADT and ADT.Housing and ADT.Housing.Binding_Paste) then
        print("ADT: 住宅模块未加载，无法粘贴")
        return
    end
    ADT.Housing:Binding_Paste()
end

-- 剪切（Ctrl+X）：仅支持“当前已选中”的装饰
function ADT_CutDecor()
    if not (ADT and ADT.Housing and ADT.Housing.Binding_Cut) then
        print("ADT: 住宅模块未加载，无法剪切")
        return
    end
    ADT.Housing:Binding_Cut()
end
