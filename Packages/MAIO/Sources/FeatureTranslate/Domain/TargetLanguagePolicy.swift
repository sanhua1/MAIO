/// 目标语言规则：原文已经是目标语言时，改为翻译成第二目标语言（例如中文 → 英文，其他 → 中文）。
enum TargetLanguagePolicy {
    static func target(detected: Language?, preferred: Language, second: Language) -> Language {
        guard let detected, detected != .auto else { return preferred }
        if detected == preferred || (detected.isChinese && preferred.isChinese) {
            return second
        }
        return preferred
    }
}
