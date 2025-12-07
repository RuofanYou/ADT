-- Bindings.lua
-- 为 ADT 注册按键绑定对应的全局函数

local ADDON_NAME, ADT = ...

-- 绑定头与名称（用于按键设置界面显示）
-- 注意：这些全局常量是暴雪的约定命名，必须是全局。
BINDING_HEADER_ADT = "AdvancedDecorationTools"
BINDING_NAME_ADT_TOGGLE_HISTORY = "打开/关闭：最近放置（历史弹窗）"

-- 历史面板切换
function ADT_ToggleHistory()
    if ADT and ADT.HistoryPopup and ADT.HistoryPopup.Toggle then
        ADT.HistoryPopup:Toggle()
    else
        print("ADT: 历史模块未加载")
    end
end

