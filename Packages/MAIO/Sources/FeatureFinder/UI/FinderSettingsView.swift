import MAIOKit
import MAIOUI
import SwiftUI

/// Finder 增强的设置：快捷键（MAIO 增强 + 原生快捷键 + 速查面板）、隐藏设置。
struct FinderSettingsView: View {
    enum Page: String, CaseIterable {
        case shortcuts = "快捷键"
        case contextMenu = "右键菜单"
        case tweaks = "隐藏设置"
    }

    let context: any FeatureContext
    /// 功能没在运行时为 nil（只能改隐藏设置）
    let enhancer: FinderEnhancer?
    @State private var page = Page.shortcuts
    @State private var restart = RestartState()

    var body: some View {
        Picker("页面", selection: $page) {
            ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        restartBanner
        switch page {
        case .shortcuts:
            if let enhancer {
                FinderShortcutsPage(context: context, enhancer: enhancer, restart: $restart)
            } else {
                Text("打开 Finder 增强后才能设置快捷键。").foregroundStyle(.secondary)
            }
        case .contextMenu:
            if let enhancer {
                FinderContextMenuPage(context: context, enhancer: enhancer)
            }
        case .tweaks:
            FinderTweaksPage(backups: FinderBackups(storage: context.storage), restart: $restart)
        }
    }

    @ViewBuilder private var restartBanner: some View {
        if restart.needed {
            LabeledContent {
                Button("重启 Finder") {
                    FinderPreferences.restartFinder()
                    restart = RestartState()
                    Task {
                        // Finder 重新打开、菜单建好之后再读
                        try? await Task.sleep(for: .seconds(2.5))
                        await enhancer?.refreshMenu()
                    }
                }
            } label: {
                Label(restart.message, systemImage: "arrow.clockwise").foregroundStyle(.orange)
            }
        }
    }
}

/// 有改动要重启 Finder 才生效
struct RestartState: Equatable {
    var needed = false
    var needsRelogin = false

    var message: String {
        needsRelogin ? "重启 Finder 后生效（.DS_Store 设置要重新登录）。有复制任务时先别点" : "重启 Finder 后生效。有复制任务时先别点"
    }
}
