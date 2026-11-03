import CryptoKit
import Foundation

/// 各翻译源签名算法用到的摘要函数，全部输出小写十六进制。
enum Crypto {
    static func md5Hex(_ string: String) -> String {
        hex(Insecure.MD5.hash(data: Data(string.utf8)))
    }

    static func sha256Hex(_ string: String) -> String {
        hex(SHA256.hash(data: Data(string.utf8)))
    }

    static func hmacSHA256(_ message: String, key: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    static func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    static func hmacSHA256Hex(_ message: String, key: Data) -> String {
        hex(hmacSHA256(message, key: key))
    }

    static func hmacSHA1Base64(_ message: String, key: String) -> String {
        let code = HMAC<Insecure.SHA1>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(key.utf8)))
        return Data(code).base64EncodedString()
    }

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
