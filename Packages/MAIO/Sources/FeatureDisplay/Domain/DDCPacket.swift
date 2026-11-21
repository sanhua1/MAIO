/// DDC/CI 的 VCP 功能码（MCCS 标准）。
enum VCPCode: UInt8, Sendable, Hashable {
    case brightness = 0x10
    case volume = 0x62
}

/// VCP 当前值和最大值。
struct VCPValue: Sendable, Hashable {
    var current: Int
    var maximum: Int
}

/// 读一个功能码的结果。区分"显示器明确说不支持"和"这次没读到"（刚唤醒、刚接上时常见），后者应该重试、不能当成不支持。
enum DDCReadResult: Sendable, Hashable {
    case value(VCPValue)
    case unsupported
    case failed

    var value: VCPValue? {
        if case let .value(value) = self {
            return value
        }
        return nil
    }
}

/// DDC/CI 数据包的编码与解析（纯逻辑）。
/// 包格式参考：references/MonitorControl/MonitorControl/Support/Arm64DDC.swift（performDDCCommunication）
enum DDCPacket {
    /// 显示器的 7 位 I2C 地址（写地址 0x6E）
    static let chipAddress: UInt8 = 0x37
    /// 主机的子地址
    static let dataAddress: UInt8 = 0x51

    /// 读取请求：长度 0x82、Get VCP（0x01）、功能码、校验
    static func getRequest(_ code: VCPCode) -> [UInt8] {
        withChecksum([0x82, 0x01, code.rawValue])
    }

    /// 写入请求：长度 0x84、Set VCP（0x03）、功能码、值高字节、值低字节、校验
    static func setRequest(_ code: VCPCode, value: Int) -> [UInt8] {
        let clamped = UInt16(clamping: max(0, value))
        return withChecksum([0x84, 0x03, code.rawValue, UInt8(clamped >> 8), UInt8(clamped & 0xFF)])
    }

    /// 解析 Get VCP 回复（11 字节）：6E 88 02 结果 功能码 类型 最大高 最大低 当前高 当前低 校验。
    /// 结果字节 01 是显示器明确回复"不支持"；校验不对、功能码不对、格式不对都算 `failed`（可以重试）。
    static func parse(_ reply: [UInt8], for code: VCPCode) -> DDCReadResult {
        guard reply.count == 11, reply[2] == 0x02, reply[4] == code.rawValue else { return .failed }
        // 回复的校验从 0x50（主机读地址）开始异或
        let checksum = reply[0 ..< 10].reduce(UInt8(0x50), ^)
        guard checksum == reply[10] else { return .failed }
        guard reply[3] == 0x00 else { return reply[3] == 0x01 ? .unsupported : .failed }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        guard maximum > 0 else { return .unsupported }
        return .value(VCPValue(current: min(current, maximum), maximum: maximum))
    }

    private static func withChecksum(_ body: [UInt8]) -> [UInt8] {
        // 校验 = 显示器写地址 ^ 子地址 ^ 包里的每个字节
        body + [body.reduce((chipAddress << 1) ^ dataAddress, ^)]
    }
}
