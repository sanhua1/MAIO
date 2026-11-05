/// 设置页的说明文字
enum FinderHelp {
    static let open = "Finder 里回车本来是重命名。设成回车后：回车 = 打开文件或进入文件夹，重命名改用 F2。正在重命名时回车照常确认。"
    static let rename = "开始重命名（发出回车）。笔记本键盘上要按 fn + F2，除非在系统设置 › 键盘 里打开了“将 F1、F2 等键用作标准功能键”。"
    static let trash = "⌦ 是向前删除，笔记本上是 fn + ⌫。"
    static let back = "Windows 资源管理器里 Backspace 是后退。重命名、搜索时 ⌫ 照常删字。"
    static let forward = "默认不设：⌥→ 在列表视图里本来是“展开全部子文件夹”。"
    static let enclosing = "和 Windows 的 Alt + ↑ 一样。"
    static let goTo = "打开“前往文件夹”，直接输入或粘贴路径，相当于资源管理器的地址栏。"
    static let cut = """
    记下要移动的文件（先复制，再标记为剪切），到目标文件夹按“粘贴（剪切后移动）”的键就是移动。
    剪切后又复制了别的东西，剪切自动作废。没选中文件时什么也不做。
    """
    static let paste = "只在剪切之后接管，发出 Finder 的“将项目移到这里”；其他时候还是普通粘贴。"
    static let newFile = """
    在当前文件夹（焦点在桌面时是桌面）新建一个空文件，选中并进入重命名，重名时自动加 2、3…
    第一次使用时系统会询问是否允许 MAIO 控制 Finder。
    """
    static let terminal = "在所选终端里打开当前文件夹。第一次使用时系统会询问是否允许 MAIO 控制 Finder。"
    static let native = """
    读的是 Finder 菜单当前真正生效的快捷键。改动写进 Finder 的“App 快捷键”配置\
    （和系统设置 › 键盘 › 键盘快捷键 › App 快捷键是同一份），重启 Finder 后生效。不在菜单里的按键（回车、空格等）只能用上面的 MAIO 增强改。
    """
    static let templates = """
    模板文件夹里的每个文件都是「新建」子菜单的一项，新文件的名字是“新建 ”加模板名（重名时加 2、3…）。
    可以放进自己常用的空白文件，例如带格式的 Word 模板、Keynote 文稿。改完点“刷新”。
    """
    static let cheatSheet = "Finder 在前台时只按住 ⌘ 一会儿，显示所有快捷键（包括 MAIO 增强）；松开 ⌘ 或按别的键就消失。"
    static let viewStyle = """
    新打开的文件夹默认用什么方式显示。已经单独设置过显示方式的文件夹不受影响\
    （它们的设置记在各自的 .DS_Store 里；在显示选项（⌘J）里点“用作默认”可以统一）。
    """
}
