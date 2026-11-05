import Foundation

/// 汉字转拼音（不带声调）。用系统的 `CFStringTransform`，逐字转换。
/// 系统逐字转换时多音字只给一个读音（"音乐"会变成 yin le），常见多音字另外补上其他读音。
enum Pinyin {
    /// 是否是汉字（基本区 + 扩展 A 区）
    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00 ... 0x9FFF).contains(scalar.value) || (0x3400 ... 0x4DBF).contains(scalar.value)
    }

    static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHan)
    }

    /// 一个汉字的全部读音（小写、无声调），第一个是系统给的读音
    static func readings(of character: Character) -> [String] {
        let text = String(character)
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let primary = (mutable as String).lowercased().trimmingCharacters(in: .whitespaces)
        var result = primary.isEmpty || primary == text ? [] : [primary]
        for extra in polyphones[character] ?? [] where !result.contains(extra) {
            result.append(extra)
        }
        return result
    }

    /// 应用名、文件名里常见的多音字（系统给的读音之外的其他读音）
    static let polyphones: [Character: [String]] = [
        "乐": ["le", "yue"], "行": ["xing", "hang"], "重": ["zhong", "chong"], "长": ["chang", "zhang"],
        "调": ["tiao", "diao"], "传": ["chuan", "zhuan"], "藏": ["cang", "zang"], "便": ["bian", "pian"],
        "还": ["hai", "huan"], "和": ["he", "huo"], "觉": ["jue", "jiao"], "曾": ["ceng", "zeng"],
        "朝": ["chao", "zhao"], "解": ["jie", "xie"], "薄": ["bo", "bao"], "率": ["lv", "shuai"],
        "都": ["du", "dou"], "地": ["di", "de"], "的": ["de", "di"], "得": ["de", "dei"],
        "着": ["zhe", "zhao", "zhuo"], "了": ["le", "liao"], "系": ["xi", "ji"], "区": ["qu", "ou"],
        "单": ["dan", "shan"], "角": ["jiao", "jue"], "屏": ["ping", "bing"], "盛": ["sheng", "cheng"],
        "省": ["sheng", "xing"], "差": ["cha", "chai"], "卡": ["ka", "qia"], "合": ["he", "ge"],
        "弹": ["tan", "dan"], "参": ["can", "shen"], "校": ["xiao", "jiao"], "奇": ["qi", "ji"],
        "数": ["shu"], "量": ["liang"], "降": ["jiang", "xiang"], "供": ["gong"], "转": ["zhuan"],
        "会": ["hui", "kuai"], "露": ["lu", "lou"], "色": ["se", "shai"], "似": ["si", "shi"],
        "厦": ["xia", "sha"], "折": ["zhe", "she"], "背": ["bei"], "强": ["qiang", "jiang"],
        "剥": ["bo", "bao"], "壳": ["ke", "qiao"], "约": ["yue", "yao"], "思": ["si"],
    ]
}
