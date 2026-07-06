import Foundation

/// Tracks RPN state per channel and returns semitones when RPN 0,2 (coarse tuning)
/// arrives. Mirrors `midi/rpn_parser.py`.
public final class RpnParser {
    private struct State {
        var rpnMsb: Int = 127
        var rpnLsb: Int = 127
    }

    private let ch0Set: Set<Int>
    private var state: [Int: State]

    public init(channels1to16: [Int]) throws {
        guard !channels1to16.isEmpty else {
            throw MidiMessageError.valueError("At least one MIDI channel (1–16) is required")
        }
        for c in channels1to16 where !(1...16).contains(c) {
            throw MidiMessageError.valueError("MIDI channel must be between 1 and 16")
        }
        self.ch0Set = Set(channels1to16.map { $0 - 1 })
        self.state = Dictionary(uniqueKeysWithValues: ch0Set.map { ($0, State()) })
    }

    public convenience init(channels1to16: Int...) throws {
        try self.init(channels1to16: channels1to16)
    }

    /// Returns semitones (value - 64) when CC6 arrives with RPN 0,2 selected.
    public func feedCoarseTuning(_ msg: MidiMessage) -> Int? {
        guard case .controlChange(let ch0, let control, let value) = msg else { return nil }
        guard ch0Set.contains(ch0) else { return nil }
        guard var st = state[ch0] else { return nil }
        switch control {
        case 101:
            st.rpnMsb = value
            state[ch0] = st
            return nil
        case 100:
            st.rpnLsb = value
            state[ch0] = st
            return nil
        case 6 where st.rpnMsb == 0 && st.rpnLsb == 2:
            return value - 64
        default:
            return nil
        }
    }
}

/// Returns semitones if `msg` is a Universal Realtime Master Coarse Tuning SysEx.
public func parseMasterCoarseTuningSysex(_ msg: MidiMessage) -> Int? {
    guard case .sysex(let data) = msg, data.count == 6 else { return nil }
    guard data[0] == 0x7F, data[1] == 0x7F, data[2] == 0x04, data[3] == 0x04 else { return nil }
    let value = Int(data[5]) - 0x40
    guard (-24...24).contains(value) else { return nil }
    return value
}
