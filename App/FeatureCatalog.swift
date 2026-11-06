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
        ScrollFeature.self,
        SwitcherFeature.self,
        TranslateFeature.self,
        ClipboardFeature.self,
        ScreenshotFeature.self,
        FinderFeature.self,
        LauncherFeature.self,
        KeysFeature.self,
        // @new-feature-catalog
    ]
}
