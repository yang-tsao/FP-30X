import Foundation

// MARK: - Roland SysEx constants

public let ROLAND_ID: UInt8 = 0x41
public let ROLAND_DEVICE_ID: UInt8 = 0x10
public let FP30X_MODEL_ID: (UInt8, UInt8, UInt8, UInt8) = (0x00, 0x00, 0x00, 0x28)
public let ROLAND_CMD_RQ1: UInt8 = 0x11
public let ROLAND_CMD_DT1: UInt8 = 0x12

public typealias SysexAddress = (UInt8, UInt8, UInt8, UInt8)

// Brief pause between messages: avoids the FP-30X grouping CC0/CC32/PC badly
// in some drivers.
public let DEFAULT_MESSAGE_GAP_S: TimeInterval = 0.02

// Dual: the manual says CC7 adjusts per-Part volume. The main keyboard uses
// channel 4; the second Dual layer follows another MIDI part on compact Rolands.
public let MIDI_DUAL_MAIN_VOLUME_CH = 4
public let MIDI_DUAL_LAYER_VOLUME_CH = 2
public let MIDI_SPLIT_RIGHT_VOLUME_CH = MIDI_DUAL_MAIN_VOLUME_CH
public let MIDI_SPLIT_LEFT_VOLUME_CH = MIDI_DUAL_LAYER_VOLUME_CH
// Extra delay after Program Change before the latch Note On.
public let POST_PROGRAM_CHANGE_LATCH_DELAY_S: TimeInterval = 0.08

// Dual balance panel scale (9 = center). The UI uses the same 0...18 axis as Split.
public let DUAL_BALANCE_PANEL_MIN = 0
public let DUAL_BALANCE_PANEL_MAX = 18

// MARK: - Channel helpers

@inlinable
public func channelZero(_ channel1to16: Int) throws -> Int {
    guard (1...16).contains(channel1to16) else {
        throw MidiMessageError.valueError("MIDI channel must be between 1 and 16")
    }
    return channel1to16 - 1
}

// MARK: - Bank / Program Change

public func bankSelectAndProgramChange(
    channel1to16: Int, bankMsb: Int, bankLsb: Int, program0to127: Int
) throws -> [MidiMessage] {
    let ch = try channelZero(channel1to16)
    guard (0...127).contains(bankMsb), (0...127).contains(bankLsb) else {
        throw MidiMessageError.valueError("Bank MSB/LSB must be between 0 and 127")
    }
    guard (0...127).contains(program0to127) else {
        throw MidiMessageError.valueError("Program change must be between 0 and 127")
    }
    return [
        .controlChange(channel: ch, control: 0, value: bankMsb),
        .controlChange(channel: ch, control: 32, value: bankLsb),
        .programChange(channel: ch, program: program0to127),
    ]
}

/// Tuple of (core CC0/CC32/PC, latch Note On/Off).
public func bankSelectProgramAndLatchParts(
    channel1to16: Int, bankMsb: Int, bankLsb: Int, program0to127: Int,
    latchAfterProgram: Bool = true, latchNote: Int = 60, latchVelocity: Int = 1
) throws -> (core: [MidiMessage], latch: [MidiMessage]) {
    guard (0...127).contains(latchNote), (1...127).contains(latchVelocity) else {
        throw MidiMessageError.valueError("Latch note out of range")
    }
    let core = try bankSelectAndProgramChange(
        channel1to16: channel1to16, bankMsb: bankMsb, bankLsb: bankLsb, program0to127: program0to127
    )
    guard latchAfterProgram else { return (core, []) }
    let ch = try channelZero(channel1to16)
    let latch: [MidiMessage] = [
        .noteOn(channel: ch, note: latchNote, velocity: latchVelocity),
        .noteOff(channel: ch, note: latchNote, velocity: 0),
    ]
    return (core, latch)
}

public func bankSelectProgramSequence(
    channel1to16: Int, bankMsb: Int, bankLsb: Int, program0to127: Int,
    latchAfterProgram: Bool = true, latchNote: Int = 60, latchVelocity: Int = 1
) throws -> [MidiMessage] {
    let parts = try bankSelectProgramAndLatchParts(
        channel1to16: channel1to16, bankMsb: bankMsb, bankLsb: bankLsb, program0to127: program0to127,
        latchAfterProgram: latchAfterProgram, latchNote: latchNote, latchVelocity: latchVelocity
    )
    return parts.core + parts.latch
}

// MARK: - Control change / RPN

public func controlChange(channel1to16: Int, control: Int, value: Int) throws -> MidiMessage {
    let ch = try channelZero(channel1to16)
    guard (0...127).contains(control), (0...127).contains(value) else {
        throw MidiMessageError.valueError("Control and value must be between 0 and 127")
    }
    return .controlChange(channel: ch, control: control, value: value)
}

/// RPN 0,2 (Coarse Tuning): 64 = 0 semitones, followed by Null RPN.
public func rpnCoarseTuning(channel1to16: Int, semitones: Int) throws -> [MidiMessage] {
    guard (-64...63).contains(semitones) else {
        throw MidiMessageError.valueError("Transpose must be between -64 and 63 semitones")
    }
    let value = semitones + 64
    return [
        try controlChange(channel1to16: channel1to16, control: 101, value: 0),
        try controlChange(channel1to16: channel1to16, control: 100, value: 2),
        try controlChange(channel1to16: channel1to16, control: 6, value: value),
        try controlChange(channel1to16: channel1to16, control: 38, value: 0),
        try controlChange(channel1to16: channel1to16, control: 101, value: 127),
        try controlChange(channel1to16: channel1to16, control: 100, value: 127),
    ]
}

/// Universal Realtime SysEx Master Coarse Tuning. mm = 0x40 + semitones (-24..+24).
public func masterCoarseTuningRealtime(semitones: Int) throws -> MidiMessage {
    guard (-24...24).contains(semitones) else {
        throw MidiMessageError.valueError("Transpose must be between -24 and 24 semitones")
    }
    return .sysex(data: [0x7F, 0x7F, 0x04, 0x04, 0x00, UInt8(semitones + 0x40)])
}

// MARK: - Roland checksum / DT1 / RQ1

public func rolandChecksum(_ values: [Int]) -> Int {
    (128 - (values.reduce(0, +) % 128)) % 128
}

public func rolandDataRequest1(address: SysexAddress, size: SysexAddress) -> MidiMessage {
    let payload: [Int] = [Int(address.0), Int(address.1), Int(address.2), Int(address.3),
                          Int(size.0), Int(size.1), Int(size.2), Int(size.3)]
    let chk = rolandChecksum(payload)
    var data: [UInt8] = [ROLAND_ID, ROLAND_DEVICE_ID,
                         FP30X_MODEL_ID.0, FP30X_MODEL_ID.1, FP30X_MODEL_ID.2, FP30X_MODEL_ID.3,
                         ROLAND_CMD_RQ1]
    data.append(contentsOf: payload.map { UInt8($0 & 0x7F) })
    data.append(UInt8(chk & 0x7F))
    return .sysex(data: data)
}

public func rolandDataSet1(address: SysexAddress, data: [Int]) -> MidiMessage {
    let payload: [Int] = [Int(address.0), Int(address.1), Int(address.2), Int(address.3)] + data
    let chk = rolandChecksum(payload)
    var bytes: [UInt8] = [ROLAND_ID, ROLAND_DEVICE_ID,
                          FP30X_MODEL_ID.0, FP30X_MODEL_ID.1, FP30X_MODEL_ID.2, FP30X_MODEL_ID.3,
                          ROLAND_CMD_DT1]
    bytes.append(contentsOf: payload.map { UInt8($0 & 0x7F) })
    bytes.append(UInt8(chk & 0x7F))
    return .sysex(data: bytes)
}

// MARK: - App handshake / metronome (reverse-engineered from Roland Piano App 1.5.9)

public func appConnectHandshake() -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x03, 0x06), data: [0x01])
}

public func metronomeToggle() -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x05, 0x09), data: [0x00])
}

public func metronomeSet(on: Bool) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x03, 0x1A), data: [on ? 0x01 : 0x00])
}

public func metronomeSetTempo(bpm: Int) throws -> MidiMessage {
    guard (10...500).contains(bpm) else {
        throw MidiMessageError.valueError("Tempo must be between 10 and 500 BPM")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x03, 0x09), data: [bpm / 128, bpm % 128])
}

public func metronomeReadStatus() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x01, 0x0F), size: (0x00, 0x00, 0x00, 0x01))
}

public func metronomeReadTempo() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x01, 0x08), size: (0x00, 0x00, 0x00, 0x02))
}

// MARK: - Master volume

public let MASTER_VOLUME_DT1_MAX = 100

public func masterVolumeSet(value: Int) throws -> MidiMessage {
    guard (0...MASTER_VOLUME_DT1_MAX).contains(value) else {
        throw MidiMessageError.valueError("Master Volume must be between 0 and \(MASTER_VOLUME_DT1_MAX)")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x13), data: [value])
}

public func masterVolumeRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x13), size: (0x00, 0x00, 0x00, 0x01))
}

public func masterVolumeRealtime(value0to127: Int) throws -> MidiMessage {
    guard (0...127).contains(value0to127) else {
        throw MidiMessageError.valueError("Master Volume must be between 0 and 127")
    }
    return .sysex(data: [0x7F, 0x7F, 0x04, 0x01, 0x00, UInt8(value0to127)])
}

public func keyTransposeRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x01, 0x01), size: (0x00, 0x00, 0x00, 0x01))
}

// MARK: - Keyboard mode / tones

public func keyboardModeSet(mode: Int) throws -> MidiMessage {
    guard (0...3).contains(mode) else {
        throw MidiMessageError.valueError("Keyboard mode must be between 0 and 3")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x00), data: [mode])
}

public func keyboardModeRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x00), size: (0x00, 0x00, 0x00, 0x01))
}

public func toneForSingleSet(categoryIdx: Int, num: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x07), data: [categoryIdx, num / 128, num % 128])
}

public func toneForSplitSet(categoryIdx: Int, num: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x0A), data: [categoryIdx, num / 128, num % 128])
}

public func toneForDualSet(categoryIdx: Int, num: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x0D), data: [categoryIdx, num / 128, num % 128])
}

public func toneForSingleRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x07), size: (0x00, 0x00, 0x00, 0x03))
}

public func toneForSplitRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x0A), size: (0x00, 0x00, 0x00, 0x03))
}

public func toneForDualRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x0D), size: (0x00, 0x00, 0x00, 0x03))
}

// MARK: - Split point / balance

public func splitPointSet(noteMidi: Int) throws -> MidiMessage {
    guard (0...127).contains(noteMidi) else {
        throw MidiMessageError.valueError("Split point must be between 0 and 127")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x01), data: [noteMidi])
}

public func splitPointRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x01), size: (0x00, 0x00, 0x00, 0x01))
}

/// Split balance L:R pair (1..9 each) for the balance label. Panel 0...18, 9 = center.
public func splitBalanceDisplayLR(panelValue0to18: Int) -> (Int, Int) {
    let v = max(0, min(18, panelValue0to18))
    if v <= 9 {
        return (9, 1 + (8 * v) / 9)
    }
    return (1 + (8 * (18 - v)) / 9, 9)
}

/// Collapses the two redundant steps at the extremes to the final visible value.
public func splitBalanceNormalizePanel(_ value: Int) -> Int {
    let v = max(0, min(18, value))
    if v <= 1 { return 0 }
    if v >= 17 { return 18 }
    return v
}

/// Panel index 0...18 (9 = center) to DT1 byte, centered on 64.
public func splitBalanceSysexByte(_ value: Int) -> Int {
    let v = max(0, min(18, value))
    return max(0, min(127, 64 + (v - 9)))
}

/// Inverts an RQ1/DT1 byte to panel index 0...18.
public func splitBalancePanelFromSysexByte(_ raw: Int) -> Int {
    if (0...18).contains(raw) {
        return max(0, min(18, raw))
    }
    let v = Int((Double(raw) - 64 + 9).rounded())
    return max(0, min(18, v))
}

public func dualBalanceDisplayLR(panelValue0to18: Int) -> (Int, Int) {
    let v = max(DUAL_BALANCE_PANEL_MIN, min(DUAL_BALANCE_PANEL_MAX, panelValue0to18))
    return splitBalanceDisplayLR(panelValue0to18: v)
}

public func splitBalanceSet(_ value: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x03), data: [splitBalanceSysexByte(value)])
}

public func splitBalanceControlChanges(_ value: Int) -> [MidiMessage] {
    let v = max(0, min(18, value))
    let d = v - 9
    let left = max(1, min(127, 100 - d))
    let right = max(1, min(127, 100 + d))
    let leftCh = MIDI_SPLIT_LEFT_VOLUME_CH - 1
    let rightCh = MIDI_SPLIT_RIGHT_VOLUME_CH - 1
    return [.controlChange(channel: leftCh, control: 7, value: left),
            .controlChange(channel: rightCh, control: 7, value: right)]
}

public func splitBalanceRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x03), size: (0x00, 0x00, 0x00, 0x01))
}

// MARK: - Dual balance

public func dualBalanceSysexByte(_ value: Int) -> Int {
    let v = max(DUAL_BALANCE_PANEL_MIN, min(DUAL_BALANCE_PANEL_MAX, value))
    return max(0, min(127, 64 + (v - 9) * 3))
}

public func dualBalancePanelFromSysexByte(_ raw: Int) -> Int {
    let v: Int
    if raw <= 18 {
        v = raw
    } else {
        v = Int((Double(raw) - 64).rounded() / 3 + 9)
    }
    return max(DUAL_BALANCE_PANEL_MIN, min(DUAL_BALANCE_PANEL_MAX, v))
}

public func dualBalanceSet(_ value: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x05), data: [dualBalanceSysexByte(value)])
}

public func dualBalanceRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x05), size: (0x00, 0x00, 0x00, 0x01))
}

public func dualBalanceControlChanges(_ value: Int) -> [MidiMessage] {
    let b = dualBalanceSysexByte(value)
    let d = b - 64
    let main = max(1, min(127, 100 - d))
    let layer = max(1, min(127, 100 + d))
    let mainCh = MIDI_DUAL_MAIN_VOLUME_CH - 1
    let layerCh = MIDI_DUAL_LAYER_VOLUME_CH - 1
    return [.controlChange(channel: mainCh, control: 7, value: main),
            .controlChange(channel: layerCh, control: 7, value: layer)]
}

// MARK: - Octave shifts

public func splitOctaveShiftSet(_ value: Int) throws -> MidiMessage {
    guard (-3...3).contains(value) else {
        throw MidiMessageError.valueError("Split octave shift must be between -3 and 3")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x02), data: [value + 64])
}

public func splitOctaveShiftRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x02), size: (0x00, 0x00, 0x00, 0x01))
}

public func dualOctaveShiftSet(_ value: Int) throws -> MidiMessage {
    guard (-3...3).contains(value) else {
        throw MidiMessageError.valueError("Dual octave shift must be between -3 and 3")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x04), data: [value + 64])
}

public func dualOctaveShiftRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x04), size: (0x00, 0x00, 0x00, 0x01))
}

public func splitRightOctaveShiftSet(_ value: Int) throws -> MidiMessage {
    guard (-3...3).contains(value) else {
        throw MidiMessageError.valueError("Split right octave shift must be between -3 and 3")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x16), data: [value + 64])
}

public func splitRightOctaveShiftRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x16), size: (0x00, 0x00, 0x00, 0x01))
}

public func dualTone1OctaveShiftSet(_ value: Int) throws -> MidiMessage {
    guard (-3...3).contains(value) else {
        throw MidiMessageError.valueError("Dual tone 1 octave shift must be between -3 and 3")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x17), data: [value + 64])
}

public func dualTone1OctaveShiftRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x17), size: (0x00, 0x00, 0x00, 0x01))
}

// MARK: - Twin piano

public func twinPianoModeSet(_ mode: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x06), data: [mode])
}

public func twinPianoModeRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x06), size: (0x00, 0x00, 0x00, 0x01))
}

// MARK: - Metronome volume / tone / beat / pattern

public func metronomeVolumeSet(_ value0to10: Int) throws -> MidiMessage {
    guard (0...10).contains(value0to10) else {
        throw MidiMessageError.valueError("Metronome volume must be between 0 and 10")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x21), data: [value0to10])
}

public func metronomeVolumeRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x21), size: (0x00, 0x00, 0x00, 0x01))
}

public func metronomeToneSet(_ value0to3: Int) throws -> MidiMessage {
    guard (0...3).contains(value0to3) else {
        throw MidiMessageError.valueError("Metronome tone must be between 0 and 3")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x22), data: [value0to3])
}

public func metronomeToneRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x22), size: (0x00, 0x00, 0x00, 0x01))
}

public func metronomeBeatSet(_ value: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x02, 0x1F), data: [value])
}

public func metronomeBeatRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x1F), size: (0x00, 0x00, 0x00, 0x01))
}

public func metronomePatternSet(_ value: Int) throws -> MidiMessage {
    guard (0...7).contains(value) else {
        throw MidiMessageError.valueError("Metronome pattern must be between 0 and 7")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x20), data: [value])
}

public func metronomePatternRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x20), size: (0x00, 0x00, 0x00, 0x01))
}

// MARK: - Master tuning

// FP-30X master tuning: useful A4 range ~415.3 Hz ... 466.2 Hz. Roland Piano App
// maps `raw = hz * 10 - 4144`, useful raw 9...518 (2 7-bit bytes, MSB first).
public let MASTER_TUNING_REF_HZ: Double = 440.0
public let MASTER_TUNING_MIN_HZ: Double = 415.3
public let MASTER_TUNING_MAX_HZ: Double = 466.2
public let MASTER_TUNING_MIN_RAW = 9
public let MASTER_TUNING_MAX_RAW = 518
public let MASTER_TUNING_MIN_CENTS: Double = 1200.0 * log2(MASTER_TUNING_MIN_HZ / MASTER_TUNING_REF_HZ)
public let MASTER_TUNING_MAX_CENTS: Double = 1200.0 * log2(MASTER_TUNING_MAX_HZ / MASTER_TUNING_REF_HZ)

public func masterTuningRawFromHz(_ hz: Double) -> Int {
    let h = max(MASTER_TUNING_MIN_HZ, min(MASTER_TUNING_MAX_HZ, hz))
    return max(MASTER_TUNING_MIN_RAW,
               min(MASTER_TUNING_MAX_RAW, Int((h * 10 - 4144).rounded())))
}

public func masterTuningHzFromRaw(_ raw: Int) -> Double {
    let r = max(MASTER_TUNING_MIN_RAW, min(MASTER_TUNING_MAX_RAW, raw))
    return Double(4144 + r) / 10.0
}

public func masterTuningCentsFromRaw(_ raw: Int) -> Double {
    let hz = masterTuningHzFromRaw(raw)
    return 1200.0 * log2(hz / MASTER_TUNING_REF_HZ)
}

public func masterTuningSetRaw(_ raw: Int) -> MidiMessage {
    let r = max(MASTER_TUNING_MIN_RAW, min(MASTER_TUNING_MAX_RAW, raw))
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x18), data: [r / 128, r % 128])
}

public func masterTuningSet(centsOffset: Double) -> MidiMessage {
    let c = max(MASTER_TUNING_MIN_CENTS, min(MASTER_TUNING_MAX_CENTS, centsOffset))
    var hz = MASTER_TUNING_REF_HZ * pow(2, c / 1200)
    hz = max(MASTER_TUNING_MIN_HZ, min(MASTER_TUNING_MAX_HZ, hz))
    let raw = masterTuningRawFromHz(hz)
    return masterTuningSetRaw(raw)
}

public func masterTuningRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x18), size: (0x00, 0x00, 0x00, 0x02))
}

// MARK: - Key touch / brilliance / ambience

public func keyTouchSet(_ value0to5: Int) throws -> MidiMessage {
    guard (0...5).contains(value0to5) else {
        throw MidiMessageError.valueError("Key Touch must be between 0 and 5")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x1D), data: [value0to5])
}

public func keyTouchRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x1D), size: (0x00, 0x00, 0x00, 0x01))
}

public func brillianceSet(_ valueNeg1ToPos1: Int) throws -> MidiMessage {
    guard (-1...1).contains(valueNeg1ToPos1) else {
        throw MidiMessageError.valueError("Brilliance must be between -1 and +1")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x1C), data: [64 + valueNeg1ToPos1])
}

public func brillianceRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x1C), size: (0x00, 0x00, 0x00, 0x01))
}

public func ambienceSet(_ value0to10: Int) throws -> MidiMessage {
    guard (0...10).contains(value0to10) else {
        throw MidiMessageError.valueError("Ambience must be between 0 and 10")
    }
    return rolandDataSet1(address: (0x01, 0x00, 0x02, 0x1A), data: [value0to10])
}

public func ambienceRead() -> MidiMessage {
    rolandDataRequest1(address: (0x01, 0x00, 0x02, 0x1A), size: (0x00, 0x00, 0x00, 0x01))
}

// MARK: - Piano Designer (reverse-engineered from Roland Piano App 1.5.9)

@inlinable
func pdAddr(_ offset: UInt8) -> SysexAddress { (0x02, 0x00, 0x00, offset) }

public func pianoDesignerLidSet(_ value0to6: Int) -> MidiMessage {
    rolandDataSet1(address: pdAddr(0x01), data: [max(0, min(6, value0to6))])
}

public func pianoDesignerStringResonanceSet(_ value: Int) -> MidiMessage {
    rolandDataSet1(address: pdAddr(0x02), data: [max(0, min(10, value))])
}

public func pianoDesignerDamperResonanceSet(_ value: Int) -> MidiMessage {
    rolandDataSet1(address: pdAddr(0x03), data: [max(0, min(10, value))])
}

public func pianoDesignerKeyOffResonanceSet(_ value: Int) -> MidiMessage {
    rolandDataSet1(address: pdAddr(0x06), data: [max(0, min(10, value))])
}

public func pianoDesignerTemperamentSet(_ value0to9: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x00, 0x04), data: [max(0, min(9, value0to9))])
}

public func pianoDesignerTemperamentKeySet(_ value0to11: Int) -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x00, 0x00, 0x05), data: [max(0, min(11, value0to11))])
}

public func pianoDesignerWrite() -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x02, 0x00, 0x01), data: [0x01])
}

public func pianoDesignerEnter() -> MidiMessage {
    rolandDataSet1(address: (0x01, 0x02, 0x00, 0x00), data: [0x01])
}

/// Per-note fine tuning. centsX10: -500...+500. Address: 02 10 04 00 + note.
public func pianoDesignerIndividualNoteTuningSet(note0to87: Int, centsX10: Int) -> MidiMessage {
    let raw = max(0, min(1000, centsX10 + 500))
    let addr: SysexAddress = (0x02, 0x10, 0x04, UInt8(note0to87 & 0x7F))
    return rolandDataSet1(address: addr, data: [raw / 128, raw % 128])
}

/// Per-note tonal character. value: -5...+5 → offset 5.
public func pianoDesignerIndividualNoteCharacterSet(note0to87: Int, value: Int) -> MidiMessage {
    let raw = max(0, min(10, value + 5))
    let addr: SysexAddress = (0x02, 0x10, 0x05, UInt8(note0to87 & 0x7F))
    return rolandDataSet1(address: addr, data: [raw])
}

// MARK: - GM2 global reverb (Universal Realtime)

public func gm2GlobalReverbParameter(parameterPp: Int, value0to127: Int) throws -> MidiMessage {
    guard (0...127).contains(parameterPp), (0...127).contains(value0to127) else {
        throw MidiMessageError.valueError("Reverb parameter or value out of range")
    }
    return .sysex(data: [0x7F, 0x7F, 0x04, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01,
                         UInt8(parameterPp), UInt8(value0to127)])
}
