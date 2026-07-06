# AGENTS.md

## Build & Test

```bash
swift build            # debug
swift build -c release # release
swift test             # all tests
swift test --filter MessagesTests   # single test class
swift test --filter "testChannelZero"  # single test method
```

To create the macOS .app bundle: `./scripts/make_app.sh` (optional: `brew install librsvg` for icon embedding).

## Architecture

```
Sources/
  RolandMIDI/             # Library: MIDI message types, SysEx builders, parsers, tone catalog
  RolandFP30XController/  # SwiftUI macOS app (executable), depends on RolandMIDI
Tests/
  RolandMIDITests/        # Unit tests for RolandMIDI only (no UI tests)
```

**Two SPM products:**
- `RolandMIDI` — library (`Sources/RolandMIDI`)
- `RolandFP30XController` — executable (`Sources/RolandFP30XController`)

## Key Conventions

- **MIDI channels**: API functions take 1-based channels (`channel1to16: 1...16`). `channelZero()` converts to 0-based for wire bytes.
- **Tone program numbers**: `Tone.programDoc` is 1…128 (manual convention); `Tone.programMidi` is 0…127 (wire format).
- **SysEx addresses**: 4-byte tuples `(UInt8,UInt8,UInt8,UInt8)`.
- **No external dependencies** — pure SPM with CoreMIDI and SwiftUI from the platform SDK.
- **Language**: String codes `"en"`/`"es"`/`"zh"`, auto-detected from `Locale` on first launch (stored in `UserDefaults`).
- **Verbose mode**: pass `--verbose` flag to enable hex MIDI tracing to stderr.
- **platforms**: macOS 13+ only. The app won't build for iOS/Linux.

## MIDI Behavior (Gotchas)

- A **message gap** of 20 ms (`DEFAULT_MESSAGE_GAP_S = 0.02`) is inserted between CC0/CC32/PC in bank-select sequences to avoid FP-30X grouping errors in some drivers.
- An extra **80 ms delay** (`POST_PROGRAM_CHANGE_LATCH_DELAY_S`) follows program changes before the latch Note On for drum kits.
- The app **requires bidirectional MIDI** for full two-way sync (receives DT1 responses to RQ1 polls). Output-only connections work but give a limited experience.
- **Port watchdog** (1 s interval) detects if the connected MIDI port disappears and auto-disconnects.
- **Piano poll** (2.5 s interval) re-reads all device state via RQ1 messages; suppressed for 2 s after any user send.
- `ignorePianoPatchUntil` blocks incoming DT1 for 550 ms after sending a bank/program change, to prevent stale echo.
- `suppressSliderMidi` guards against feedback loops when a slider position changes because of an incoming DT1.

## Tests

- Tests cover `RolandMIDI` only: message construction, parsers (`BankProgramParser`, `RpnParser`), tone catalog lookup, SysEx encoding.
- No UI or integration tests exist.
- Run single tests with `swift test --filter <testMethodName>`.
