import Foundation

/// A MIDI message value type (replaces `mido.Message` for the FP-30X controller).
///
/// Channel-voice messages carry a 0-based `channel` (0...15). System-exclusive
/// messages carry their payload in `data` (bytes strictly between the F0 / F7
/// wrappers), matching `mido`'s `msg.data` for sysex.
public enum MidiMessage: Equatable, Sendable {
    case controlChange(channel: Int, control: Int, value: Int)
    case programChange(channel: Int, program: Int)
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case sysex(data: [UInt8])

    /// Type name, mirroring `mido.Message.type`.
    public var type: String {
        switch self {
        case .controlChange: return "control_change"
        case .programChange: return "program_change"
        case .noteOn: return "note_on"
        case .noteOff: return "note_off"
        case .sysex: return "sysex"
        }
    }

    public var channel: Int? {
        switch self {
        case .controlChange(let c, _, _),
             .programChange(let c, _),
             .noteOn(let c, _, _),
             .noteOff(let c, _, _):
            return c
        case .sysex:
            return nil
        }
    }

    public var control: Int? {
        if case .controlChange(_, let c, _) = self { return c }
        return nil
    }

    public var value: Int? {
        if case .controlChange(_, _, let v) = self { return v }
        return nil
    }

    public var program: Int? {
        if case .programChange(_, let p) = self { return p }
        return nil
    }

    public var note: Int? {
        if case .noteOn(_, let n, _) = self { return n }
        if case .noteOff(_, let n, _) = self { return n }
        return nil
    }

    public var velocity: Int? {
        if case .noteOn(_, _, let v) = self { return v }
        if case .noteOff(_, _, let v) = self { return v }
        return nil
    }

    /// Sysex payload (bytes between F0 and F7). Empty for channel messages.
    public var data: [UInt8] {
        if case .sysex(let d) = self { return d }
        return []
    }

    /// Full wire bytes including status byte and (for sysex) F0/F7 wrappers.
    /// Mirrors `mido.Message.bytes()`.
    public var bytes: [UInt8] {
        switch self {
        case .controlChange(let ch, let c, let v):
            return [0xB0 | UInt8(ch & 0x0F), UInt8(c & 0x7F), UInt8(v & 0x7F)]
        case .programChange(let ch, let p):
            return [0xC0 | UInt8(ch & 0x0F), UInt8(p & 0x7F)]
        case .noteOn(let ch, let n, let v):
            return [0x90 | UInt8(ch & 0x0F), UInt8(n & 0x7F), UInt8(v & 0x7F)]
        case .noteOff(let ch, let n, let v):
            return [0x80 | UInt8(ch & 0x0F), UInt8(n & 0x7F), UInt8(v & 0x7F)]
        case .sysex(let d):
            return [0xF0] + d + [0xF7]
        }
    }

    /// Mirror of `mido.Message.bin()`.
    public func bin() -> [UInt8] { bytes }
}

/// Errors raised by the MIDI message builders, mirroring the Python `ValueError`
/// / `RuntimeError` contracts used throughout `messages.py`.
public enum MidiMessageError: Error, Equatable, CustomStringConvertible {
    case valueError(String)
    case runtimeError(String)
    case osError(String)

    public var description: String {
        switch self {
        case .valueError(let s): return s
        case .runtimeError(let s): return s
        case .osError(let s): return s
        }
    }
}
