import SwiftUI
import LoopKit

struct SettingsView: View {
    var onChanged: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var settings: AppSettings?
    @State private var errorMessage: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section("Interface") {
                toggle("Toggle with short press", \.shortToggle) { try $0.setShortToggle(enabled: $1) }
                toggle("Day ends at 3 AM", \.midnightDelay) { try $0.setMidnightDelay(enabled: $1) }
                toggle("Enable skip days", \.skipEnabled) { try $0.setSkipEnabled(enabled: $1) }
                toggle("Enable question marks", \.questionMarksEnabled) { try $0.setQuestionMarksEnabled(enabled: $1) }
                toggle("Reverse order of days", \.reverseCheckmarks) { try $0.setReverseCheckmarks(enabled: $1) }
                Picker("First day of the week", selection: Binding(
                    get: { Int(settings?.firstWeekdayChoice ?? -1) },
                    set: { choice in write { try $0.setFirstWeekday(choice: Int32(choice)) } })) {
                    Text("System default").tag(-1)
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.standaloneWeekdaySymbols[day - 1]).tag(day)
                    }
                }
            }
            Section("Reminders") {
                Button("Notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            }
            Section {
                Button("Export full backup") {}
                Button("Export as CSV") {}
                Button("Import data") {}
            } header: {
                Text("Database")
            } footer: {
                Text("Coming soon")
            }
            .disabled(true)
            Section("About") {
                LabeledContent("Version", value: version)
                if let url = URL(string: "https://github.com/ROODAY/uhabits") {
                    Link("Source code", destination: url)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil },
                                             set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func toggle(_ title: String, _ keyPath: KeyPath<AppSettings, Bool>,
                        _ setter: @escaping (LoopKit, Bool) throws -> Void) -> some View {
        Toggle(title, isOn: Binding(
            get: { settings?[keyPath: keyPath] ?? false },
            set: { value in write { try setter($0, value) } }))
    }

    private func reload() async {
        do { settings = try await LoopStore.shared.withKit { try $0.settings() } }
        catch { errorMessage = String(describing: error) }
    }

    private func write(_ body: @escaping (LoopKit) throws -> Void) {
        Task {
            do { try await LoopStore.shared.mutate(body) } catch { errorMessage = String(describing: error) }
            await reload()
            onChanged()
        }
    }
}
