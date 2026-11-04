import SwiftUI

public extension View {
    /// 浮动面板的玻璃背景（翻译窗口、剪贴板面板、窗口切换器、提示条等共用）：玻璃效果，再裁成同样的圆角。
    ///
    /// 窗口是 key window 时，液态玻璃会带一圈柔和的投影（实测，下方比上方深）。面板窗口和玻璃差不多大，
    /// 投影大部分落在窗口外、被窗口边界裁掉，只剩圆角外、窗口矩形以内的四个角：
    /// 浅色模式下看起来是四个灰色的方角（有用户反馈），深色模式下几乎看不出来。
    /// 裁成圆角后四个角完全透明，其他地方的外观不变。
    ///
    /// 玻璃在大窗口中间时（例如截图遮罩上的工具栏）投影是完整的，不需要它。
    func panelGlass(cornerRadius: CGFloat) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
