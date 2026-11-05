/// 一个当前能执行的命令，以及它属于哪个功能（ADR-0021）。启动器之类的命令面板用它列出命令。
public struct AvailableCommand: Sendable, Hashable, Identifiable {
    public let descriptor: CommandDescriptor
    public let featureID: FeatureID
    /// 功能的显示名，例如"截图"
    public let featureName: String
    /// 功能的 SF Symbol
    public let featureSymbol: String

    public var id: CommandID {
        descriptor.id
    }

    public init(descriptor: CommandDescriptor, featureID: FeatureID, featureName: String, featureSymbol: String) {
        self.descriptor = descriptor
        self.featureID = featureID
        self.featureName = featureName
        self.featureSymbol = featureSymbol
    }

    /// 不用填参数就能执行（没有参数，或者参数都不是必填 / 都有默认值）
    public var runsWithoutArguments: Bool {
        descriptor.parameters.allSatisfy { !$0.isRequired || $0.defaultValue != nil }
    }
}
