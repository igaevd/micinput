import CoreAudio
import Foundation
import ServiceManagement
import os

/// A device remembered by its UID. Name and transport are kept so it can still be shown while disconnected.
struct DeviceRef: Codable, Hashable {
    var uid: String
    var name: String
    var transport: UInt32

    init(_ device: AudioDevice) {
        uid = device.uid
        name = device.name
        transport = device.transport
    }

    /// SF Symbol for the device: by product family first, by connection type second.
    func symbol(mic: Bool) -> String {
        let families = [("airpods max", "airpods.max"), ("airpods pro", "airpods.pro"), ("airpods", "airpods"),
                        ("beats", "beats.headphones"), ("iphone", "iphone"), ("ipad", "ipad"),
                        ("macbook", "laptopcomputer"), ("display", "display")]
        let name = name.lowercased()
        if let family = families.first(where: { name.contains($0.0) }) { return family.1 }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "desktopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        default: return mic ? "mic" : "hifispeaker"
        }
    }
}

/// "While sound plays through `output`, use `mic`."
struct Rule: Codable, Hashable {
    var output: DeviceRef
    var mic: DeviceRef
}

struct Config: Codable, Equatable {
    /// The master switch. Off means micinput watches but never touches the microphone.
    var enabled = false
    var rules: [Rule] = []
    /// Used when a rule's microphone isn't connected. `nil`, the default, leaves the microphone alone.
    var fallback: DeviceRef?

    /// The microphone the rules ask for right now, or `nil` to leave the microphone alone.
    ///
    /// This is the whole decision, and it only ever returns a microphone that was picked by hand and is
    /// connected: the rule's microphone, else the fallback, else nothing. No switch, no rule for this
    /// output, or nothing suitable connected all mean "do nothing".
    func microphone(whilePlayingThrough output: AudioDevice, connected inputs: [AudioDevice]) -> AudioDevice? {
        guard enabled, let rule = rules.first(where: { $0.output.uid == output.uid }) else { return nil }
        return inputs.first { $0.uid == rule.mic.uid } ?? inputs.first { $0.uid == fallback?.uid }
    }
}

/// One microphone switch made by micinput, as reported in the pop-up.
struct Override {
    let output: AudioDevice
    let from: AudioDevice?
    let to: AudioDevice
}

/// Settings, the live device list, and the rule engine that keeps the microphone in line.
@MainActor
final class Store: ObservableObject {
    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: Key.config) }
            // Act on what is connected this instant, not on what was connected a moment ago.
            refresh()
        }
    }
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var inputID: AudioDeviceID = 0
    @Published private(set) var outputID: AudioDeviceID = 0

    var onOverride: (Override) -> Void = { _ in }

    var inputs: [AudioDevice] { devices.filter(\.isInput) }
    var outputs: [AudioDevice] { devices.filter(\.isOutput) }
    var currentInput: AudioDevice? { devices.first { $0.id == inputID } }

    private enum Key {
        static let config = "config"
        static let loginItemAdded = "loginItemAdded"
    }

    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "micinput", category: "engine")
    private var pendingRefresh: Task<Void, Never>?
    private var recentSwitches: [Date] = []

    init() {
        let saved = defaults.data(forKey: Key.config).flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
        config = saved ?? Config()
    }

    /// Reads the current devices, applies first-run defaults and starts watching for changes.
    func start() {
        refresh()
        if !defaults.bool(forKey: Key.loginItemAdded), Bundle.main.bundlePath.contains("/Applications/") {
            // First launch from Applications: join the login items so the rules are always in force.
            defaults.set(true, forKey: Key.loginItemAdded)
            opensAtLogin = true
        }
        Audio.observe { [weak self] in self?.scheduleRefresh() }
    }

    /// Re-reads devices and defaults from Core Audio, then enforces the rules.
    func refresh() {
        let devices = Audio.devices().sorted {
            // Built-in first, then by name, like System Settings. The UID tiebreak keeps twins in a stable order.
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.uid < $1.uid : order == .orderedAscending
        }
        if devices != self.devices { self.devices = devices }
        let (input, output) = (Audio.defaultInput, Audio.defaultOutput)
        if input != inputID { inputID = input }
        if output != outputID { outputID = output }
        enforce()
    }

    // MARK: - Rules

    func mic(for output: DeviceRef) -> DeviceRef? {
        config.rules.first { $0.output.uid == output.uid }?.mic
    }

    /// Sets the microphone for an output. `nil` removes the rule.
    func setMic(_ mic: DeviceRef?, for output: DeviceRef) {
        var rules = config.rules.filter { $0.output.uid != output.uid }
        if let mic { rules.append(Rule(output: output, mic: mic)) }
        config.rules = rules.sorted { $0.output.name.localizedStandardCompare($1.output.name) == .orderedAscending }
    }

    /// Switches the system microphone if the rule for the current output asks for a different one.
    private func enforce() {
        guard let output = outputs.first(where: { $0.id == outputID }),
              let target = config.microphone(whilePlayingThrough: output, connected: inputs),
              target.id != inputID else { return }

        // If something keeps switching the microphone back, stand down instead of fighting over it.
        let now = Date()
        recentSwitches.removeAll { now.timeIntervalSince($0) > 10 }
        guard recentSwitches.count < 4 else {
            log.warning("Too many switches in 10 s; leaving the microphone alone for now")
            return
        }
        guard Audio.setDefaultInput(target.id) else {
            log.error("Could not switch the microphone to \(target.name, privacy: .public)")
            return
        }
        recentSwitches.append(now)
        let previous = currentInput
        inputID = target.id
        log.info("\(output.name, privacy: .public): microphone → \(target.name, privacy: .public)")
        onOverride(Override(output: output, from: previous, to: target))
    }

    /// Connecting a headset fires several Core Audio notifications in a row; act once things settle.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Login item

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            }
            // Turned off by hand in System Settings earlier: only the user can turn it back on there.
            if newValue, SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}

extension [AudioDevice] {
    /// Display names by UID. Identical names (say, two Studio Displays) are numbered to tell them apart.
    var labels: [String: String] {
        var seen: [String: Int] = [:]
        return reduce(into: [:]) { labels, device in
            let count = seen[device.name, default: 0] + 1
            seen[device.name] = count
            labels[device.uid] = count == 1 ? device.name : "\(device.name) (\(count))"
        }
    }
}
