import MAIOKit

/// "命令"来源的全部条目：MAIO 命令 → 系统操作 → 系统设置面板。
enum CommandList {
    static func items(maio: [AvailableCommand], panes: [SettingsPane], own: FeatureID) -> [LauncherItem] {
        let commands = maio.filter { $0.featureID != own && $0.runsWithoutArguments }.map { command in
            LauncherItem.command(
                id: command.id.rawValue, title: command.descriptor.title,
                feature: command.featureName, symbol: command.featureSymbol,
            )
        }
        return commands + SystemAction.allCases.map(LauncherItem.system) + panes.map(LauncherItem.settingsPane)
    }
}
