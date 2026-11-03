import MAIOKit
import SwiftUI

struct __NAME__SettingsView: View {
    let settings: any SettingsService
    @State private var value: __NAME__Settings

    init(settings: any SettingsService) {
        self.settings = settings
        _value = State(initialValue: settings.load(__NAME__Settings.self))
    }

    var body: some View {
        Toggle("示例开关", isOn: $value.isExampleEnabled)
            .onChange(of: value) { _, newValue in settings.save(newValue) }
    }
}
