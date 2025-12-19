-- Bindings.lua
-- 为 ADT 注册按键绑定对应的全局函数

local ADDON_NAME, ADT = ...

-- 绑定头与名称（用于按键设置界面显示）
-- 注意：这些全局常量是暴雪的约定命名，必须是全局。
BINDING_HEADER_ADT = "AdvancedDecorationTools"
BINDING_NAME_ADT_TOGGLE_HISTORY = "打开/关闭：最近放置（Dock 分类）"
-- 临时板专用按键
BINDING_NAME_ADT_TEMP_STORE = "临时板：存入并移除（Ctrl+S）"
BINDING_NAME_ADT_TEMP_RECALL = "临时板：取出并放置（Ctrl+R）"
-- 旋转快捷键（建议在按键设置里绑定到 Q/E）
BINDING_NAME_ADT_ROTATE_CCW_90 = "旋转 -90°（逆时针）"
BINDING_NAME_ADT_ROTATE_CW_90  = "旋转 +90°（顺时针）"

-- 额外剪切板
-- 旧剪切板相关绑定名已移除

-- 历史面板切换
function ADT_ToggleHistory()
    local Main = ADT and ADT.CommandDock and ADT.CommandDock.SettingsPanel
    if not Main then return end
    -- 若当前已显示且正处于“最近放置”分类，则收起；否则打开并切到该分类
    if Main:IsShown() and Main.currentDecorCategory == 'History' then
        Main:Hide(); return
    end
    local mode = (HouseEditorFrame and HouseEditorFrame:IsShown()) and "editor" or "standalone"
    Main:ShowUI(mode)
    if Main.ShowDecorListCategory then Main:ShowDecorListCategory('History') end
end

-- 原“复制/粘贴/剪切”快捷键已废弃，避免多套逻辑并存。

-- ===== 临时板：仅保留两项快捷键 =====
local function TempLoaded()
    return ADT and ADT.Clipboard
end

function ADT_Temp_StoreSelected()
    if not TempLoaded() then print("ADT: 临时板模块未加载") return end
    ADT.Clipboard:StoreSelectedAndRemove()
end

function ADT_Temp_RecallTop()
    if not TempLoaded() then print("ADT: 临时板模块未加载") return end
    ADT.Clipboard:RecallTopStartPlacing()
end

-- ===== 基本模式：旋转90°（基于 AutoRotate 的步进映射） =====
local function RotateLoaded()
    return ADT and ADT.RotateHotkey and ADT.RotateHotkey.RotateSelectedByDegrees
end

function ADT_Rotate_CCW_90()
    if not RotateLoaded() then print("ADT: 旋转模块未加载") return end
    ADT.RotateHotkey:RotateSelectedByDegrees(-90)
end

function ADT_Rotate_CW_90()
    if not RotateLoaded() then print("ADT: 旋转模块未加载") return end
    ADT.RotateHotkey:RotateSelectedByDegrees(90)
end

-- ===== 专家模式：快速选轴（Alt+Q/W/E → X/Y/Z） =====
BINDING_NAME_ADT_AXIS_X = "专家模式：切换到 X 轴"
BINDING_NAME_ADT_AXIS_Y = "专家模式：切换到 Y 轴"
BINDING_NAME_ADT_AXIS_Z = "专家模式：切换到 Z 轴"

function ADT_Axis_X()
    if ADT and ADT.AxisSelect then ADT.AxisSelect:SelectAxisX() end
end

function ADT_Axis_Y()
    if ADT and ADT.AxisSelect then ADT.AxisSelect:SelectAxisY() end
end

function ADT_Axis_Z()
    if ADT and ADT.AxisSelect then ADT.AxisSelect:SelectAxisZ() end
end
