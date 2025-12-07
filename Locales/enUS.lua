-- ADT 本地化系统
-- 所有语言字符串定义在此处，支持运行时切换
local ADDON_NAME, ADT = ...
ADT = ADT or {}

-- 语言表存储（每个语言单独存储，便于切换）
ADT.Locales = ADT.Locales or {}
ADT.L = ADT.L or {}

-- 英文语言表（默认）
ADT.Locales.enUS = {
    ["ModuleName Housing_DecorHover"] = "Decor: Press to Repeat",
    ["ModuleDescription Housing_DecorHover"] = "In Decorate Mode:\n\n- Hover the cursor over a decor to display its name and its item count in storage.\n\n- Press Ctrl+D to \"duplicate\" the hovered decor (default).\n\nThe new object will not inherit the current angles and scales.",
    ["Duplicate"] = "Duplicate",
    ["Hotkey Cut"] = "Cut",
    ["Hotkey Copy"] = "Copy",
    ["Hotkey Paste"] = "Paste",
    ["Hotkey Store"] = "Store",
    ["Hotkey Recall"] = "Recall",
    ["Hotkey BatchPlace"] = "Batch Place",
    ["Duplicate Decor Key"] = "\"Duplicate\" Key",
    ["Enable Duplicate"] = "Enable CTRL+D Duplicate",
    ["Enable Duplicate tooltip"] = "While in Decorate Mode, you can hover the cursor over a decor and then press a key to place another instance of this object.",
    ["Enable Copy"] = "Enable CTRL+C Copy",
    ["Enable Copy tooltip"] = "Copy the hovered or selected decor to the clipboard with Ctrl+C.",
    ["Enable Paste"] = "Enable CTRL+V Paste",
    ["Enable Paste tooltip"] = "Paste a decor from the clipboard with Ctrl+V.",
    ["Enable Cut"] = "Enable CTRL+X Cut",
    ["Enable Cut tooltip"] = "Remove the selected decor and copy it to the clipboard with Ctrl+X.",
    ["Enable Batch Place"] = "Enable CTRL Batch Place",
    ["Enable Batch Place tooltip"] = "Hold Ctrl to continuously place the same decor after selecting it.",
    ["Enable T Reset"] = "Enable T Reset (Current)",
    ["Enable T Reset tooltip"] = "In Expert Mode, pressing T resets the current transform submode. Turn off to keep only Ctrl+T (reset all).",
    ["Enable CTRL+T Reset All"] = "Enable CTRL+T Reset All",
    ["Enable CTRL+T Reset All tooltip"] = "In Expert Mode, pressing Ctrl+T resets all transforms. Turn off to disable the hotkey and hide the hint.",
    
    ["SC Housing"] = "General",
    ["SC Clipboard"] = "Clipboard",
    ["SC History"] = "Recent",
    ["SC About"] = "About",
    ["List Is Empty"] = "No results",
    ["Category Colon"] = "Category: ",
    
    -- Interaction / Locking
    ["LOCKED"] = "LOCKED",
    ["UNLOCKED"] = "UNLOCKED",
    ["ADT: Decor %s"] = "ADT: Decor %s",
    ["This item is LOCKED by ADT."] = "This item is LOCKED by ADT.",
    ["Unknown Decor"] = "Unknown Decor",
    ["Decor #%d"] = "Decor #%d",
    ["Stock: %d"] = "Stock: %d",
    ["Stock: 0 (Unavailable)"] = "Stock: 0 (Unavailable)",
    ["Left Click: Place"] = "Left Click: Place",
    ["Right Click: Remove from Clipboard"] = "Right Click: Remove from Clipboard",
    ["Cannot Place Decor"] = "Unable to place this decor (out of stock or not owned)",

    -- Top notices & prompts
    ["Hover a decor to lock"] = "Hover a decor to lock.",
    ["Unlocked %s"] = "Unlocked \"%s\"",
    ["Locked %s"] = "Locked \"%s\"",
    ["Decor is locked"] = "This decor is protected.",
    ["Confirm edit?"] = "Proceed with editing?",
    ["Continue Edit"] = "Continue",
    ["Cancel Select"] = "Cancel Selection",
    ["Unlock"] = "Unlock",
    ["Edit allowed"] = "Editing allowed this time.",
    ["Selection cancelled"] = "Selection cancelled.",
    ["No decor to copy"] = "No hovered or selected decor to copy.",
    ["Copied to clipboard"] = "Copied to clipboard.",
    ["Clipboard empty, cannot paste"] = "Clipboard is empty, cannot paste.",
    ["Cannot start placing"] = "Cannot start placing (stock 0 or at limit).",
    ["Saved to clipboard tip"] = "Saved to clipboard; select it then press Ctrl+X again to remove.",
    ["Select then press Ctrl+X"] = "Please select a decor, then press Ctrl+X.",
    ["Removed and saved to clipboard"] = "Removed and added to clipboard.",
    ["Removed %s and saved to clipboard"] = "Removed \"%s\" and added to clipboard.",
    ["Cannot remove decor"] = "Cannot remove this decor (not removable or not selected).",
    ["Reset requires Expert Mode"] = "Switch to Expert Mode first (press 2).",
    ["No decor selected"] = "No decor selected.",
    ["Current transform reset"] = "Current transform reset.",
    ["All transforms reset"] = "All transforms reset (rotation + scale).",

    -- Clipboard module
    ["Added to clipboard: %s x%d"] = "Added to clipboard: %s x%d",
    ["Please select a decor to store"] = "Please select a decor to store.",
    ["Cannot remove, check mode"] = "Unable to remove this decor; ensure removable mode.",
    ["Clipboard is empty"] = "Clipboard is empty.",
    ["No hovered decor"] = "No hovered decor detected.",
    ["No selected decor"] = "No selected decor.",
    ["Selection empty or AE off"] = "Selection set is empty (or Advanced Edit disabled).",
    ["Selection has no valid decor"] = "No valid decor in selection.",
    ["Cannot start placing 2"] = "Cannot start placing (insufficient stock or at limit).",
    ["Clipboard UI not loaded"] = "Clipboard UI not loaded; please /reload or report this issue.",

    -- History
    ["Enter editor then choose history"] = "Enter the house editor first, then choose from history.",
    ["History module not loaded"] = "History module not loaded.",

    -- Debug
    ["ADT Debug Enabled"] = "ADT Debug: Enabled",
    ["ADT Debug Disabled"] = "ADT Debug: Disabled",
    
    -- 语言选择
    ["Language"] = "Language",
    ["Language Auto"] = "Auto (Client)",
    ["Language Reload Hint"] = "Some text may update after /reload",
    -- 空列表/提示
    ["Clipboard Empty Line1"] = "Clipboard is empty",
    ["Clipboard Empty Line2"] = "Ctrl+S Store; Ctrl+R Recall",
    ["History Empty Line1"] = "No placements yet",
    ["History Empty Line2"] = "Will record automatically after a placement",
    ["List Is Empty"] = "No results",

    -- About 面板
    ["Addon Full Name"] = "Advanced Decoration Tools",
    ["Version Label"] = "Version: %s",
    ["Credits Label"] = "Credits",
    ["Bilibili Label"] = "bilibili:",
}

-- 中文语言表
ADT.Locales.zhCN = {
    ["ModuleName Housing_DecorHover"] = "装饰物：按下以重复",
    ["ModuleDescription Housing_DecorHover"] = "在装饰模式：\n\n- 鼠标悬停装饰以显示其名称与库存数量。\n\n- 按下 Ctrl+D 可快速\"复制\"一个相同的装饰进入放置状态（默认）。\n\n新对象不会继承当前角度与缩放。",
    ["Duplicate"] = "重复",
    ["Hotkey Cut"] = "剪切",
    ["Hotkey Copy"] = "复制",
    ["Hotkey Paste"] = "粘贴",
    ["Hotkey Store"] = "存储",
    ["Hotkey Recall"] = "读取",
    ["Hotkey BatchPlace"] = "批量放置",
    ["Duplicate Decor Key"] = "重复热键",
    ["Enable Duplicate"] = "启用 CTRL+D 重复",
    ["Enable Duplicate tooltip"] = "在装饰模式下，鼠标悬停装饰后按下热键，可直接放置一个同款新实例。",
    ["Enable Copy"] = "启用 CTRL+C 复制",
    ["Enable Copy tooltip"] = "在悬停或选中装饰时按 Ctrl+C 将其复制到剪切板。",
    ["Enable Paste"] = "启用 CTRL+V 粘贴",
    ["Enable Paste tooltip"] = "按 Ctrl+V 从剪切板粘贴装饰。",
    ["Enable Cut"] = "启用 CTRL+X 剪切",
    ["Enable Cut tooltip"] = "选中装饰后按 Ctrl+X 将其移除并复制到剪切板。",
    ["Enable Batch Place"] = "启用 CTRL 批量放置",
    ["Enable Batch Place tooltip"] = "选中装饰后按住 Ctrl 点击，可连续放置多个相同装饰。",
    ["Enable T Reset"] = "启用 T 重置默认属性",
    ["Enable T Reset tooltip"] = "在专家模式下，按 T 重置当前子模式的变换；关闭后仅保留 Ctrl+T 的“全部重置”。",
    ["Enable CTRL+T Reset All"] = "启用 CTRL+T 全部重置",
    ["Enable CTRL+T Reset All tooltip"] = "在专家模式下，按 Ctrl+T 重置所有变换；关闭后禁用该热键并隐藏提示。",
    
    ["SC Housing"] = "通用",
    ["SC Clipboard"] = "临时板",
    ["SC History"] = "最近放置",
    ["SC About"] = "信息",
    ["List Is Empty"] = "暂无结果",
    ["Category Colon"] = "分类：",

    -- About 面板
    ["Addon Full Name"] = "高级装修工具",
    ["Version Label"] = "版本：%s",
    ["Credits Label"] = "制作信息",
    ["Bilibili Label"] = "bilibili:",
    
    -- 交互/锁定
    ["LOCKED"] = "已锁定",
    ["UNLOCKED"] = "未锁定",
    ["ADT: Decor %s"] = "ADT：装饰 %s",
    ["This item is LOCKED by ADT."] = "该物体已被 ADT 锁定。",
    ["Unknown Decor"] = "未知装饰",
    ["Decor #%d"] = "装饰 #%d",
    ["Stock: %d"] = "库存：%d",
    ["Stock: 0 (Unavailable)"] = "库存：0（不可放置）",
    ["Left Click: Place"] = "左键：开始放置",
    ["Right Click: Remove from Clipboard"] = "右键：从临时板移除",
    ["Cannot Place Decor"] = "无法放置该装饰（可能已用完或未拥有）",
    
    -- 语言选择
    ["Language"] = "语言 / Language",
    ["Language Auto"] = "自动 (跟随客户端)",
    ["Language Reload Hint"] = "部分文字可能需要 /reload 后更新",
    -- 空列表/提示
    ["Clipboard Empty Line1"] = "临时板为空",
    ["Clipboard Empty Line2"] = "Ctrl+S 存入；Ctrl+R 取出",
    ["History Empty Line1"] = "暂无放置记录",
    ["History Empty Line2"] = "放置装饰后会自动记录",
    -- 顶部提示与弹窗
    ["Hover a decor to lock"] = "请先将鼠标悬停在装饰上",
    ["Unlocked %s"] = "已解锁「%s」",
    ["Locked %s"] = "已锁定「%s」",
    ["Decor is locked"] = "该装饰已被锁定保护",
    ["Confirm edit?"] = "确认要编辑吗？",
    ["Continue Edit"] = "继续编辑",
    ["Cancel Select"] = "取消选中",
    ["Unlock"] = "解除保护",
    ["Edit allowed"] = "已允许本次编辑",
    ["Selection cancelled"] = "已取消选中",
    ["No decor to copy"] = "未检测到悬停或选中的装饰，无法复制",
    ["Copied to clipboard"] = "已复制到剪切板",
    ["Clipboard empty, cannot paste"] = "剪切板为空，无法粘贴",
    ["Cannot start placing"] = "无法进入放置（可能库存为 0 或已达上限）",
    ["Saved to clipboard tip"] = "已记录剪切板；请先点击选中该装饰后再按 Ctrl+X 完成移除",
    ["Select then press Ctrl+X"] = "请先点击选中要移除的装饰，再按 Ctrl+X",
    ["Removed and saved to clipboard"] = "已移除并加入剪切板",
    ["Removed %s and saved to clipboard"] = "「%s」已移除，已加入剪切板",
    ["Cannot remove decor"] = "无法移除该装饰（可能不在可移除模式或未被选中）",
    ["Reset requires Expert Mode"] = "需先切换到专家模式（按 2）",
    ["No decor selected"] = "请先选中一个装饰",
    ["Current transform reset"] = "已重置当前变换",
    ["All transforms reset"] = "已重置所有变换（旋转+缩放）",

    -- 剪切板模块
    ["Added to clipboard: %s x%d"] = "已加入剪切板：%s x%d",
    ["Please select a decor to store"] = "请先点击选中要存入的装饰",
    ["Cannot remove, check mode"] = "无法移除该装饰，请确认处于可移除模式",
    ["Clipboard is empty"] = "临时板为空",
    ["No hovered decor"] = "未检测到悬停装饰",
    ["No selected decor"] = "当前未选中装饰",
    ["Selection empty or AE off"] = "选集为空（或高级编辑未开启）",
    ["Selection has no valid decor"] = "选集中没有有效装饰",
    ["Cannot start placing 2"] = "无法进入放置（库存不足或达到上限）",
    ["Clipboard UI not loaded"] = "剪切板 UI 未加载，请重载界面或报告问题",

    -- 历史
    ["Enter editor then choose history"] = "请先进入住宅编辑模式，再从历史选择。",
    ["History module not loaded"] = "历史模块未加载",

    -- 调试
    ["ADT Debug Enabled"] = "ADT 调试已开启",
    ["ADT Debug Disabled"] = "ADT 调试已关闭",
}

-- 应用指定语言到 ADT.L
function ADT.ApplyLocale(localeKey)
    local sourceTable = ADT.Locales[localeKey]
    if not sourceTable then
        sourceTable = ADT.Locales.enUS  -- 回退到英文
        localeKey = "enUS"
    end
    -- 切换语言前清空旧表，避免残留（单一权威）
    wipe(ADT.L)
    for k, v in pairs(sourceTable) do
        ADT.L[k] = v
    end
    ADT.CurrentLocale = localeKey
end

-- 获取当前应使用的语言
function ADT.GetActiveLocale()
    -- 优先使用用户设置
    local userLang = ADT_DB and ADT_DB.SelectedLanguage
    if userLang and ADT.Locales[userLang] then
        return userLang
    end
    -- 否则使用客户端语言
    local clientLang = GetLocale()
    if ADT.Locales[clientLang] then
        return clientLang
    end
    -- 默认英文
    return "enUS"
end

-- 初始化语言
local function InitLocale()
    local locale = ADT.GetActiveLocale()
    ADT.ApplyLocale(locale)
end

-- 立即初始化
InitLocale()
