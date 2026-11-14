import Testing
@testable import micinput

/// The safe path: micinput only ever picks a microphone that was chosen by hand and is connected right now.
/// Every other situation must come out as `nil`, meaning "leave the microphone alone".
struct RulesTests {
    let airpods = AudioDevice.fake("AirPods", output: true)
    let speakers = AudioDevice.fake("MacBook Pro Speakers", output: true)
    let jabra = AudioDevice.fake("Jabra")
    let display = AudioDevice.fake("Studio Display Microphone")
    let builtIn = AudioDevice.fake("MacBook Pro Microphone")
    let airpodsMic = AudioDevice.fake("AirPods Microphone")

    /// One rule, AirPods → Jabra, with an optional fallback.
    func config(enabled: Bool = true, fallback: AudioDevice? = nil) -> Config {
        Config(enabled: enabled,
               rules: [Rule(output: DeviceRef(airpods), mic: DeviceRef(jabra))],
               fallback: fallback.map { DeviceRef($0) })
    }

    @Test func freshInstallDoesNothing() {
        let fresh = Config()
        #expect(fresh.fallback == nil)
        #expect(fresh.microphone(whilePlayingThrough: airpods, connected: [jabra, builtIn, airpodsMic]) == nil)
    }

    @Test func switchedOffDoesNothing() {
        let off = config(enabled: false, fallback: builtIn)
        #expect(off.microphone(whilePlayingThrough: airpods, connected: [jabra, builtIn]) == nil)
    }

    @Test func outputWithoutRuleIsLeftAlone() {
        // Not even the fallback applies: it only stands in for a rule's missing microphone.
        let rules = config(fallback: builtIn)
        #expect(rules.microphone(whilePlayingThrough: speakers, connected: [jabra, builtIn]) == nil)
    }

    @Test func ruleMicrophoneIsUsedWhenConnected() {
        #expect(config().microphone(whilePlayingThrough: airpods, connected: [airpodsMic, jabra, builtIn]) == jabra)
    }

    @Test func ruleMicrophoneWinsOverFallback() {
        let rules = config(fallback: display)
        #expect(rules.microphone(whilePlayingThrough: airpods, connected: [display, jabra]) == jabra)
    }

    @Test func missingMicrophoneWithoutFallbackDoesNothing() {
        // Undocked: the Jabra is gone and nothing else was chosen, so macOS keeps whatever it picked.
        #expect(config().microphone(whilePlayingThrough: airpods, connected: [airpodsMic, builtIn]) == nil)
    }

    @Test func missingMicrophoneUsesFallbackWhenConnected() {
        let rules = config(fallback: display)
        #expect(rules.microphone(whilePlayingThrough: airpods, connected: [airpodsMic, display, builtIn]) == display)
    }

    @Test func missingMicrophoneAndMissingFallbackDoesNothing() {
        let rules = config(fallback: display)
        #expect(rules.microphone(whilePlayingThrough: airpods, connected: [airpodsMic, builtIn]) == nil)
        #expect(rules.microphone(whilePlayingThrough: airpods, connected: []) == nil)
    }
}

private extension AudioDevice {
    static func fake(_ name: String, output: Bool = false) -> AudioDevice {
        AudioDevice(id: UInt32(truncatingIfNeeded: name.hashValue), uid: name, name: name,
                    transport: 0, isInput: !output, isOutput: output)
    }
}
