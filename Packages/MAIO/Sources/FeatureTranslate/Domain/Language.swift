/// 翻译语言。rawValue 是 BCP 47 代码，各翻译源再映射成自己的代码。
enum Language: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"
    case italian = "it"
    case portuguese = "pt"
    case vietnamese = "vi"
    case thai = "th"
    case arabic = "ar"
    case indonesian = "id"
    case malay = "ms"
    case turkish = "tr"
    case polish = "pl"
    case dutch = "nl"
    case ukrainian = "uk"

    var id: String {
        rawValue
    }

    /// 可以作为目标语言的（不含"自动"）
    static var targets: [Language] {
        allCases.filter { $0 != .auto }
    }

    var displayName: String {
        switch self {
        case .auto: "自动检测"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁体中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        case .german: "德语"
        case .spanish: "西班牙语"
        case .russian: "俄语"
        case .italian: "意大利语"
        case .portuguese: "葡萄牙语"
        case .vietnamese: "越南语"
        case .thai: "泰语"
        case .arabic: "阿拉伯语"
        case .indonesian: "印尼语"
        case .malay: "马来语"
        case .turkish: "土耳其语"
        case .polish: "波兰语"
        case .dutch: "荷兰语"
        case .ukrainian: "乌克兰语"
        }
    }

    /// 写进大模型提示词的英文名
    var englishName: String {
        switch self {
        case .auto: "the detected language"
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .english: "English"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .french: "French"
        case .german: "German"
        case .spanish: "Spanish"
        case .russian: "Russian"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .vietnamese: "Vietnamese"
        case .thai: "Thai"
        case .arabic: "Arabic"
        case .indonesian: "Indonesian"
        case .malay: "Malay"
        case .turkish: "Turkish"
        case .polish: "Polish"
        case .dutch: "Dutch"
        case .ukrainian: "Ukrainian"
        }
    }

    var isChinese: Bool {
        self == .simplifiedChinese || self == .traditionalChinese
    }
}
