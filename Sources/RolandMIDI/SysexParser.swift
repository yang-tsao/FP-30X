import Foundation

/// Parses incoming Roland DT1 SysEx messages.
///
/// Mirrors `midi/sysex_parser.py`. Returns `(address, data_bytes)` if the message
/// is a DT1 from the FP-30X, otherwise `nil`. The trailing checksum byte is dropped.
public func parseRolandDt1(_ msg: MidiMessage) -> (address: SysexAddress, data: [Int])? {
    guard case .sysex(let d) = msg, d.count >= 13 else { return nil }
    // data[0..6] = ROLAND_ID, DEVICE_ID, MODEL_ID×4, CMD
    if d[0] != ROLAND_ID { return nil }
    if d[1] != ROLAND_DEVICE_ID { return nil }
    if (d[2], d[3], d[4], d[5]) != FP30X_MODEL_ID { return nil }
    if d[6] != ROLAND_CMD_DT1 { return nil }
    let addr: SysexAddress = (d[7], d[8], d[9], d[10])
    // d[11 ..< count-1] = data bytes; last = checksum
    if d.count <= 12 { return nil }
    let data = Array(d[11..<(d.count - 1)]).map { Int($0) }
    if data.isEmpty { return nil }
    let checksumReceived = Int(d[d.count - 1])
    let checksumPayload = d[7..<(d.count - 1)].map { Int($0) }
    let checksumComputed = rolandChecksum(checksumPayload)
    if checksumComputed != checksumReceived { return nil }
    return (addr, data)
}
