/// 启动器自带的系统操作（现有的"系统操作"功能里的命令都要填参数，不适合直接从启动器执行）。
enum SystemAction: String, CaseIterable, Sendable {
    case lockScreen
    case sleep
    case displaySleep
    case screenSaver
    case logOut
    case restart
    case shutDown
    case emptyTrash
    case toggleDarkMode

    var title: String {
        switch self {
        case .lockScreen: "锁定屏幕"
        case .sleep: "睡眠"
        case .displaySleep: "关闭显示器"
        case .screenSaver: "启动屏幕保护程序"
        case .logOut: "退出登录"
        case .restart: "重新启动"
        case .shutDown: "关机"
        case .emptyTrash: "清空废纸篓"
        case .toggleDarkMode: "切换深色模式"
        }
    }

    /// 别的叫法（中英文都能搜到）
    var keywords: [String] {
        switch self {
        case .lockScreen: ["锁屏", "Lock Screen"]
        case .sleep: ["休眠", "Sleep"]
        case .displaySleep: ["熄屏", "关屏", "Display Sleep", "Turn Off Display"]
        case .screenSaver: ["屏保", "Screen Saver"]
        case .logOut: ["注销", "Log Out", "Logout"]
        case .restart: ["重启", "Restart", "Reboot"]
        case .shutDown: ["关闭电脑", "Shut Down", "Shutdown", "Power Off"]
        case .emptyTrash: ["垃圾桶", "回收站", "Empty Trash"]
        case .toggleDarkMode: ["暗色", "夜间模式", "浅色模式", "外观", "Dark Mode", "Toggle Appearance"]
        }
    }

    var summary: String {
        switch self {
        case .lockScreen: "立即锁定，需要输入密码才能回来"
        case .sleep: "让电脑立即睡眠"
        case .displaySleep: "只关闭显示器，程序继续运行"
        case .screenSaver: "立即启动屏幕保护程序"
        case .logOut: "系统会先弹出确认框"
        case .restart: "系统会先弹出确认框"
        case .shutDown: "系统会先弹出确认框"
        case .emptyTrash: "会先确认；删除后不能恢复"
        case .toggleDarkMode: "在浅色和深色外观之间切换"
        }
    }

    /// SF Symbol
    var symbol: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleep: "moon.zzz.fill"
        case .displaySleep: "display"
        case .screenSaver: "sparkles.tv"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .restart: "arrow.clockwise.circle.fill"
        case .shutDown: "power.circle.fill"
        case .emptyTrash: "trash.fill"
        case .toggleDarkMode: "circle.lefthalf.filled"
        }
    }
}
