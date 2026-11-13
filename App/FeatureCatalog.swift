import FeatureClipboard
import FeatureFinder
import FeatureKeys
import FeatureLauncher
import FeatureScreenshot
import FeatureScroll
import FeatureSwitcher
import FeatureSystemActions
import FeatureTranslate

// @new-feature-import
import MAIOKit

/// ★ 注册所有功能的唯一位置（见 docs/FEATURE_GUIDE.md）。
/// 顺序即设置窗口侧边栏和菜单中的顺序。
@MainActor
enum FeatureCatalog {
    static let all: [any Feature.Type] = [
        SystemActionsFeature.self,
        LauncherFeature.self,
        SwitcherFeature.self,
        ScrollFeature.self,
        ClipboardFeature.self,
        TranslateFeature.self,
        ScreenshotFeature.self,
        // Finder 增强和按键映射都注册按键过滤器，过滤器按启动顺序串联：保持 Finder 在按键映射之前
        FinderFeature.self,
        KeysFeature.self,
        // @new-feature-catalog
    ]
}
