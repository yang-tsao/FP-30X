import Foundation
import SwiftUI
import Combine
import RolandMIDI

// MARK: - Defaults & constants

let kSettingTransposeValue = "transpose/value"
let kSettingConnectHelpSkipStartup = "connect_help_skip_startup"
let kSettingPdWarningShown = "pd_warning_shown"

private let defaultPresetIndex = 0
private let midiPartChannel = 4
private let defaultMasterVolume = 100
private let defaultMasterTuningRaw = masterTuningRawFromHz(MASTER_TUNING_REF_HZ)
private let defaultTranspose = 0
private let defaultTempo = 120
private let defaultBrilliance = 0
private let defaultAmbience = 1
private let defaultKeyTouch = 3
private let defaultKeyboardMode = 0
private let defaultBalance = 9
private let defaultTwinMode = 0
private let defaultMetroVolume = 5
private let defaultMetroTone = 0
private let defaultMetroBeat = 3
private let defaultMetroPattern = 0
private let octaveShiftMin = -3
private let octaveShiftMax = 3
private let tempoMin = 10, tempoMax = 500
private let defaultSplitPoint = 54
let invNoteMidiBase = 21
let invNoteCount = 88

let beatTable: [(midiVal: Int, num: Int)] = [
    (0, 0), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6),
]

let metroGridCols = 5

let keyTouchI18nKeys = [
    "key_touch_fix", "key_touch_super_light", "key_touch_light",
    "key_touch_medium", "key_touch_heavy", "key_touch_super_heavy",
]

let temperamentI18nKeys = [
    "pd_temp_equal", "pd_temp_just_major", "pd_temp_just_minor",
    "pd_temp_pythagorean", "pd_temp_kirnberger_1", "pd_temp_kirnberger_2",
    "pd_temp_kirnberger_3", "pd_temp_meantone", "pd_temp_werckmeister", "pd_temp_arabic",
]

let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

let temperamentKeys = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

let metroPatternGlyphs: [String?] = [
    nil, "♫", "♪♪♪₃", "♫₂", "♬", "♬₃", "♩", "♪",
]

func midiNoteName(_ note: Int) -> String {
    return "\(noteNames[note % 12])\(note / 12 - 1)"
}

// MARK: - ControllerModel

@MainActor
final class ControllerModel: ObservableObject {
    // MARK: Connection
    @Published var outputNames: [String] = []
    @Published var inputNames: [String] = []
    @Published var selectedOutput: String = ""
    @Published var isConnected: Bool = false
    @Published var lastOutputPort: String?
    var lastInputPort: String?

    // MARK: Status
    @Published var statusText: String = ""

    // MARK: Flags
    let verbose: Bool
    let debug: Bool
    @Published var pdWarningShown: Bool

    // MARK: Piano Settings
    @Published var masterVolume: Int = defaultMasterVolume
    @Published var masterTuningRaw: Int = defaultMasterTuningRaw
    var masterTuningHzDisplay: String {
        let hz = masterTuningHzFromRaw(masterTuningRaw)
        return String(format: "%.1f Hz", hz)
    }
    @Published var transpose: Int = defaultTranspose
    @Published var transposeKnown: Bool = true
    @Published var brilliance: Int = defaultBrilliance
    @Published var ambience: Int = defaultAmbience
    @Published var keyTouch: Int = defaultKeyTouch
    @Published var keyboardMode: Int = defaultKeyboardMode

    // MARK: Tones
    @Published var singleCategory: Int = 0
    @Published var singleToneIdx: Int = 0
    @Published var splitLeftCategory: Int = 0
    @Published var splitLeftToneIdx: Int = 0
    @Published var splitRightCategory: Int = 0
    @Published var splitRightToneIdx: Int = 0
    @Published var dual1Category: Int = 0
    @Published var dual1ToneIdx: Int = 0
    @Published var dual2Category: Int = 0
    @Published var dual2ToneIdx: Int = 0
    @Published var twinCategory: Int = 0
    @Published var twinToneIdx: Int = 0

    var currentSingleTone: Tone? { toneInCategory(singleCategory, singleToneIdx) }
    var currentSplitLeftTone: Tone? { toneInCategory(splitLeftCategory, splitLeftToneIdx) }
    var currentSplitRightTone: Tone? { toneInCategory(splitRightCategory, splitRightToneIdx) }
    var currentDual1Tone: Tone? { toneInCategory(dual1Category, dual1ToneIdx) }
    var currentDual2Tone: Tone? { toneInCategory(dual2Category, dual2ToneIdx) }
    var currentTwinTone: Tone? { toneInCategory(twinCategory, twinToneIdx) }

    private func toneInCategory(_ cat: Int, _ idx: Int) -> Tone? {
        guard CATEGORIES.indices.contains(cat) else { return nil }
        let tones = toneCategories[CATEGORIES[cat]] ?? []
        return tones.indices.contains(idx) ? tones[idx] : nil
    }

    private func setPickerTone(cat: inout Int, tIdx: inout Int, tone: Tone) {
        let c = categoryOf(tone)
        if let catIdx = CATEGORIES.firstIndex(of: c) {
            cat = catIdx
            let tones = toneCategories[c] ?? []
            if let ti = tones.firstIndex(of: tone) {
                tIdx = ti
            } else { tIdx = 0 }
        }
    }

    func setSingleTone(_ tone: Tone) { setPickerTone(cat: &singleCategory, tIdx: &singleToneIdx, tone: tone) }
    func setSplitLeftTone(_ tone: Tone) { setPickerTone(cat: &splitLeftCategory, tIdx: &splitLeftToneIdx, tone: tone) }
    func setSplitRightTone(_ tone: Tone) { setPickerTone(cat: &splitRightCategory, tIdx: &splitRightToneIdx, tone: tone) }
    func setDual1Tone(_ tone: Tone) { setPickerTone(cat: &dual1Category, tIdx: &dual1ToneIdx, tone: tone) }
    func setDual2Tone(_ tone: Tone) { setPickerTone(cat: &dual2Category, tIdx: &dual2ToneIdx, tone: tone) }
    func setTwinTone(_ tone: Tone) { setPickerTone(cat: &twinCategory, tIdx: &twinToneIdx, tone: tone) }

    @Published var splitBalance: Int = defaultBalance
    @Published var dualBalance: Int = defaultBalance
    @Published var splitPointVal: Int = defaultSplitPoint
    @Published var splitRightShift: Int = 0
    @Published var splitLeftShift: Int = 0
    @Published var dualShift1: Int = 0
    @Published var dualShift2: Int = 0
    @Published var twinMode: Int = defaultTwinMode

    // MARK: Metronome
    @Published var tempo: Int = defaultTempo
    @Published var metroVolume: Int = defaultMetroVolume
    @Published var metroTone: Int = defaultMetroTone
    @Published var metroBeat: Int = defaultMetroBeat
    @Published var metroPattern: Int = defaultMetroPattern
    @Published var metronomeOn: Bool?

    // MARK: Piano Designer
    @Published var pdLid: Int = 4
    @Published var pdStringResonance: Int = 5
    @Published var pdDamperResonance: Int = 5
    @Published var pdKeyOffResonance: Int = 5
    @Published var pdTemperament: Int = 0
    @Published var pdTemperamentKey: Int = 0
    @Published var invNoteIndex: Int = 0
    @Published var invTuning: Int = 0   // -500..500 → tenths of a cent
    @Published var invCharacter: Int = 0

    // MARK: UI helpers
    @Published var showConnectHelp: Bool = false
    @Published var showPdWarning: Bool = false

    var connectHelpSkipStartup: Bool { UserDefaults.standard.bool(forKey: kSettingConnectHelpSkipStartup) }

    // MARK: Internal state
    nonisolated(unsafe) private let midi: MidiOutClient
    nonisolated(unsafe) private var midiInWorker: MidiInWorker?
    nonisolated(unsafe) private var bankParser: BankProgramParser!
    nonisolated(unsafe) private var rpnParser: RpnParser!
    private var ignorePianoPatchUntil: TimeInterval = 0
    private var masterVolSentAt: TimeInterval = 0
    private var suppressSliderMidi = false
    var midiSyncUpdating = false
    private var pianoDesignerActive = false
    private var pianoPollSuppressUntil: TimeInterval = 0

    // MARK: Timers
    nonisolated(unsafe) private var portWatchdogTimer: Timer?
    nonisolated(unsafe) private var pianoPollTimer: Timer?
    private var masterVolDebounceWorkItem: DispatchWorkItem?
    private var tempoDebounceWorkItem: DispatchWorkItem?
    private var toneRefreshWorkItem: DispatchWorkItem?
    private var readPianoValuesTimeout: DispatchWorkItem?

    private var readPianoValuesActive = false
    private var readPianoValuesPending: [UInt32: String] = [:]

    private let sendQueue = DispatchQueue(label: "midi.send", qos: .userInitiated)

    /// Pack a 4-byte Sysex address into a UInt32 dictionary key.
    private func addrKey(_ addr: SysexAddress) -> UInt32 {
        UInt32(addr.0) << 24 | UInt32(addr.1) << 16 | UInt32(addr.2) << 8 | UInt32(addr.3)
    }

    // MARK: Read Piano Value specs (debug)
    static let readPianoValueSpecs: [(id: String, addr: SysexAddress, factory: () -> MidiMessage)] = [
        ("master_volume", (0x01,0x00,0x02,0x13), masterVolumeRead),
        ("sequencer_tempo", (0x01,0x00,0x01,0x08), metronomeReadTempo),
        ("metronome_status", (0x01,0x00,0x01,0x0F), metronomeReadStatus),
        ("key_transpose", (0x01,0x00,0x01,0x01), keyTransposeRead),
        ("brilliance", (0x01,0x00,0x02,0x1C), brillianceRead),
        ("ambience", (0x01,0x00,0x02,0x1A), ambienceRead),
        ("key_touch", (0x01,0x00,0x02,0x1D), keyTouchRead),
        ("keyboard_mode", (0x01,0x00,0x02,0x00), keyboardModeRead),
        ("master_tuning", (0x01,0x00,0x02,0x18), masterTuningRead),
        ("metronome_volume", (0x01,0x00,0x02,0x21), metronomeVolumeRead),
        ("metronome_tone", (0x01,0x00,0x02,0x22), metronomeToneRead),
        ("metronome_beat", (0x01,0x00,0x02,0x1F), metronomeBeatRead),
        ("metronome_pattern", (0x01,0x00,0x02,0x20), metronomePatternRead),
        ("split_point", (0x01,0x00,0x02,0x01), splitPointRead),
        ("split_right_octave_shift", (0x01,0x00,0x02,0x16), splitRightOctaveShiftRead),
        ("split_left_octave_shift", (0x01,0x00,0x02,0x02), splitOctaveShiftRead),
        ("split_balance", (0x01,0x00,0x02,0x03), splitBalanceRead),
        ("dual_tone1_octave_shift", (0x01,0x00,0x02,0x17), dualTone1OctaveShiftRead),
        ("dual_tone2_octave_shift", (0x01,0x00,0x02,0x04), dualOctaveShiftRead),
        ("dual_balance", (0x01,0x00,0x02,0x05), dualBalanceRead),
        ("twin_piano_mode", (0x01,0x00,0x02,0x06), twinPianoModeRead),
        ("tone_single", (0x01,0x00,0x02,0x07), toneForSingleRead),
        ("tone_split_left", (0x01,0x00,0x02,0x0A), toneForSplitRead),
        ("tone_dual_layer", (0x01,0x00,0x02,0x0D), toneForDualRead),
    ]

    // MARK: init

    init(verbose: Bool = false, debug: Bool = false) {
        self.verbose = verbose
        self.debug = debug
        self.pdWarningShown = UserDefaults.standard.bool(forKey: kSettingPdWarningShown)
        self.midi = MidiOutClient(traceSend: nil)
        if verbose {
            self.midi.traceSend = { [weak self] msg in self?.traceMidiOut(msg) }
        }

        // Load saved settings
        let ud = UserDefaults.standard
        if let tv = ud.object(forKey: kSettingTransposeValue) as? Int {
            self.transpose = tv
        }

        self.bankParser = try! BankProgramParser(channels1to16: 1, midiPartChannel)
        self.rpnParser = try! RpnParser(channels1to16: 1, midiPartChannel)
    }

    nonisolated deinit {
        portWatchdogTimer?.invalidate()
        pianoPollTimer?.invalidate()
        midiInWorker?.stop()
        midiInWorker = nil
        midi.close()
    }

    // MARK: - MIDI trace

    func traceMidiOut(_ msg: MidiMessage) {
        let raw = msg.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        FileHandle.standardError.write(Data("MIDI [OUT] \(msg)  |  \(raw)\n".utf8))
    }

    // MARK: - Port enumeration

    func refreshPorts() {
        outputNames = listOutputNames()
        inputNames = listInputNames()
        statusText = locf("status_midi_ports", outputNames.count, inputNames.count)
    }

    // MARK: - Connect / Disconnect

    func toggleConnect() {
        if isConnected {
            disconnectDevice(statusKey: "status_disconnected")
        } else {
            let name = selectedOutput.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                statusText = loc("err_no_port")
                return
            }
            do {
                try midi.open(name)
            } catch {
                statusText = locf("err_open_port", "\(error)")
                return
            }
            lastOutputPort = name
            lastInputPort = nil
            transposeKnown = false
            metronomeOn = nil
            pianoDesignerActive = false
            isConnected = true
            updateConnectButton()
            syncConnectionDependentControls()

            do {
                try midi.send(appConnectHandshake())
            } catch { /* non-fatal */ }

            let inName = inputNames.contains(name) ? name : ""
            if !inName.isEmpty {
                startMidiInWorker(portName: inName)
            }

            if midiInWorker != nil, let _ = lastInputPort {
                statusText = locf("status_connected_sync", name, lastInputPort!)
                requestPianoState()
                pianoPollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.requestPianoState() }
                }
            } else {
                statusText = locf("status_connected", name)
            }
            syncConnectionDependentControls()
            if transpose != 0 { sendTranspose(updateStatus: false) }

            // Port watchdog
            portWatchdogTimer?.invalidate()
            portWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkConnectedPorts() }
            }
        }
    }

    func updateConnectButton() {} // placeholder for view

    func syncConnectionDependentControls() {}

    private func disconnectDevice(statusKey: String, name: String? = nil) {
        portWatchdogTimer?.invalidate(); portWatchdogTimer = nil
        pianoPollTimer?.invalidate(); pianoPollTimer = nil
        toneRefreshWorkItem?.cancel(); toneRefreshWorkItem = nil
        readPianoValuesTimeout?.cancel(); readPianoValuesActive = false
        cancelDebounceTimers()
        stopMidiInWorker()
        midi.close()
        lastOutputPort = nil; lastInputPort = nil
        metronomeOn = nil; pianoDesignerActive = false
        isConnected = false
        updateConnectButton()
        syncConnectionDependentControls()
        if let n = name {
            statusText = locf(statusKey, n)
        } else {
            statusText = loc(statusKey)
        }
    }

    private func checkConnectedPorts() {
        guard isConnected, let out = lastOutputPort else { return }
        let outs = listOutputNames()
        if !outs.contains(out) {
            refreshPorts()
            disconnectDevice(statusKey: "status_device_lost", name: out)
            return
        }
        if let inp = lastInputPort, !listInputNames().contains(inp) {
            stopMidiInWorker()
            lastInputPort = nil
            statusText = locf("status_device_lost", inp)
            refreshPorts()
            syncConnectionDependentControls()
        }
    }

    // MARK: - MIDI input worker

    private func startMidiInWorker(portName: String) {
        stopMidiInWorker()
        let worker = MidiInWorker(portName: portName, queue: .main) { [weak self] msg in
            self?.onMidiInMessage(msg)
        }
        do { try worker.start() } catch {
            midiInWorker = nil
            return
        }
        midiInWorker = worker
        lastInputPort = portName
    }

    private func stopMidiInWorker() {
        midiInWorker?.stop()
        midiInWorker = nil
    }

    // MARK: - MIDI input handling

    private func onMidiInMessage(_ msg: MidiMessage) {
        if verbose {
            let raw = msg.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            FileHandle.standardError.write(Data("MIDI [IN] \(msg)  |  \(raw)\n".utf8))
        }

        if let (addr, data) = parseRolandDt1(msg) {
            if readPianoValuesActive, let pid = readPianoValuesPending[addrKey(addr)] {
                readPianoValuesPending.removeValue(forKey: addrKey(addr))
                printPianoValueTrace(pid, data: data)
                if readPianoValuesPending.isEmpty { finishReadPianoValues() }
            }

            guard Date().timeIntervalSince1970 >= ignorePianoPatchUntil else { return }
            handleDt1(addr: addr, data: data)
            return
        }

        if let semitones = parseMasterCoarseTuningSysex(msg) {
            if transpose != semitones || !transposeKnown {
                setTransposeUI(semitones, known: true, emitStatus: true)
            }
            return
        }

        if let semitones = rpnParser.feedCoarseTuning(msg) {
            if transpose != semitones || !transposeKnown {
                setTransposeUI(semitones, known: true, emitStatus: true)
            }
            return
        }

        guard let (msb, lsb, pdoc) = bankParser.feed(msg) else { return }
        guard toneUsesBankProgram(activePrimaryTone()) else { return }

        for t in TONE_PRESETS {
            if t.bankMsb == msb, t.bankLsb == lsb, t.programDoc == pdoc {
                setSingleTone(t)
                statusText = locf("status_tone_from_piano", t.name)
                return
            }
        }
        statusText = locf("status_piano_tone_unknown", msb, lsb, pdoc)
    }

    // MARK: - DT1 handler (port of `_handle_dt1`)

    private func handleDt1(addr: SysexAddress, data: [Int]) {
        switch addr {
        case (0x01, 0x00, 0x02, 0x13) where !data.isEmpty:
            if Date().timeIntervalSince1970 - masterVolSentAt < 1.5 { return }
            let mv = max(0, min(MASTER_VOLUME_DT1_MAX, data[0]))
            suppressSliderMidi = true
            masterVolume = mv
            suppressSliderMidi = false

        case (0x01, 0x00, 0x01, 0x08) where data.count >= 2:
            let bpm = data[0] * 128 + data[1]
            if (tempoMin...tempoMax).contains(bpm) { setTempoUI(bpm) }

        case (0x01, 0x00, 0x01, 0x0F) where !data.isEmpty:
            metronomeOn = data[0] != 0

        case (0x01, 0x00, 0x02, 0x1C) where !data.isEmpty:
            let display = max(-1, min(1, data[0] - 64))
            suppressSliderMidi = true
            brilliance = display
            suppressSliderMidi = false

        case (0x01, 0x00, 0x02, 0x1A) where !data.isEmpty:
            let val = max(0, min(10, data[0]))
            suppressSliderMidi = true
            ambience = val
            suppressSliderMidi = false

        case (0x01, 0x00, 0x02, 0x1D) where !data.isEmpty:
            keyTouch = max(0, min(5, data[0]))

        case (0x01, 0x00, 0x02, 0x18) where data.count >= 2:
            let raw = data[0] * 128 + data[1]
            suppressSliderMidi = true
            masterTuningRaw = max(MASTER_TUNING_MIN_RAW, min(MASTER_TUNING_MAX_RAW, raw))
            suppressSliderMidi = false

        case (0x01, 0x00, 0x02, 0x00) where !data.isEmpty:
            let mode = max(0, min(3, data[0]))
            if mode != keyboardMode {
                midiSyncUpdating = true
                keyboardMode = mode
                midiSyncUpdating = false
                scheduleToneRefreshFromPiano()
            }

        case (0x01, 0x00, 0x02, 0x01) where !data.isEmpty:
            splitPointVal = max(0, min(127, data[0]))

        case (0x01, 0x00, 0x02, 0x16) where !data.isEmpty:
            splitRightShift = max(octaveShiftMin, min(octaveShiftMax, data[0] - 64))

        case (0x01, 0x00, 0x02, 0x02) where !data.isEmpty:
            splitLeftShift = max(octaveShiftMin, min(octaveShiftMax, data[0] - 64))

        case (0x01, 0x00, 0x02, 0x03) where !data.isEmpty:
            let val = splitBalanceNormalizePanel(splitBalancePanelFromSysexByte(data[0]))
            suppressSliderMidi = true
            splitBalance = val
            suppressSliderMidi = false

        case (0x01, 0x00, 0x02, 0x17) where !data.isEmpty:
            dualShift1 = max(octaveShiftMin, min(octaveShiftMax, data[0] - 64))

        case (0x01, 0x00, 0x02, 0x04) where !data.isEmpty:
            dualShift2 = max(octaveShiftMin, min(octaveShiftMax, data[0] - 64))

        case (0x01, 0x00, 0x02, 0x05) where !data.isEmpty:
            let val = dualBalancePanelFromSysexByte(data[0])
            suppressSliderMidi = true
            dualBalance = val
            suppressSliderMidi = false

        case (0x01, 0x00, 0x02, 0x06) where !data.isEmpty:
            midiSyncUpdating = true
            twinMode = max(0, min(1, data[0]))
            midiSyncUpdating = false

        case (0x01, 0x00, 0x02, 0x07) where data.count >= 3:
            if !toneUsesBankProgram(activePrimaryTone()),
               let t = toneFromDt1Bytes(data[0], data[1], data[2]) {
                setSingleTone(t)
                setSplitRightTone(t)
                setDual1Tone(t)
                setTwinTone(t)
            }

        case (0x01, 0x00, 0x02, 0x0A) where data.count >= 3:
            if !toneUsesBankProgram(currentSplitLeftTone),
               let t = toneFromDt1Bytes(data[0], data[1], data[2]) {
                setSplitLeftTone(t)
            }

        case (0x01, 0x00, 0x02, 0x0D) where data.count >= 3:
            if !toneUsesBankProgram(currentDual2Tone),
               let t = toneFromDt1Bytes(data[0], data[1], data[2]) {
                setDual2Tone(t)
            }

        case (0x01, 0x00, 0x02, 0x21) where !data.isEmpty:
            let val = max(0, min(10, data[0]))
            suppressSliderMidi = true
            metroVolume = val
            suppressSliderMidi = false

        case (0x01, 0x00, 0x02, 0x22) where !data.isEmpty:
            midiSyncUpdating = true
            metroTone = max(0, min(3, data[0]))
            midiSyncUpdating = false

        case (0x01, 0x00, 0x02, 0x20) where !data.isEmpty:
            midiSyncUpdating = true
            metroPattern = max(0, min(7, data[0]))
            midiSyncUpdating = false

        case (0x01, 0x00, 0x02, 0x1F) where !data.isEmpty:
            midiSyncUpdating = true
            metroBeat = data[0]
            midiSyncUpdating = false

        default: break
        }
    }

    // MARK: - Tone helpers

    private func toneUsesBankProgram(_ tone: Tone?) -> Bool {
        guard let t = tone else { return false }
        let cat = categoryOf(t)
        return cat == "GM2" || cat == "Drums"
    }

    private func activePrimaryTone() -> Tone? {
        switch keyboardMode {
        case 1: return currentSplitRightTone
        case 2: return currentDual1Tone
        case 3: return currentTwinTone
        default: return currentSingleTone
        }
    }

    // MARK: - Transpose UI

    func setTransposeUI(_ value: Int, known: Bool, emitStatus: Bool = false) {
        transposeKnown = known
        transpose = value
        if known { UserDefaults.standard.set(value, forKey: kSettingTransposeValue) }
        if emitStatus {
            statusText = known
                ? locf("status_transpose_from_piano", value)
                : loc("status_transpose_unknown")
        }
    }

    // MARK: - Tempo UI

    func setTempoUI(_ bpm: Int) {
        suppressSliderMidi = true
        tempo = bpm
        suppressSliderMidi = false
    }

    // MARK: - Send helpers

    private func userSend(_ factory: @autoclosure () throws -> MidiMessage) {
        guard let msg = try? factory() else { return }
        do {
            try midi.send(msg)
            suppressPianoPoll()
        } catch let e as MidiMessageError {
            handleSendError(e)
        } catch {
            logUnexpectedError("userSend", error)
        }
    }

    private func userSendAll(_ msgs: [MidiMessage], gap: TimeInterval = 0) {
        do {
            try midi.sendAllSpaced(msgs, gapS: gap)
            suppressPianoPoll()
        } catch let e as MidiMessageError {
            handleSendError(e)
        } catch {
            logUnexpectedError("userSendAll", error)
        }
    }

    private func handleSendError(_ error: MidiMessageError) {
        switch error {
        case .osError:
            disconnectDevice(statusKey: "status_device_lost", name: lastOutputPort ?? "?")
        default:
            statusText = error.description
        }
    }

    nonisolated private func logUnexpectedError(_ context: String, _ error: Error) {
        if verbose {
            FileHandle.standardError.write(Data("MIDI [ERR] \(context): \(error)\n".utf8))
        }
    }

    private func suppressPianoPoll() {
        pianoPollSuppressUntil = Date().timeIntervalSince1970 + 2.0
    }

    private func cancelDebounceTimers() {
        masterVolDebounceWorkItem?.cancel()
        tempoDebounceWorkItem?.cancel()
    }

    // MARK: - Piano state poll

    private func requestPianoState() {
        guard isConnected, lastInputPort != nil else { return }
        guard Date().timeIntervalSince1970 >= pianoPollSuppressUntil else { return }

        let msgs: [MidiMessage] = [
            masterVolumeRead(), metronomeReadTempo(), metronomeReadStatus(),
            brillianceRead(), ambienceRead(), keyTouchRead(), keyboardModeRead(),
            masterTuningRead(), metronomeVolumeRead(), metronomeToneRead(),
            metronomeBeatRead(), metronomePatternRead(), splitPointRead(),
            splitRightOctaveShiftRead(), splitOctaveShiftRead(), splitBalanceRead(),
            dualTone1OctaveShiftRead(), dualOctaveShiftRead(), dualBalanceRead(),
            twinPianoModeRead(), toneForSingleRead(), toneForSplitRead(), toneForDualRead(),
        ]
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.midi.sendAllSpaced(msgs, gapS: 0.004)
                Task { @MainActor in self.suppressPianoPoll() }
            } catch {
                Task { @MainActor in self.logUnexpectedError("requestPianoState", error) }
            }
        }
    }

    // MARK: - Tone refresh

    func scheduleToneRefreshFromPiano() {
        guard isConnected, lastInputPort != nil else { return }
        toneRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.requestTonesFromPiano() }
        toneRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.120, execute: work)
    }

    private func requestTonesFromPiano() {
        guard isConnected, lastInputPort != nil else { return }
        let msgs: [MidiMessage] = [
            toneForSingleRead(), toneForSplitRead(), toneForDualRead(),
            splitRightOctaveShiftRead(), splitOctaveShiftRead(),
            dualTone1OctaveShiftRead(), dualOctaveShiftRead(),
        ]
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            do { try self.midi.sendAllSpaced(msgs, gapS: 0.004) } catch {
                Task { @MainActor in self.logUnexpectedError("requestTonesFromPiano", error) }
            }
        }
    }

    // MARK: - Read Piano Values (debug)

    func onReadPianoValuesClicked() {
        guard isConnected, lastInputPort != nil else {
            statusText = loc("err_read_piano_needs_sync")
            return
        }
        guard !readPianoValuesActive else { return }
        let specs = Self.readPianoValueSpecs
        readPianoValuesPending = Dictionary(uniqueKeysWithValues: specs.map { (addrKey($0.addr), $0.id) })
        readPianoValuesActive = true
        readPianoValuesTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.onReadPianoValuesTimeout() }
        readPianoValuesTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: timeout)

        FileHandle.standardError.write(Data("\n=== Read Piano Values ===\n".utf8))

        let msgs = specs.map { $0.factory() }
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.midi.sendAllSpaced(msgs, gapS: 0.05)
            } catch {
                Task { @MainActor in self.logUnexpectedError("onReadPianoValuesClicked", error) }
            }
        }
    }

    private func printPianoValueTrace(_ pid: String, data: [Int]) {
        let summary: String
        switch pid {
        case "master_volume": summary = "master_volume=\(data[0])"
        case "sequencer_tempo" where data.count >= 2:
            summary = "tempo_bpm=\(data[0] * 128 + data[1])"
        case "metronome_status": summary = "metronome_on=\(data[0] != 0)"
        case "key_transpose": summary = "transpose_semitones=\(data[0] - 64)"
        case "brilliance": summary = "brilliance=\(max(-1, min(1, data[0] - 64)))"
        case "ambience": summary = "ambience=\(max(0, min(10, data[0])))"
        case "key_touch": summary = "key_touch=\(max(0, min(5, data[0])))"
        case "keyboard_mode":
            let modes = ["Single", "Split", "Dual", "TwinPiano"]
            summary = "keyboard_mode=\(modes[max(0, min(3, data[0]))])"
        case "master_tuning" where data.count >= 2:
            let raw = data[0] * 128 + data[1]
            let hz = masterTuningHzFromRaw(raw)
            summary = "master_tuning_cents=\(String(format:"%.2f",masterTuningCentsFromRaw(raw))) ref_hz=\(String(format:"%.1f",hz))"
        default:
            summary = "raw=" + data.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
        FileHandle.standardError.write(Data("MIDI [VALUES] \(pid): \(summary)\n".utf8))
    }

    private func finishReadPianoValues() {
        readPianoValuesTimeout?.cancel()
        readPianoValuesActive = false
        readPianoValuesPending.removeAll()
        FileHandle.standardError.write(Data("=== End Read Piano Values ===\n\n".utf8))
    }

    private func onReadPianoValuesTimeout() {
        guard readPianoValuesActive else { return }
        for (_, pid) in readPianoValuesPending {
            FileHandle.standardError.write(Data("MIDI [VALUES] \(pid): (no response in time)\n".utf8))
        }
        readPianoValuesPending.removeAll()
        readPianoValuesActive = false
        FileHandle.standardError.write(Data("=== End Read Piano Values (timeout) ===\n\n".utf8))
    }

    // MARK: - Reset defaults

    func resetDefaults() {
        cancelDebounceTimers()
        suppressSliderMidi = true
        defer { suppressSliderMidi = false }

        masterVolume = defaultMasterVolume
        setTransposeUI(defaultTranspose, known: true)
        setTempoUI(defaultTempo)
        masterTuningRaw = defaultMasterTuningRaw
        brilliance = defaultBrilliance
        ambience = defaultAmbience
        keyTouch = defaultKeyTouch
        metroVolume = defaultMetroVolume
        metronomeOn = false
        metroTone = defaultMetroTone
        metroPattern = defaultMetroPattern
        metroBeat = defaultMetroBeat
        splitBalance = defaultBalance
        dualBalance = defaultBalance
        splitPointVal = defaultSplitPoint
        splitRightShift = 0; splitLeftShift = 0
        dualShift1 = 0; dualShift2 = 0
        twinMode = defaultTwinMode
        pdLid = 4
        pdStringResonance = 5; pdDamperResonance = 5; pdKeyOffResonance = 5
        pdTemperament = 0; pdTemperamentKey = 0
        invNoteIndex = 0; invTuning = 0; invCharacter = 0

        guard isConnected else {
            statusText = loc("status_defaults_offline")
            return
        }

        sendMasterVolume()
        sendMasterTuning()
        sendTranspose(updateStatus: false)
        flushTempo()
        sendBrilliance()
        sendAmbience()
        sendKeyTouch()
        userSend(metronomeSet(on: false))
        userSend(safeMetronomeVolumeSet(0))
        userSend(safeMetronomeToneSet(0))
        userSend(metronomeBeatSet(defaultMetroBeat))
        userSend(safeMetronomePatternSet(0))
        userSend(splitBalanceSet(defaultBalance))
        userSendAll(splitBalanceControlChanges(defaultBalance), gap: DEFAULT_MESSAGE_GAP_S)
        userSend(safeSplitRightOctaveShift(0))
        userSend(safeSplitOctaveShift(0))
        userSend(dualBalanceSet(defaultBalance))
        userSendAll(dualBalanceControlChanges(defaultBalance), gap: DEFAULT_MESSAGE_GAP_S)
        userSend(safeDualTone1OctaveShift(0))
        userSend(safeDualOctaveShift(0))
        if ensurePianoDesignerActive() {
            userSend(pianoDesignerLidSet(4))
            userSend(pianoDesignerStringResonanceSet(5))
            userSend(pianoDesignerDamperResonanceSet(5))
            userSend(pianoDesignerKeyOffResonanceSet(5))
            userSend(pianoDesignerTemperamentSet(0))
            userSend(pianoDesignerTemperamentKeySet(0))
        }
        statusText = loc("status_defaults_sent")
    }

    // Helper: catch throws for known-safe ranges, return identity-ish
    private func trySafe<T>(_ f: @autoclosure () throws -> T, fallback: T) -> T {
        (try? f()) ?? fallback
    }

    func safeMetronomeVolumeSet(_ v: Int) -> MidiMessage { try! metronomeVolumeSet(v) }
    func safeMetronomeToneSet(_ v: Int) -> MidiMessage { try! metronomeToneSet(v) }
    func safeMetronomePatternSet(_ v: Int) -> MidiMessage { try! metronomePatternSet(v) }
    func safeSplitRightOctaveShift(_ v: Int) -> MidiMessage { try! splitRightOctaveShiftSet(v) }
    func safeSplitOctaveShift(_ v: Int) -> MidiMessage { try! splitOctaveShiftSet(v) }
    func safeDualTone1OctaveShift(_ v: Int) -> MidiMessage { try! dualTone1OctaveShiftSet(v) }
    func safeDualOctaveShift(_ v: Int) -> MidiMessage { try! dualOctaveShiftSet(v) }

    // MARK: - Piano Designer

    func ensurePianoDesignerActive() -> Bool {
        guard isConnected else { return false }
        if pianoDesignerActive { return true }
        userSend(pianoDesignerEnter())
        pianoDesignerActive = true
        return true
    }

    func pdSendLid(_ v: Int) { guard ensurePianoDesignerActive() else { return }; userSend(pianoDesignerLidSet(v)) }
    func pdSendStringRes(_ v: Int) { guard ensurePianoDesignerActive() else { return }; userSend(pianoDesignerStringResonanceSet(v)) }
    func pdSendDamperRes(_ v: Int) { guard ensurePianoDesignerActive() else { return }; userSend(pianoDesignerDamperResonanceSet(v)) }
    func pdSendKeyOff(_ v: Int) { guard ensurePianoDesignerActive() else { return }; userSend(pianoDesignerKeyOffResonanceSet(v)) }
    func pdSendTemperament(_ idx: Int) { guard ensurePianoDesignerActive() else { return }; userSend(pianoDesignerTemperamentSet(idx)) }
    func pdSendTemperamentKey(_ idx: Int) { guard ensurePianoDesignerActive() else { return }; userSend(pianoDesignerTemperamentKeySet(idx)) }

    func pdSaveToPiano() {
        guard ensurePianoDesignerActive() else { statusText = loc("msg_connect_before_send"); return }
        userSend(pianoDesignerWrite())
        statusText = loc("status_pd_saved")
    }

    // MARK: - Individual note voicing

    func flushInvTuning() {
        guard isConnected, !suppressSliderMidi else { return }
        let noteIdx = invNoteIndex
        guard (0..<invNoteCount).contains(noteIdx) else { return }
        let centsX10 = invTuning
        userSend(pianoDesignerIndividualNoteTuningSet(note0to87: noteIdx, centsX10: centsX10))
    }

    func onInvCharacterChanged(_ value: Int) {
        guard !suppressSliderMidi else { return }
        guard isConnected else { return }
        let noteIdx = invNoteIndex
        guard (0..<invNoteCount).contains(noteIdx) else { return }
        userSend(pianoDesignerIndividualNoteCharacterSet(note0to87: noteIdx, value: value))
    }

    // MARK: - Send methods for Piano Settings

    func scheduleMasterVolumeDebounced() {
        guard !suppressSliderMidi else { return }
        masterVolDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendMasterVolume() }
        masterVolDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.055, execute: work)
    }

    func sendMasterVolume() {
        guard isConnected else { return }
        masterVolDebounceWorkItem?.cancel()
        userSend(try masterVolumeSet(value: masterVolume))
        masterVolSentAt = Date().timeIntervalSince1970
        statusText = locf("status_master_volume_sent", masterVolume)
    }

    func sendTranspose(updateStatus: Bool = true) {
        guard isConnected else { return }
        UserDefaults.standard.set(transpose, forKey: kSettingTransposeValue)
        userSend(try masterCoarseTuningRealtime(semitones: transpose))
        if updateStatus { statusText = locf("status_transpose_sent", transpose) }
    }

    func sendMasterTuning() {
        guard isConnected else { return }
        if lastInputPort != nil {
            userSendAll([masterTuningSetRaw(masterTuningRaw), masterTuningRead()], gap: 0.05)
        } else {
            userSend(masterTuningSetRaw(masterTuningRaw))
        }
    }

    func sendBrilliance() {
        guard isConnected else { return }
        userSend(try brillianceSet(brilliance))
    }

    func sendAmbience() {
        guard isConnected else { return }
        userSend(try ambienceSet(ambience))
    }

    func sendKeyTouch() {
        guard isConnected else { return }
        userSend(try keyTouchSet(keyTouch))
    }

    // MARK: - Metronome sends

    func sendMetronomeProbe() {
        guard isConnected else { statusText = loc("msg_connect_before_send"); return }
        userSend(metronomeToggle())
        metronomeOn = metronomeOn.map { !$0 } ?? true
        statusText = loc("status_metronome_probe_sent")
    }

    func flushTempo() {
        guard isConnected, !suppressSliderMidi else { return }
        userSend(try metronomeSetTempo(bpm: tempo))
    }

    func sendMetroVolume(_ v: Int) { guard !suppressSliderMidi, isConnected else { return }; userSend(try metronomeVolumeSet(v)) }
    func sendMetroTone(_ idx: Int) { guard !midiSyncUpdating, isConnected else { return }; userSend(try metronomeToneSet(idx)) }
    func sendMetroBeat(_ v: Int) { guard !midiSyncUpdating, isConnected else { return }; userSend(metronomeBeatSet(v)) }
    func sendMetroPattern(_ v: Int) { guard !midiSyncUpdating, isConnected else { return }; userSend(try metronomePatternSet(v)) }

    // MARK: - Tone mode/selection sends

    func sendKeyboardMode(_ mode: Int) {
        guard !midiSyncUpdating, isConnected else { return }
        userSend(try keyboardModeSet(mode: mode))
        scheduleToneRefreshFromPiano()
    }

    func sendToneSingle(_ tone: Tone) {
        guard isConnected else { return }
        if toneUsesBankProgram(tone) { sendToneBankProgram(tone); return }
        let enc = toneDt1Encoding(tone)
        let num = enc.numHi * 128 + enc.numLo
        userSend(toneForSingleSet(categoryIdx: enc.categoryIdx, num: num))
    }

    func sendToneSplitLeft(_ tone: Tone) {
        guard !midiSyncUpdating, isConnected else { return }
        let enc = toneDt1Encoding(tone)
        userSend(toneForSplitSet(categoryIdx: enc.categoryIdx, num: enc.numHi * 128 + enc.numLo))
    }

    func sendToneDualLayer(_ tone: Tone) {
        guard !midiSyncUpdating, isConnected else { return }
        let enc = toneDt1Encoding(tone)
        userSend(toneForDualSet(categoryIdx: enc.categoryIdx, num: enc.numHi * 128 + enc.numLo))
    }

    private func sendToneBankProgram(_ tone: Tone) {
        guard isConnected else { return }
        ignorePianoPatchUntil = Date().timeIntervalSince1970 + 0.55
        let progMidi = tone.programMidi

        sendQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let parts = try bankSelectProgramAndLatchParts(
                    channel1to16: midiPartChannel,
                    bankMsb: tone.bankMsb, bankLsb: tone.bankLsb,
                    program0to127: progMidi, latchAfterProgram: true)
                try self.midi.sendAllSpaced(parts.core, gapS: DEFAULT_MESSAGE_GAP_S)
                if !parts.latch.isEmpty {
                    Thread.sleep(forTimeInterval: POST_PROGRAM_CHANGE_LATCH_DELAY_S)
                    try self.midi.sendAllSpaced(parts.latch, gapS: 0)
                }
                Task { @MainActor in self.suppressPianoPoll() }
            } catch {
                Task { @MainActor in self.logUnexpectedError("sendToneBankProgram", error) }
            }
        }
    }

    func sendSplitBalance(_ value: Int) {
        guard isConnected else { return }
        userSend(splitBalanceSet(value))
        userSendAll(splitBalanceControlChanges(value), gap: DEFAULT_MESSAGE_GAP_S)
    }

    func sendDualBalance(_ value: Int) {
        guard isConnected else { return }
        userSend(dualBalanceSet(value))
        userSendAll(dualBalanceControlChanges(value), gap: DEFAULT_MESSAGE_GAP_S)
    }

    func sendSplitPoint() {
        guard isConnected else { return }
        userSend(try splitPointSet(noteMidi: splitPointVal))
    }

    func sendSplitRightShift(_ v: Int) { guard isConnected else { return }; userSend(try splitRightOctaveShiftSet(v)) }
    func sendSplitLeftShift(_ v: Int) { guard isConnected else { return }; userSend(try splitOctaveShiftSet(v)) }
    func sendDualShift1(_ v: Int) { guard isConnected else { return }; userSend(try dualTone1OctaveShiftSet(v)) }
    func sendDualShift2(_ v: Int) { guard isConnected else { return }; userSend(try dualOctaveShiftSet(v)) }
    func sendTwinMode(_ mode: Int) { guard !midiSyncUpdating, isConnected else { return }; userSend(twinPianoModeSet(mode)) }

    // MARK: - Split point stepper

    func decSplitPoint() { if splitPointVal > 0 { splitPointVal -= 1; sendSplitPoint() } }
    func incSplitPoint() { if splitPointVal < 127 { splitPointVal += 1; sendSplitPoint() } }

    // MARK: - Connect help

    func markConnectHelpShown() {
        UserDefaults.standard.set(true, forKey: kSettingConnectHelpSkipStartup)
    }

    func setPdWarningShown() {
        pdWarningShown = true
        UserDefaults.standard.set(true, forKey: kSettingPdWarningShown)
    }
}
