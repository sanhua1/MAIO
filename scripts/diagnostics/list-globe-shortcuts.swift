import CoreGraphics
import Foundation

let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
typealias GetValue = @convention(c) (
    Int32,
    UnsafeMutablePointer<UInt16>,
    UnsafeMutablePointer<UInt16>,
    UnsafeMutablePointer<UInt32>,
) -> Int32
typealias IsEnabled = @convention(c) (Int32) -> Bool
let get = unsafeBitCast(dlsym(h, "CGSGetSymbolicHotKeyValue"), to: GetValue.self)
let enabled = unsafeBitCast(dlsym(h, "CGSIsSymbolicHotKeyEnabled"), to: IsEnabled.self)
let names: [UInt16: String] = [
    0: "A",
    1: "S",
    2: "D",
    3: "F",
    4: "H",
    5: "G",
    6: "Z",
    7: "X",
    8: "C",
    9: "V",
    11: "B",
    12: "Q",
    13: "W",
    14: "E",
    15: "R",
    16: "Y",
    17: "T",
    31: "O",
    32: "U",
    34: "I",
    35: "P",
    37: "L",
    38: "J",
    40: "K",
    45: "N",
    46: "M",
    49: "Space",
    51: "Delete",
    36: "Return",
    123: "←",
    124: "→",
    125: "↓",
    126: "↑",
    63: "Fn",
    179: "🌐",
]
for id in Int32(0) ... 400 {
    var ch: UInt16 = 0, code: UInt16 = 0; var mods: UInt32 = 0
    guard get(id, &ch, &code, &mods) == 0, mods & 0x800000 != 0 else { continue }
    var m = ""
    if mods & 0x40000 != 0 {
        m += "⌃"
    }; if mods & 0x80000 != 0 {
        m += "⌥"
    }
    if mods & 0x20000 != 0 {
        m += "⇧"
    }; if mods & 0x100000 != 0 {
        m += "⌘"
    }
    print("\(id)\t🌐\(m)\(names[code] ?? "key\(code)")\t\(enabled(id) ? "开启" : "关闭")")
}
