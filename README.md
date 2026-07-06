# Roland FP-30X Controller

A native macOS controller app for the Roland FP-30X digital piano. Communicate with your piano via USB or Bluetooth MIDI to control tones, keyboard modes, metronome, transpose, master tuning, Piano Designer, and more.

> Much of the SysEx messaging was reverse-engineered from the official Roland Piano App (v1.5.9).

## Requirements

- macOS 13 (Ventura) or later
- Roland FP-30X digital piano connected via USB cable or Bluetooth MIDI
- Bidirectional MIDI is recommended for full two-way state sync

## Build

No external dependencies — pure Swift Package Manager with CoreMIDI and SwiftUI.

```bash
swift build                # debug
swift build -c release     # release
./scripts/make_app.sh      # create macOS .app bundle (optional: brew install librsvg for icon)
```

## Run

```bash
# Run from the command line (debug):
swift run RolandFP30XController

# Or with verbose MIDI tracing:
swift run RolandFP30XController --verbose

# Or open the .app bundle created by make_app.sh:
open build/Release/RolandFP30XController.app
```

### CLI Flags

| Flag          | Description                                                |
|---------------|------------------------------------------------------------|
| `--verbose`   | Print hex MIDI traces (outgoing and incoming) to stderr    |
| `--debug`     | Show a "Read piano values" button to query all RQ1 values  |

## macOS Gatekeeper

If you downloaded the `.app` bundle from a release, macOS may block it with a quarantine warning. Clear the attribute before launching:

```bash
xattr -c RolandFP30XController.app
```

## Test

```bash
swift test                                     # all tests
swift test --filter MessagesTests              # single test class
swift test --filter "testChannelZero"          # single test method
```

## Features

- **Piano Settings** — Master volume, key touch, master tuning (±50 cents, or per-note micro-tuning), brilliance, ambience depth, transpose

- **Tones** — 175+ presets across 9 categories (Piano, E.Piano, Organ, Strings, Pad, Synth, Other, Drums, GM2), with keyboard modes (Single, Split, Dual, Twin Piano) and per-layer octave shift, balance, and split point

- **Metronome** — Start/stop, tempo (10–500 BPM), volume (0–10), tone, beat, and pattern selection

- **Piano Designer (Beta)** — Lid position, string/damper/key-off resonance, temperament selection, per-note voicing and individual note tuning across all 88 keys

- **Connection** — Auto-detects MIDI ports, supports USB and Bluetooth, auto-disconnects if device disappears, polls piano state every 2.5 s

## Languages

English, Español, and 中文. Auto-detected from macOS locale on first launch, changeable in the app's Preferences window.

## Architecture

```
Sources/
  RolandMIDI/                — Library: MIDI message types, SysEx builders/parsers, tone catalog
  RolandFP30XController/     — SwiftUI macOS app (executable), depends on RolandMIDI
Tests/
  RolandMIDITests/           — Unit tests for the RolandMIDI library
```

Two SPM products: `RolandMIDI` (library) and `RolandFP30XController` (executable).

## License

Proprietary. No license granted.
