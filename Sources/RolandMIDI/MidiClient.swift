import Foundation
import CoreMIDI

// MARK: - Port enumeration

/// Display name of a CoreMIDI object (endpoint / device).
private func displayName(of obj: MIDIObjectRef) -> String? {
    var name: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(obj, kMIDIPropertyName, &name) == noErr,
          let str = name?.takeUnretainedValue() else { return nil }
    return str as String
}

/// Lists MIDI output (destination) port names, deduplicated preserving order.
public func listOutputNames() -> [String] {
    var seen = Set<String>()
    var names: [String] = []
    let n = MIDIGetNumberOfDestinations()
    for i in 0..<n {
        guard let name = displayName(of: MIDIGetDestination(i)) else { continue }
        if seen.insert(name).inserted { names.append(name) }
    }
    return names
}

/// Lists MIDI input (source) port names, deduplicated preserving order.
public func listInputNames() -> [String] {
    var seen = Set<String>()
    var names: [String] = []
    let n = MIDIGetNumberOfSources()
    for i in 0..<n {
        guard let name = displayName(of: MIDIGetSource(i)) else { continue }
        if seen.insert(name).inserted { names.append(name) }
    }
    return names
}

// MARK: - MIDI output client (CoreMIDI-backed)

/// MIDI output client. Mirrors `midi/client.py` (`MidiOutClient`).
public final class MidiOutClient {
    private var client: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var destination: MIDIEndpointRef = 0
    private var portName: String?
    public var traceSend: ((MidiMessage) -> Void)?

    public init(traceSend: ((MidiMessage) -> Void)? = nil) {
        self.traceSend = traceSend
    }

    deinit {
        close()
        if client != 0 { MIDIClientDispose(client) }
    }

    public var isOpened: Bool { destination != 0 && outPort != 0 }

    public var currentPortName: String? { portName }

    public func open(_ portName: String) throws {
        close()
        if client == 0 {
            var ref: MIDIClientRef = 0
            let status = MIDIClientCreate("RolandFP30XController" as CFString, nil, nil, &ref)
            guard status == noErr else {
                throw MidiMessageError.osError("MIDIClientCreate failed: \(status)")
            }
            client = ref
        }
        var port: MIDIPortRef = 0
        let createStatus = MIDIOutputPortCreate(client, "Out" as CFString, &port)
        guard createStatus == noErr else {
            throw MidiMessageError.osError("MIDIOutputPortCreate failed: \(createStatus)")
        }
        outPort = port

        // Locate destination endpoint by name.
        var endpoint: MIDIEndpointRef = 0
        let n = MIDIGetNumberOfDestinations()
        for i in 0..<n {
            let dest = MIDIGetDestination(i)
            if displayName(of: dest) == portName {
                endpoint = dest
                break
            }
        }
        guard endpoint != 0 else {
            MIDIPortDispose(outPort); outPort = 0
            throw MidiMessageError.osError("No MIDI output device named: \(portName)")
        }
        destination = endpoint
        self.portName = portName
    }

    public func close() {
        if outPort != 0 {
            MIDIPortDispose(outPort)
            outPort = 0
        }
        destination = 0
        portName = nil
    }

    public func send(_ msg: MidiMessage) throws {
        guard isOpened else {
            throw MidiMessageError.runtimeError("No MIDI output port is open")
        }
        traceSend?(msg)
        try sendBytes(msg.bytes)
    }

    public func sendAll(_ messages: [MidiMessage]) throws {
        for m in messages { try send(m) }
    }

    public func sendAllSpaced(_ messages: [MidiMessage], gapS: TimeInterval = 0.0) throws {
        var first = true
        for m in messages {
            if !first, gapS > 0 { Thread.sleep(forTimeInterval: gapS) }
            first = false
            try send(m)
        }
    }

    private func sendBytes(_ data: [UInt8]) throws {
        guard !data.isEmpty else { return }
        var packetList = MIDIPacketList()
        let status = data.withUnsafeBufferPointer { buf -> OSStatus in
            guard let base = buf.baseAddress else { return OSStatus(0) }
            return withUnsafeMutablePointer(to: &packetList) { listPtr -> OSStatus in
                let curPtr = MIDIPacketListInit(listPtr)
                _ = MIDIPacketListAdd(listPtr,
                                      MemoryLayout<MIDIPacketList>.size,
                                      curPtr,
                                      0,
                                      Int(buf.count),
                                      base)
                return MIDISend(outPort, destination, listPtr)
            }
        }
        if status != noErr {
            throw MidiMessageError.osError("MIDISend failed: \(status)")
        }
    }
}

// MARK: - Raw MIDI byte parser

/// Parses a stream of MIDI bytes (e.g. the contents of a CoreMIDI packet) into
/// structured messages. Handles running status and SysEx. Useful for the input
/// worker; mirrors how `mido` reconstructs messages from a port.
public func parseMidiBytes(_ data: [UInt8]) -> [MidiMessage] {
    var msgs: [MidiMessage] = []
    var i = 0
    var runningStatus: UInt8? = nil

    func readByte() -> UInt8? {
        guard i < data.count else { return nil }
        let b = data[i]; i += 1
        return b
    }

    while i < data.count {
        var status = data[i]
        if status & 0x80 == 0 {
            // data byte: use running status, do not advance (data[i] is first data byte)
            guard let rs = runningStatus else { i += 1; continue }
            status = rs
        } else {
            // system real-time: single byte, does not affect running status
            if status >= 0xF8 { i += 1; continue }
            i += 1
            if status != 0xF0 && status != 0xF7 {
                runningStatus = status
            }
        }
        let nib = status & 0xF0
        let ch = Int(status & 0x0F)
        switch nib {
        case 0x80:
            guard let n = readByte(), let v = readByte() else { return msgs }
            msgs.append(.noteOff(channel: ch, note: Int(n), velocity: Int(v)))
        case 0x90:
            guard let n = readByte(), let v = readByte() else { return msgs }
            msgs.append(.noteOn(channel: ch, note: Int(n), velocity: Int(v)))
        case 0xA0:
            _ = readByte(); _ = readByte()  // poly aftertouch (unused)
        case 0xB0:
            guard let c = readByte(), let v = readByte() else { return msgs }
            msgs.append(.controlChange(channel: ch, control: Int(c), value: Int(v)))
        case 0xC0:
            guard let p = readByte() else { return msgs }
            msgs.append(.programChange(channel: ch, program: Int(p)))
        case 0xD0:
            _ = readByte()  // channel pressure (unused)
        case 0xE0:
            _ = readByte(); _ = readByte()  // pitch bend (unused)
        default: // 0xF0 system common / sysex
            switch status {
            case 0xF0:
                // collect until F7 inclusive; payload excludes F0/F7
                var payload: [UInt8] = []
                while i < data.count {
                    let b = data[i]; i += 1
                    if b == 0xF7 { break }
                    payload.append(b)
                }
                runningStatus = nil
                msgs.append(.sysex(data: payload))
            case 0xF1, 0xF3:
                _ = readByte()
            case 0xF2:
                _ = readByte(); _ = readByte()
            default:
                break // 0xF6 etc.: no data
            }
        }
    }
    return msgs
}

// MARK: - MIDI input worker

/// Reads incoming MIDI from a source endpoint via a CoreMIDI read callback and
/// delivers parsed messages on `queue`. Mirrors `ui/midi_in_worker.py`.
public final class MidiInWorker {
    private var client: MIDIClientRef = 0
    private var inPort: MIDIPortRef = 0
    private var source: MIDIEndpointRef = 0
    private let portName: String
    private let queue: DispatchQueue
    private let onMessage: (MidiMessage) -> Void

    public init(portName: String,
                queue: DispatchQueue = .main,
                onMessage: @escaping (MidiMessage) -> Void) {
        self.portName = portName
        self.queue = queue
        self.onMessage = onMessage
    }

    deinit { stop() }

    public func start() throws {
        var ref: MIDIClientRef = 0
        let cs = MIDIClientCreate("RolandFP30XController-In" as CFString, nil, nil, &ref)
        guard cs == noErr else { throw MidiMessageError.osError("MIDIClientCreate failed: \(cs)") }
        client = ref

        // The read callback receives a pointer to `self` as refCon.
        let refCon = Unmanaged.passUnretained(self).toOpaque()
        var port: MIDIPortRef = 0
        let ps = MIDIInputPortCreate(client, "In" as CFString, midiInReadProc, refCon, &port)
        guard ps == noErr else {
            MIDIClientDispose(client); client = 0
            throw MidiMessageError.osError("MIDIInputPortCreate failed: \(ps)")
        }
        inPort = port

        var endpoint: MIDIEndpointRef = 0
        let n = MIDIGetNumberOfSources()
        for i in 0..<n {
            let src = MIDIGetSource(i)
            if displayName(of: src) == portName {
                endpoint = src
                break
            }
        }
        guard endpoint != 0 else {
            throw MidiMessageError.osError("No MIDI input device named: \(portName)")
        }
        source = endpoint
        let connStatus = MIDIPortConnectSource(inPort, source, nil)
        guard connStatus == noErr else {
            throw MidiMessageError.osError("MIDIPortConnectSource failed: \(connStatus)")
        }
    }

    public func stop() {
        if inPort != 0 {
            if source != 0 { MIDIPortDisconnectSource(inPort, source) }
            MIDIPortDispose(inPort)
            inPort = 0
        }
        source = 0
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }
}

private let midiInReadProc: MIDIReadProc = { pktlist, refCon, _ in
    guard let refCon = refCon else { return }
    let worker = Unmanaged<MidiInWorker>.fromOpaque(refCon).takeUnretainedValue()
    let count = Int(pktlist.pointee.numPackets)
    var packetPtr: UnsafeMutablePointer<MIDIPacket> = withUnsafePointer(to: pktlist.pointee.packet) {
        UnsafeMutablePointer(mutating: $0)
    }
    var collected: [MidiMessage] = []
    for i in 0..<count {
        let packet = packetPtr.pointee
        let len = Int(packet.length)
        // packet.data is a tuple; read its raw bytes.
        withUnsafeBytes(of: packet.data) { raw in
            let bytes = Array(raw.prefix(len)).map { $0 }
            collected.append(contentsOf: parseMidiBytes(bytes))
        }
        if i + 1 < count {
            packetPtr = MIDIPacketNext(packetPtr)
        }
    }
    guard !collected.isEmpty else { return }
    worker.deliver(collected)
}

extension MidiInWorker {
    fileprivate func deliver(_ messages: [MidiMessage]) {
        queue.async { [weak self] in
            guard self != nil else { return }
            for m in messages { self?.onMessage(m) }
        }
    }
}
