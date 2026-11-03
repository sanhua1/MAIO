/// 取色结果（sRGB，0～255）。
struct SampledColor: Sendable, Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
}

/// 取色的显示和复制格式。
enum ColorFormat: String, Codable, CaseIterable, Sendable {
    case hex
    case rgb

    var title: String {
        switch self {
        case .hex: "HEX（#1A2B3C）"
        case .rgb: "RGB（rgb(26, 43, 60)）"
        }
    }

    var next: ColorFormat {
        self == .hex ? .rgb : .hex
    }

    func string(_ color: SampledColor) -> String {
        switch self {
        case .hex:
            "#" + [color.red, color.green, color.blue].map { byte in
                let digits = String(byte, radix: 16, uppercase: true)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
        case .rgb:
            "rgb(\(color.red), \(color.green), \(color.blue))"
        }
    }
}
