import Foundation

/// Holds the last bank (CC0/CC32) per channel and returns `(msb, lsb, programDoc)`
/// on Program Change. Mirrors `midi/bank_program_parser.py`.
public final class BankProgramParser {
    private struct BankHold {
        var bankMsb: Int = 0
        var bankLsb: Int = 0
    }

    private let ch0Set: Set<Int>
    private var hold: [Int: BankHold]

    public init(channels1to16: [Int]) throws {
        guard !channels1to16.isEmpty else {
            throw MidiMessageError.valueError("At least one MIDI channel (1–16) is required")
        }
        for c in channels1to16 where !(1...16).contains(c) {
            throw MidiMessageError.valueError("MIDI channel must be between 1 and 16")
        }
        self.ch0Set = Set(channels1to16.map { $0 - 1 })
        self.hold = Dictionary(uniqueKeysWithValues: ch0Set.map { ($0, BankHold()) })
    }

    public convenience init(channels1to16: Int...) throws {
        try self.init(channels1to16: channels1to16)
    }

    /// Returns `(msb, lsb, programDoc)` where `programDoc = program + 1`.
    public func feed(_ msg: MidiMessage) -> (msb: Int, lsb: Int, programDoc: Int)? {
        guard let ch0 = msg.channel, ch0Set.contains(ch0) else { return nil }
        guard var st = hold[ch0] else { return nil }
        switch msg {
        case .controlChange(_, let control, let value):
            if control == 0 { st.bankMsb = value }
            if control == 32 { st.bankLsb = value }
            hold[ch0] = st
            return nil
        case .programChange(_, let program):
            hold[ch0] = st
            return (st.bankMsb, st.bankLsb, program + 1)
        default:
            return nil
        }
    }
}
