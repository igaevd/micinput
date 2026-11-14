import SwiftUI

/// The one and only window: master switch, a microphone per output device, fallback, login item and quit.
struct SettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.config.enabled) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Override microphone")
                                .font(.headline)
                            Text("Current microphone: \(store.currentInput?.name ?? "none")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ForEach(rows) { row in
                    MicPicker(selection: micBinding(for: row.ref), inputs: store.inputs) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                row.subtitle
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: row.ref.symbol(mic: false))
                                .foregroundStyle(row.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .frame(width: 26)
                        }
                        .opacity(dimming)
                    }
                }
            } header: {
                HStack {
                    Text("When sound plays through")
                    Spacer()
                    Text("Use microphone")
                }
                .opacity(dimming)
            }
            .disabled(!store.config.enabled)

            Section {
                MicPicker(selection: $store.config.fallback, inputs: store.inputs) {
                    Text("If that microphone isn’t connected")
                        .opacity(dimming)
                }
            }
            .disabled(!store.config.enabled)

            Section {
                Toggle("Open at login", isOn: $store.opensAtLogin)
                LabeledContent {
                    Button("Quit Completely") { NSApp.terminate(nil) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Runs in the background")
                        Text("Closing this window doesn’t stop it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: store.config.enabled)
    }

    /// With the master switch off the rules do nothing, so they are disabled and fade back.
    /// (Disabling alone only greys the menus, not the labels beside them.)
    private var dimming: Double { store.config.enabled ? 1 : 0.4 }

    /// Connected outputs, followed by outputs that have a rule but aren't connected right now.
    private var rows: [OutputRow] {
        let outputs = store.outputs
        let labels = outputs.labels
        let connected = outputs.map {
            OutputRow(ref: DeviceRef($0), title: labels[$0.uid] ?? $0.name, kind: $0.kind,
                      isCurrent: $0.id == store.outputID)
        }
        let away = store.config.rules.map(\.output)
            .filter { ref in !outputs.contains { $0.uid == ref.uid } }
            .map { OutputRow(ref: $0, title: $0.name, kind: nil, isCurrent: false) }
        return connected + away
    }

    private func micBinding(for output: DeviceRef) -> Binding<DeviceRef?> {
        Binding { store.mic(for: output) } set: { store.setMic($0, for: output) }
    }
}

private struct OutputRow: Identifiable {
    let ref: DeviceRef
    let title: String
    /// Connection type, or `nil` when the device isn't connected.
    let kind: String?
    let isCurrent: Bool

    var id: String { ref.uid }

    var subtitle: Text {
        guard let kind else { return Text("Not connected") }
        return isCurrent ? Text("\(kind) · \(Text("Playing now").foregroundStyle(.tint))") : Text(kind)
    }
}

/// A pop-up menu of the connected microphones, plus "Don't override".
private struct MicPicker<Title: View>: View {
    @Binding var selection: DeviceRef?
    let inputs: [AudioDevice]
    @ViewBuilder var title: Title

    var body: some View {
        let labels = inputs.labels
        Picker(selection: uid) {
            Text("Don’t override").tag(String?.none)
            Divider()
            ForEach(inputs) { mic in
                Label(labels[mic.uid] ?? mic.name, systemImage: DeviceRef(mic).symbol(mic: true))
                    .tag(String?.some(mic.uid))
            }
            // Keep a chosen microphone selectable while it is away (say, the dock's mic when undocked).
            if let selection, !inputs.contains(where: { $0.uid == selection.uid }) {
                Divider()
                Text("\(selection.name) (not connected)").tag(String?.some(selection.uid))
            }
        } label: {
            title
        }
    }

    private var uid: Binding<String?> {
        Binding { selection?.uid } set: { uid in
            if uid == nil {
                selection = nil
            } else if let mic = inputs.first(where: { $0.uid == uid }) {
                selection = DeviceRef(mic)
            }
            // Otherwise it is the "(not connected)" entry, or a microphone that vanished mid-click:
            // keep what was chosen rather than silently dropping the rule.
        }
    }
}
