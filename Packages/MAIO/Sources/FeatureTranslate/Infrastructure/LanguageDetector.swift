import NaturalLanguage

/// 本地语种识别（系统自带，离线、几乎零延迟）。识别结果用于决定目标语言，并告诉需要源语言的翻译源。
enum LanguageDetector {
    static func detect(_ text: String) -> Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = mapping.map(\.0)
        recognizer.processString(String(text.prefix(500)))
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return mapping.first { $0.0 == dominant }?.1
    }

    private static let mapping: [(NLLanguage, Language)] = [
        (.simplifiedChinese, .simplifiedChinese), (.traditionalChinese, .traditionalChinese),
        (.english, .english), (.japanese, .japanese), (.korean, .korean), (.french, .french),
        (.german, .german), (.spanish, .spanish), (.russian, .russian), (.italian, .italian),
        (.portuguese, .portuguese), (.vietnamese, .vietnamese), (.thai, .thai), (.arabic, .arabic),
        (.indonesian, .indonesian), (.malay, .malay), (.turkish, .turkish), (.polish, .polish),
        (.dutch, .dutch), (.ukrainian, .ukrainian),
    ]
}
