import XCTest
@testable import RolandMIDI

final class MessagesTests: XCTestCase {

    func testChannelZero() throws {
        XCTAssertEqual(try channelZero(1), 0)
        XCTAssertEqual(try channelZero(16), 15)
    }

    func testGm2GlobalReverbTimeSysex() throws {
        let m = try gm2GlobalReverbParameter(parameterPp: 1, value0to127: 64)
        XCTAssertEqual(m.type, "sysex")
        XCTAssertEqual(m.bytes, [0xF0, 0x7F, 0x7F, 0x04, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x40, 0xF7])
    }

    func testMasterVolumeSysex() throws {
        let m = try masterVolumeRealtime(value0to127: 100)
        XCTAssertEqual(m.type, "sysex")
        XCTAssertEqual(m.bytes, [0xF0, 0x7F, 0x7F, 0x04, 0x01, 0x00, 0x64, 0xF7])
    }

    func testMasterVolumeDt1SetMax100() throws {
        let m = try masterVolumeSet(value: 100)
        XCTAssertEqual(m.type, "sysex")
        XCTAssertEqual(m.bytes, [0xF0, 0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12,
                                 0x01, 0x00, 0x02, 0x13, 0x64, 0x06, 0xF7])
    }

    func testMasterVolumeDt1SetRejectsOverMax() {
        XCTAssertThrowsError(try masterVolumeSet(value: 101)) { error in
            guard case .valueError(let msg) = error as? MidiMessageError else {
                return XCTFail("expected valueError")
            }
            XCTAssertTrue(msg.contains("100"))
        }
    }

    func testKeyTouchSetSuperHeavySysex() throws {
        let m = try keyTouchSet(5)
        XCTAssertEqual(m.type, "sysex")
        XCTAssertEqual(m.bytes, [0xF0, 0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12,
                                 0x01, 0x00, 0x02, 0x1D, 0x05, 0x5B, 0xF7])
    }

    func testKeyTouchSetRejectsOverMax() {
        XCTAssertThrowsError(try keyTouchSet(6)) { error in
            guard case .valueError(let msg) = error as? MidiMessageError else {
                return XCTFail("expected valueError")
            }
            XCTAssertTrue(msg.contains("5"))
        }
    }

    func testMasterTuningSetCenterSysex() {
        let m = masterTuningSet(centsOffset: 0.0)
        XCTAssertEqual(m.type, "sysex")
        XCTAssertEqual(m.bytes, [0xF0, 0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12,
                                 0x01, 0x00, 0x02, 0x18, 0x02, 0x00, 0x63, 0xF7])
    }

    func testMasterTuningSetRawEndpoints() {
        let mLo = masterTuningSetRaw(MASTER_TUNING_MIN_RAW)
        let mHi = masterTuningSetRaw(MASTER_TUNING_MAX_RAW)
        let loBytes = mLo.bytes
        let hiBytes = mHi.bytes
        XCTAssertEqual(Array(loBytes[12..<14]), [0x00, 0x09])
        XCTAssertEqual(Array(hiBytes[12..<14]), [0x04, 0x06])
    }

    func testMasterTuningEndpoints() {
        XCTAssertEqual(masterTuningHzFromRaw(MASTER_TUNING_MIN_RAW), MASTER_TUNING_MIN_HZ)
        XCTAssertEqual(masterTuningHzFromRaw(MASTER_TUNING_MAX_RAW), MASTER_TUNING_MAX_HZ)
        XCTAssertEqual(masterTuningRawFromHz(MASTER_TUNING_MIN_HZ), MASTER_TUNING_MIN_RAW)
        XCTAssertEqual(masterTuningRawFromHz(MASTER_TUNING_MAX_HZ), MASTER_TUNING_MAX_RAW)
        let hz440 = masterTuningHzFromRaw(masterTuningRawFromHz(440.0))
        XCTAssert(abs(hz440 - 440.0) < 0.02)
    }

    func testMasterTuningObservedPoints() {
        XCTAssertEqual(masterTuningHzFromRaw(133), 427.7)
        XCTAssertEqual(masterTuningRawFromHz(427.7), 133)
        XCTAssert(abs(masterTuningHzFromRaw(masterTuningRawFromHz(415.3)) - 415.3) < 0.02)
        XCTAssert(abs(masterTuningHzFromRaw(masterTuningRawFromHz(416.1)) - 416.1) < 0.02)
        XCTAssert(abs(masterTuningHzFromRaw(masterTuningRawFromHz(416.6)) - 416.6) < 0.02)
        XCTAssert(abs(masterTuningHzFromRaw(masterTuningRawFromHz(416.8)) - 416.8) < 0.02)
    }

    func testMasterTuningSetClampsHighToMaxRaw() {
        let mHi = masterTuningSet(centsOffset: MASTER_TUNING_MAX_CENTS)
        let mClamp = masterTuningSet(centsOffset: 500.0)
        XCTAssertEqual(mHi.bytes, mClamp.bytes)
    }

    func testBankProgramOrder() throws {
        let msgs = try bankSelectAndProgramChange(channel1to16: 3, bankMsb: 0x10, bankLsb: 0x20, program0to127: 0x05)
        XCTAssertEqual(msgs.map { $0.type }, ["control_change", "control_change", "program_change"])
        XCTAssertEqual(msgs[0].channel, 2)
        XCTAssertEqual(msgs[0].control, 0)
        XCTAssertEqual(msgs[0].value, 0x10)
        XCTAssertEqual(msgs[1].control, 32)
        XCTAssertEqual(msgs[1].value, 0x20)
        XCTAssertEqual(msgs[2].program, 5)
    }

    func testBankProgramSequenceLatch() throws {
        let withLatch = try bankSelectProgramSequence(channel1to16: 1, bankMsb: 0, bankLsb: 68, program0to127: 0, latchAfterProgram: true)
        XCTAssertEqual(withLatch.count, 5)
        XCTAssertEqual(withLatch[3].type, "note_on")
        XCTAssertEqual(withLatch[3].note, 60)
        XCTAssertEqual(withLatch[4].type, "note_off")
        let noLatch = try bankSelectProgramSequence(channel1to16: 1, bankMsb: 0, bankLsb: 68, program0to127: 0, latchAfterProgram: false)
        XCTAssertEqual(noLatch.count, 3)
    }

    func testBankProgramLatchParts() throws {
        let parts = try bankSelectProgramAndLatchParts(channel1to16: 4, bankMsb: 0, bankLsb: 68, program0to127: 0)
        XCTAssertEqual(parts.core.count, 3)
        XCTAssertEqual(parts.core.last!.type, "program_change")
        XCTAssertEqual(parts.core.last!.channel, 3)
        XCTAssertEqual(parts.latch.count, 2)
    }

    func testRpnCoarseTuningSequence() throws {
        let msgs = try rpnCoarseTuning(channel1to16: 4, semitones: -5)
        XCTAssertEqual(msgs.map { $0.type }, Array(repeating: "control_change", count: 6))
        XCTAssertEqual(msgs.map { $0.control! }, [101, 100, 6, 38, 101, 100])
        XCTAssertEqual(msgs.map { $0.value! }, [0, 2, 59, 0, 127, 127])
        XCTAssertTrue(msgs.allSatisfy { $0.channel == 3 })
    }

    func testRpnParserDetectsCoarseTuning() throws {
        let p = try RpnParser(channels1to16: 1, 4)
        XCTAssertNil(p.feedCoarseTuning(.controlChange(channel: 3, control: 101, value: 0)))
        XCTAssertNil(p.feedCoarseTuning(.controlChange(channel: 3, control: 100, value: 2)))
        XCTAssertEqual(p.feedCoarseTuning(.controlChange(channel: 3, control: 6, value: 69)), 5)
    }

    func testMasterCoarseTuningRealtimeSysex() throws {
        let m = try masterCoarseTuningRealtime(semitones: 5)
        XCTAssertEqual(m.type, "sysex")
        XCTAssertEqual(m.bytes, [0xF0, 0x7F, 0x7F, 0x04, 0x04, 0x00, 0x45, 0xF7])
    }

    func testAppConnectHandshakeSysex() {
        let m = appConnectHandshake()
        XCTAssertEqual(m.bytes, [0xF0, 0x41, 0x10, 0x00, 0x00, 0x00, 0x28, 0x12,
                                 0x01, 0x00, 0x03, 0x06, 0x01, 0x75, 0xF7])
    }

    func testDualBalanceSysexRoundtrip() {
        for v in DUAL_BALANCE_PANEL_MIN...DUAL_BALANCE_PANEL_MAX {
            let b = dualBalanceSysexByte(v)
            XCTAssertEqual(dualBalancePanelFromSysexByte(b), v)
        }
        XCTAssertEqual(dualBalanceSysexByte(0), dualBalanceSysexByte(DUAL_BALANCE_PANEL_MIN))
        XCTAssertEqual(dualBalanceSysexByte(18), dualBalanceSysexByte(DUAL_BALANCE_PANEL_MAX))
    }

    func testSplitBalanceSysexRoundtrip() {
        for v in 0...18 {
            let b = splitBalanceSysexByte(v)
            XCTAssertEqual(splitBalancePanelFromSysexByte(b), v)
        }
    }

    func testSplitBalanceControlChangesSymmetricAtCenter() {
        let msgs = splitBalanceControlChanges(9)
        XCTAssertEqual(msgs.count, 2)
        XCTAssertTrue(msgs.allSatisfy { $0.type == "control_change" })
        XCTAssertEqual(msgs[0].value, 100)
        XCTAssertEqual(msgs[1].value, 100)
    }

    func testSplitBalanceDisplayLREndpoints() {
        XCTAssertEqual(splitBalanceDisplayLR(panelValue0to18: 0).0, 9)
        XCTAssertEqual(splitBalanceDisplayLR(panelValue0to18: 0).1, 1)
        let center = splitBalanceDisplayLR(panelValue0to18: 9)
        XCTAssertEqual(center.0, 9); XCTAssertEqual(center.1, 9)
        let hi = splitBalanceDisplayLR(panelValue0to18: 18)
        XCTAssertEqual(hi.0, 1); XCTAssertEqual(hi.1, 9)
    }

    func testDualBalanceDisplayLREndpoints() {
        let lo = dualBalanceDisplayLR(panelValue0to18: DUAL_BALANCE_PANEL_MIN)
        XCTAssertEqual(lo.0, 9); XCTAssertEqual(lo.1, 1)
        let center = dualBalanceDisplayLR(panelValue0to18: 9)
        XCTAssertEqual(center.0, 9); XCTAssertEqual(center.1, 9)
        let hi = dualBalanceDisplayLR(panelValue0to18: DUAL_BALANCE_PANEL_MAX)
        XCTAssertEqual(hi.0, 1); XCTAssertEqual(hi.1, 9)
    }

    func testParseMasterCoarseTuningSysex() {
        let m = MidiMessage.sysex(data: [0x7F, 0x7F, 0x04, 0x04, 0x00, 0x3C])
        XCTAssertEqual(parseMasterCoarseTuningSysex(m), -4)
    }
}
