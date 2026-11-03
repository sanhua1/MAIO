/// 把小数像素位移转成整数像素，并把余数带到下一帧。
///
/// 实测（2026-11-02）：合成滚动事件的像素位移会被系统截断为整数，
/// 平滑动画尾部大量 0.x 像素的帧会变成 0，导致总位移少了约 40%。
struct PixelQuantizer {
    private var remainder = (y: 0.0, x: 0.0)

    mutating func quantize(_ frame: (y: Double, x: Double)) -> (y: Double, x: Double) {
        let y = frame.y + remainder.y
        let x = frame.x + remainder.x
        let output = (y: y.rounded(.towardZero), x: x.rounded(.towardZero))
        remainder = (y - output.y, x - output.x)
        return output
    }

    mutating func reset() {
        remainder = (0, 0)
    }
}
