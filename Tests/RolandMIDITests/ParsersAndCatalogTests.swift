import XCTest
@testable import RolandMIDI

final class BankProgramParserTests: XCTestCase {

    func testParserProgramChangeUsesLastBank() throws {
        let p = try BankProgramParser(channels1to16: 4)
        XCTAssertNil(p.feed(.controlChange(channel: 3, control: 0, value: 16)))
        XCTAssertNil(p.feed(.controlChange(channel: 3, control: 32, value: 67)))
        let r = p.feed(.programChange(channel: 3, program: 0))
        XCTAssertEqual(r?.msb, 16)
        XCTAssertEqual(r?.lsb, 67)
        XCTAssertEqual(r?.programDoc, 1)
    }

    func testParserIgnoresOtherChannel() throws {
        let p = try BankProgramParser(channels1to16: 1, 4)
        XCTAssertNil(p.feed(.programChange(channel: 2, program: 5)))
    }

    func testParserWrongChannelNoBankUpdate() throws {
        let p = try BankProgramParser(channels1to16: 4)
        XCTAssertNil(p.feed(.controlChange(channel: 0, control: 0, value: 99)))
        let r = p.feed(.programChange(channel: 3, program: 0))
        XCTAssertEqual(r?.msb, 0)
        XCTAssertEqual(r?.lsb, 0)
        XCTAssertEqual(r?.programDoc, 1)
    }

    func testParserChannel1MatchesFp30xPanelTx() throws {
        let p = try BankProgramParser(channels1to16: 1, 4)
        XCTAssertNil(p.feed(.controlChange(channel: 0, control: 0, value: 32)))
        XCTAssertNil(p.feed(.controlChange(channel: 0, control: 32, value: 68)))
        let r = p.feed(.programChange(channel: 0, program: 16))
        XCTAssertEqual(r?.msb, 32)
        XCTAssertEqual(r?.lsb, 68)
        XCTAssertEqual(r?.programDoc, 17)
    }

    func testParserBanksIndependentPerChannel() throws {
        let p = try BankProgramParser(channels1to16: 1, 4)
        p.feed(.controlChange(channel: 0, control: 0, value: 10))
        p.feed(.controlChange(channel: 0, control: 32, value: 20))
        p.feed(.controlChange(channel: 3, control: 0, value: 16))
        p.feed(.controlChange(channel: 3, control: 32, value: 67))
        let r0 = p.feed(.programChange(channel: 0, program: 0))
        XCTAssertEqual(r0?.msb, 10); XCTAssertEqual(r0?.lsb, 20); XCTAssertEqual(r0?.programDoc, 1)
        let r3 = p.feed(.programChange(channel: 3, program: 0))
        XCTAssertEqual(r3?.msb, 16); XCTAssertEqual(r3?.lsb, 67); XCTAssertEqual(r3?.programDoc, 1)
    }
}

final class SysexParserTests: XCTestCase {
    func testParseRolandDt1MasterVolume() {
        // DT1 reply for master volume = 100 at 01 00 02 13
        let msg = MidiMessage.sysex(data: [0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12,
                                           0x01, 0x00, 0x02, 0x13, 0x64, 0x06])
        let parsed = parseRolandDt1(msg)
        let addr = parsed?.address
        XCTAssertEqual(addr?.0, 0x01)
        XCTAssertEqual(addr?.1, 0x00)
        XCTAssertEqual(addr?.2, 0x02)
        XCTAssertEqual(addr?.3, 0x13)
        XCTAssertEqual(parsed?.data, [0x64])
    }

    func testParseRolandDt1RejectsNonRoland() {
        let msg = MidiMessage.sysex(data: [0x7F, 0x7F, 0x04, 0x01, 0x00, 0x64])
        XCTAssertNil(parseRolandDt1(msg))
    }

    func testParseMidiBytesRunningStatus() {
        // status 0xB3 (CC ch4) then running-status second CC
        let bytes: [UInt8] = [0xB3, 7, 100, 11, 64]
        let msgs = parseMidiBytes(bytes)
        XCTAssertEqual(msgs.count, 2)
        XCTAssertEqual(msgs[0], .controlChange(channel: 3, control: 7, value: 100))
        XCTAssertEqual(msgs[1], .controlChange(channel: 3, control: 11, value: 64))
    }

    func testParseMidiBytesSysex() {
        let bytes: [UInt8] = [0xF0, 0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12, 0x01, 0xF7]
        let msgs = parseMidiBytes(bytes)
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs[0].data, [0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12, 0x01])
    }
}

final class ToneCatalogTests: XCTestCase {
    func testToneDt1RoundtripFirstPreset() {
        let tone = TONE_PRESETS[0] // Concert Piano, Piano category index 0, num 0
        let enc = toneDt1Encoding(tone)
        XCTAssertEqual(enc.categoryIdx, 0)
        let back = toneFromDt1Bytes(enc.categoryIdx, enc.numHi, enc.numLo)
        XCTAssertEqual(back, tone)
    }

    func testToneDt1RoundtripAllPresets() {
        for tone in TONE_PRESETS {
            let enc = toneDt1Encoding(tone)
            let back = toneFromDt1Bytes(enc.categoryIdx, enc.numHi, enc.numLo)
            XCTAssertEqual(back, tone, "roundtrip failed for \(tone.name)")
        }
    }

    func testCategoryCounts() {
        // Every preset maps to a known category.
        for tone in TONE_PRESETS {
            XCTAssertTrue(CATEGORIES.contains(categoryOf(tone)))
        }
        XCTAssertEqual(CATEGORIES.count, 9)
    }
}
