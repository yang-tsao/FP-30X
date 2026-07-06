import SwiftUI
import RolandMIDI

let accentOrange = Color(red: 0.878, green: 0.471, blue: 0.157) // #E07828
let panelBg = Color(NSColor.controlBackgroundColor)
let surfaceBg = Color(NSColor.quaternaryLabelColor).opacity(0.15)
let borderColor = Color.secondary.opacity(0.3)

// MARK: - Main Content

struct MainContentView: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar(model: model)
            Divider().background(borderColor)
            if !model.isConnected {
                TabContent(model: model)
                    .opacity(0.42)
                    .allowsHitTesting(false)
            } else {
                TabContent(model: model)
            }
            Divider().background(borderColor)
            HStack {
                Text(model.statusText)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Button(model.trl("btn_reset_defaults")) { model.resetDefaults() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct TabContent: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        TabView {
            PianoSettingsView(model: model)
                .tabItem { Label(model.trl("tab_piano_settings"), systemImage: "pianokeys") }
            TonesView(model: model)
                .tabItem { Label(model.trl("tab_tones"), systemImage: "music.note.list") }
            MetronomeView(model: model)
                .tabItem { Label(model.trl("tab_metronome"), systemImage: "metronome") }
            PianoDesignerView(model: model)
                .tabItem { Label(model.trl("tab_piano_designer"), systemImage: "hammer") }
        }
    }
}

// MARK: - Connection Bar

private struct ConnectionBar: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(model.trl("label_device"))
                Picker("", selection: $model.selectedOutput) {
                    ForEach(model.outputNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(minWidth: 200)
                .onAppear { model.refreshPorts() }

                Button(model.trl("btn_refresh")) { model.refreshPorts() }
                    .controlSize(.small)

                Button(model.isConnected ? model.trl("btn_disconnect") : model.trl("btn_connect")) {
                    model.toggleConnect()
                }
                .controlSize(.small)
                .tint(model.isConnected ? accentOrange : nil)

                Button(model.trl("btn_connect_help")) {
                    model.showConnectHelp = true
                }
                .controlSize(.small)

                if model.debug {
                    Button(model.trl("btn_read_piano_values")) {
                        model.onReadPianoValuesClicked()
                    }
                    .controlSize(.small)
                    .disabled(!model.isConnected || model.lastInputPort == nil)
                }
            }

            HStack(spacing: 8) {
                Text(model.trl("label_language"))
                Picker("", selection: Binding<Lang>(
                    get: { model.lang },
                    set: { model.setLanguage($0) }
                )) {
                    ForEach(Lang.allCases, id: \.self) { l in
                        Text(l == .en ? "English" : (l == .es ? "Español" : "中文"))
                            .tag(l)
                    }
                }
                .frame(width: 120)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBg)
    }
}

// MARK: - Piano Settings

private struct PianoSettingsView: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MasterVolumeSection(model: model)
                KeyTouchSection(model: model)
                MasterTuningSection(model: model)
                BrillianceSection(model: model)
                TransposeSection(model: model)
                AmbienceSection(model: model)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct MasterVolumeSection: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl("label_master_volume"))
                Spacer()
                Text("\(model.masterVolume)")
                    .foregroundColor(accentOrange).bold()
            }
            Slider(
                value: Binding(get: { Double(model.masterVolume) },
                               set: { model.masterVolume = Int($0) }),
                in: 0...100, step: 1,
                onEditingChanged: { editing in
                    if editing { model.scheduleMasterVolumeDebounced() }
                    else { model.sendMasterVolume() }
                }
            )
            ScaleRow(left: "0", right: "100")
        }
        .sectionStyle()
    }
}

private struct KeyTouchSection: View {
    @ObservedObject var model: ControllerModel

    private let labels: [String] = [
        "key_touch_fix", "key_touch_super_light", "key_touch_light",
        "key_touch_medium", "key_touch_heavy", "key_touch_super_heavy",
    ]

    var body: some View {
        HStack {
            Text(model.trl("label_key_touch"))
            Spacer()
            Picker("", selection: Binding(get: { model.keyTouch }, set: { model.keyTouch = $0; model.sendKeyTouch() })) {
                ForEach(0..<6, id: \.self) { i in Text(model.trl(labels[i])).tag(i) }
            }
            .frame(width: 140)
        }
        .sectionStyle()
    }
}

private struct MasterTuningSection: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl("label_master_tuning"))
                Spacer()
                Text(model.masterTuningHzDisplay)
                    .foregroundColor(accentOrange).bold()
            }
            Slider(
                value: Binding(get: { Double(model.masterTuningRaw) },
                               set: { model.masterTuningRaw = Int($0) }),
                in: Double(MASTER_TUNING_MIN_RAW)...Double(MASTER_TUNING_MAX_RAW),
                step: 1,
                onEditingChanged: { editing in
                    if !editing { model.sendMasterTuning() }
                }
            )
            ScaleRow(left: "415.3 Hz", center: "440 Hz", right: "466.2 Hz")
        }
        .sectionStyle()
    }
}

private struct BrillianceSection: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl("label_brilliance"))
                Spacer()
                Text("\(model.brilliance)")
                    .foregroundColor(accentOrange).bold()
            }
            Slider(
                value: Binding(get: { Double(model.brilliance) },
                               set: { model.brilliance = Int($0); model.sendBrilliance() }),
                in: -1...1, step: 1
            )
            ScaleRow(left: "-1", center: "0", right: "+1")
        }
        .sectionStyle()
    }
}

private struct TransposeSection: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl("label_transpose"))
                Spacer()
                Text("\(model.transposeSigned)")
                    .foregroundColor(accentOrange).bold()
            }
            Slider(
                value: Binding(get: { Double(model.transpose) },
                               set: { model.transpose = Int($0); model.sendTranspose() }),
                in: -24...24, step: 1
            )
            ScaleRow(left: "-24", center: "0", right: "+24")
        }
        .sectionStyle()
    }
}

private struct AmbienceSection: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl("label_ambience"))
                Spacer()
                Text("\(model.ambience)")
                    .foregroundColor(accentOrange).bold()
            }
            Slider(
                value: Binding(get: { Double(model.ambience) },
                               set: { model.ambience = Int($0); model.sendAmbience() }),
                in: 0...10, step: 1
            )
            ScaleRow(left: "0", center: "5", right: "10")
        }
        .sectionStyle()
    }
}

// MARK: - Tones

private struct TonesView: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Picker("", selection: Binding(get: { model.keyboardMode }, set: { mode in
                    model.keyboardMode = mode
                    model.sendKeyboardMode(mode)
                })) {
                    Text(model.trl("tone_mode_single")).tag(0)
                    Text(model.trl("tone_mode_split")).tag(1)
                    Text(model.trl("tone_mode_dual")).tag(2)
                    Text(model.trl("tone_mode_twin")).tag(3)
                }
                .pickerStyle(.segmented)

                switch model.keyboardMode {
                case 0: SinglePanel(model: model)
                case 1: SplitPanel(model: model)
                case 2: DualPanel(model: model)
                case 3: TwinPanel(model: model)
                default: EmptyView()
                }
            }
            .padding(12)
        }
    }
}

private struct TonePickerRow: View {
    @ObservedObject var model: ControllerModel
    let labelKey: String
    @Binding var categoryIdx: Int
    @Binding var toneIdx: Int
    var onToneChanged: ((Tone) -> Void)?

    private var tonesInCurrentCategory: [Tone] {
        guard CATEGORIES.indices.contains(categoryIdx) else { return [] }
        return toneCategories[CATEGORIES[categoryIdx]] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.trl(labelKey))
            HStack {
                Picker("", selection: $categoryIdx) {
                    ForEach(0..<CATEGORIES.count, id: \.self) { i in
                        Text(model.toneCategoryLabel(CATEGORIES[i])).tag(i)
                    }
                }
                .onChange(of: categoryIdx) { _ in
                    toneIdx = 0
                    if let t = tonesInCurrentCategory.first {
                        onToneChanged?(t)
                    }
                }
                Picker("", selection: Binding(get: { toneIdx }, set: { newIdx in
                    toneIdx = newIdx
                    if let t = tonesInCurrentCategory.indices.contains(newIdx) ? tonesInCurrentCategory[newIdx] : nil {
                        onToneChanged?(t)
                    }
                })) {
                    ForEach(0..<tonesInCurrentCategory.count, id: \.self) { i in
                        Text(tonesInCurrentCategory[i].name).tag(i)
                    }
                }
                .id(categoryIdx)
            }
        }
    }
}

private struct SinglePanel: View {
    @ObservedObject var model: ControllerModel
    var body: some View {
        VStack(spacing: 8) {
            TonePickerRow(model: model, labelKey: "label_tone",
                          categoryIdx: $model.singleCategory, toneIdx: $model.singleToneIdx,
                          onToneChanged: { model.sendToneSingle($0) })
        }
    }
}

private struct SplitPanel: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 8) {
            TonePickerRow(model: model, labelKey: "label_left_tone",
                          categoryIdx: $model.splitLeftCategory, toneIdx: $model.splitLeftToneIdx,
                          onToneChanged: { model.sendToneSplitLeft($0) })
            SectionDivider()
            TonePickerRow(model: model, labelKey: "label_right_tone",
                          categoryIdx: $model.splitRightCategory, toneIdx: $model.splitRightToneIdx,
                          onToneChanged: { model.sendToneSingle($0) })
            SectionDivider()
            BalanceRow(model: model, label: "label_balance", value: Binding(
                get: { model.splitBalance }, set: { model.splitBalance = $0; model.sendSplitBalance($0) }),
                left: splitBalanceDisplayLR(panelValue0to18: model.splitBalance).0,
                right: splitBalanceDisplayLR(panelValue0to18: model.splitBalance).1)
            SectionDivider()
            SplitPointRow(model: model)
            SectionDivider()
            ShiftRow(model: model, label: "label_right_shift", value: model.splitRightShift,
                     set: { model.splitRightShift = $0; model.sendSplitRightShift($0) })
            SectionDivider()
            ShiftRow(model: model, label: "label_left_shift", value: model.splitLeftShift,
                     set: { model.splitLeftShift = $0; model.sendSplitLeftShift($0) })
        }
    }
}

private struct DualPanel: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 8) {
            TonePickerRow(model: model, labelKey: "label_tone_1",
                          categoryIdx: $model.dual1Category, toneIdx: $model.dual1ToneIdx,
                          onToneChanged: { model.sendToneSingle($0) })
            SectionDivider()
            TonePickerRow(model: model, labelKey: "label_tone_2",
                          categoryIdx: $model.dual2Category, toneIdx: $model.dual2ToneIdx,
                          onToneChanged: { model.sendToneDualLayer($0) })
            SectionDivider()
            BalanceRow(model: model, label: "label_balance", value: Binding(
                get: { model.dualBalance }, set: { model.dualBalance = $0; model.sendDualBalance($0) }),
                left: dualBalanceDisplayLR(panelValue0to18: model.dualBalance).0,
                right: dualBalanceDisplayLR(panelValue0to18: model.dualBalance).1)
            SectionDivider()
            ShiftRow(model: model, label: "label_tone1_shift", value: model.dualShift1,
                     set: { model.dualShift1 = $0; model.sendDualShift1($0) })
            SectionDivider()
            ShiftRow(model: model, label: "label_tone2_shift", value: model.dualShift2,
                     set: { model.dualShift2 = $0; model.sendDualShift2($0) })
        }
    }
}

private struct TwinPanel: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(spacing: 8) {
            TonePickerRow(model: model, labelKey: "label_tone",
                          categoryIdx: $model.twinCategory, toneIdx: $model.twinToneIdx,
                          onToneChanged: { model.sendToneSingle($0) })
            SectionDivider()
            HStack {
                Text(model.trl("label_twin_mode"))
                Spacer()
                Picker("", selection: Binding(get: { model.twinMode }, set: {
                    model.twinMode = $0; model.sendTwinMode($0)
                })) {
                    Text(model.trl("twin_mode_pair")).tag(0)
                    Text(model.trl("twin_mode_individual")).tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct BalanceRow: View {
    @ObservedObject var model: ControllerModel
    let label: String
    let value: Binding<Int>
    let left: Int, right: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl(label))
                Spacer()
                Text("\(left):\(right)")
                    .foregroundColor(accentOrange).bold()
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                   in: 0...18, step: 1)
        }
    }
}

private struct SplitPointRow: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        HStack {
            Text(model.trl("label_split_point"))
            Spacer()
            Button("-") { model.decSplitPoint() }
                .buttonStyle(.bordered).controlSize(.small)
                .frame(width: 36)
            Text(midiNoteName(model.splitPointVal, model.lang))
                .foregroundColor(accentOrange).bold()
                .frame(minWidth: 40)
            Button("+") { model.incSplitPoint() }
                .buttonStyle(.bordered).controlSize(.small)
                .frame(width: 36)
        }
    }
}

private struct ShiftRow: View {
    @ObservedObject var model: ControllerModel
    let label: String
    let value: Int
    let set: (Int) -> Void

    var body: some View {
        HStack {
            Text(model.trl(label))
            Spacer()
            Button("-") { if value > -3 { set(value - 1) } }
                .buttonStyle(.bordered).controlSize(.small)
            Text("\(value)")
                .foregroundColor(accentOrange).bold()
                .frame(width: 24)
            Button("+") { if value < 3 { set(value + 1) } }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}

// MARK: - Metronome

private struct MetronomeView: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button(model.metronomeOn == true ? model.trl("btn_stop") : model.trl("btn_start")) {
                    model.sendMetronomeProbe()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.metronomeOn == true ? .red : accentOrange)
                .controlSize(.large)

                VStack(spacing: 4) {
                    HStack {
                        Text(model.trl("label_bpm"))
                        Spacer()
                        Text("\(model.tempo)")
                            .foregroundColor(accentOrange).bold()
                    }
                    Slider(value: Binding(get: { Double(model.tempo) }, set: { model.tempo = Int($0) }),
                           in: 10...500, step: 1,
                           onEditingChanged: { editing in
                        if !editing { model.flushTempo() }
                    })
                    ScaleRow(left: "10", center: "120", right: "500")
                }
                SectionDivider()

                VStack(spacing: 4) {
                    HStack {
                        Text(model.trl("label_metro_volume"))
                        Spacer()
                        Text("\(model.metroVolume)")
                            .foregroundColor(accentOrange).bold()
                    }
                    Slider(value: Binding(get: { Double(model.metroVolume) }, set: { model.metroVolume = Int($0); model.sendMetroVolume(Int($0)) }),
                           in: 0...10, step: 1)
                }
                SectionDivider()

                HStack {
                    Text(model.trl("label_metro_tone"))
                    Spacer()
                    Picker("", selection: Binding(get: { model.metroTone }, set: {
                        model.metroTone = $0; model.sendMetroTone($0)
                    })) {
                        Text(model.trl("metro_tone_click")).tag(0)
                        Text(model.trl("metro_tone_electronic")).tag(1)
                        Text(model.trl("metro_tone_japanese")).tag(2)
                        Text(model.trl("metro_tone_english")).tag(3)
                    }
                    .pickerStyle(.segmented)
                }
                SectionDivider()

                Text(model.trl("label_metro_pattern")).frame(maxWidth: .infinity, alignment: .leading)
                PatternGrid(model: model)
                SectionDivider()

                Text(model.trl("label_metro_beat")).frame(maxWidth: .infinity, alignment: .leading)
                BeatGrid(model: model)
            }
            .padding(12)
        }
    }
}

private struct PatternGrid: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: metroGridCols), spacing: 8) {
            ForEach(0..<8, id: \.self) { i in
                Button(action: { model.metroPattern = i; model.sendMetroPattern(i) }) {
                    if let g = metroPatternGlyphs[i] {
                        Text(g).font(.title3)
                    } else {
                        Text(model.trl("metro_pattern_0"))
                    }
                }
                .buttonStyle(BeatButtonStyle(active: model.metroPattern == i))
                .frame(minHeight: 34)
            }
        }
    }
}

private struct BeatGrid: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: metroGridCols), spacing: 8) {
            ForEach(0..<beatTable.count, id: \.self) { i in
                let b = beatTable[i]
                Button(action: { model.metroBeat = b.midiVal; model.sendMetroBeat(b.midiVal) }) {
                    Text(beatSigUnicode(b.num))
                        .font(.title3)
                }
                .buttonStyle(BeatButtonStyle(active: model.metroBeat == b.midiVal))
                .frame(minHeight: 34)
            }
        }
    }
}

private struct BeatButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(active ? accentOrange : surfaceBg)
            .foregroundColor(active ? .white : .gray)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

func beatSigUnicode(_ numerator: Int) -> String {
    let superD = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
    let subD = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
    let sup = numerator < superD.count ? superD[numerator] : "\(numerator)"
    return "\(sup)⁄\(subD[4])"
}

// MARK: - Piano Designer

private struct PianoDesignerView: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionHeader(model.trl("pd_section_cabinet"))
                SectionDivider()

                VStack(spacing: 4) {
                    HStack {
                        Text(model.trl("pd_label_lid"))
                        Spacer()
                        Text("\(model.pdLid)")
                            .foregroundColor(accentOrange).bold()
                    }
                    Slider(value: Binding(get: { Double(model.pdLid) }, set: { model.pdLid = Int($0); model.pdSendLid(Int($0)) }),
                           in: 0...6, step: 1)
                    ScaleRow(left: "0", right: "6")
                }
                .padding(.vertical, 8)

                SectionHeader(model.trl("pd_section_strings"))
                SectionDivider()
                ResonanceSlider(model: model, label: "pd_label_string_resonance",
                                value: Binding(get: { model.pdStringResonance }, set: { model.pdStringResonance = $0; model.pdSendStringRes($0) }))
                SectionHeader(model.trl("pd_section_damper"))
                SectionDivider()
                ResonanceSlider(model: model, label: "pd_label_damper_resonance",
                                value: Binding(get: { model.pdDamperResonance }, set: { model.pdDamperResonance = $0; model.pdSendDamperRes($0) }))
                SectionHeader(model.trl("pd_section_keyboard"))
                SectionDivider()
                ResonanceSlider(model: model, label: "pd_label_key_off_resonance",
                                value: Binding(get: { model.pdKeyOffResonance }, set: { model.pdKeyOffResonance = $0; model.pdSendKeyOff($0) }))

                SectionHeader(model.trl("pd_section_tuning"))
                SectionDivider()

                HStack {
                    Text(model.trl("pd_label_temperament"))
                    Spacer()
                    Picker("", selection: Binding(get: { model.pdTemperament }, set: { model.pdTemperament = $0; model.pdSendTemperament($0) })) {
                        ForEach(0..<10, id: \.self) { i in
                            Text(model.trl(temperamentI18nKeys[i])).tag(i)
                        }
                    }
                }
                .padding(.vertical, 8)
                SectionDivider()

                HStack {
                    Text(model.trl("pd_label_temperament_key"))
                    Spacer()
                    Picker("", selection: Binding(get: { model.pdTemperamentKey }, set: { model.pdTemperamentKey = $0; model.pdSendTemperamentKey($0) })) {
                        ForEach(0..<12, id: \.self) { i in
                            Text(model.lang == .es ? temperamentKeysEs[i] : (model.lang == .zh ? temperamentKeysZh[i] : temperamentKeysEn[i])).tag(i)
                        }
                    }
                }
                .padding(.vertical, 8)

                SectionHeader(model.trl("pd_section_note_voicing"))
                SectionDivider()

                VStack(spacing: 8) {
                    Picker(model.trl("inv_label_note"), selection: $model.invNoteIndex) {
                        ForEach(0..<invNoteCount, id: \.self) { i in
                            Text(midiNoteName(invNoteMidiBase + i, model.lang)).tag(i)
                        }
                    }

                    VStack(spacing: 4) {
                        HStack {
                            Text(model.trl("pd_label_single_note_tuning"))
                            Spacer()
                            Text(String(format: "%+.1f", Double(model.invTuning) / 10.0))
                                .foregroundColor(accentOrange).bold()
                        }
                        Slider(value: Binding(get: { Double(model.invTuning) }, set: { model.invTuning = Int($0) }),
                               in: -500...500, step: 1,
                               onEditingChanged: { editing in
                            if !editing { model.flushInvTuning() }
                        })
                        ScaleRow(left: "−50", center: "0", right: "+50")
                    }
                    SectionDivider()

                    VStack(spacing: 4) {
                        HStack {
                            Text(model.trl("pd_label_single_note_character"))
                            Spacer()
                            Text("\(model.invCharacter)")
                                .foregroundColor(accentOrange).bold()
                        }
                        Slider(value: Binding(get: { Double(model.invCharacter) }, set: { model.invCharacter = Int($0); model.onInvCharacterChanged(Int($0)) }),
                               in: -5...5, step: 1)
                        ScaleRow(left: "−5", center: "0", right: "+5")
                    }
                }
                .padding(.vertical, 8)

                Button(model.trl("pd_btn_save")) { model.pdSaveToPiano() }
                    .buttonStyle(.borderedProminent)
                    .tint(accentOrange)
                    .controlSize(.large)
                    .padding(.vertical, 10)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct ResonanceSlider: View {
    @ObservedObject var model: ControllerModel
    let label: String
    let value: Binding<Int>

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(model.trl(label))
                Spacer()
                Text(value.wrappedValue == 0 ? model.trl("label_off") : "\(value.wrappedValue)")
                    .foregroundColor(accentOrange).bold()
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                   in: 0...10, step: 1)
            HStack {
                Text(model.trl("label_off"))
                    .font(.caption2).foregroundColor(.gray)
                Spacer()
                Text("10")
                    .font(.caption2).foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Connect Help Dialog

struct ConnectHelpDialog: View {
    @ObservedObject var model: ControllerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.trl("help_connect_language"))
                Spacer()
                Picker("", selection: Binding<Lang>(get: { model.lang }, set: { model.setLanguage($0) })) {
                    Text(model.trl("help_connect_view_english")).tag(Lang.en)
                    Text(model.trl("help_connect_view_spanish")).tag(Lang.es)
                    Text(model.trl("help_connect_view_chinese")).tag(Lang.zh)
                }
            }

            ScrollView {
                Text(model.trl("help_connect_body"))
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 340)

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: kSettingConnectHelpSkipStartup) },
                set: { UserDefaults.standard.set($0, forKey: kSettingConnectHelpSkipStartup) }
            )) {
                Text(model.trl("help_connect_skip_startup"))
            }
            .toggleStyle(.switch)

            HStack {
                Spacer()
                Button(model.trl("help_connect_close")) { model.showConnectHelp = false }
                    .buttonStyle(.borderedProminent)
                    .tint(accentOrange)
            }
        }
        .padding(20)
        .frame(minWidth: 540)
    }
}

// MARK: - Helpers

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundColor(accentOrange)
            .font(.caption).bold()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

private struct SectionDivider: View {
    var body: some View {
        Divider().background(borderColor)
    }
}

private struct ScaleRow: View {
    let left: String, center: String?, right: String

    init(left: String, right: String) { self.left = left; self.center = nil; self.right = right }
    init(left: String, center: String, right: String) { self.left = left; self.center = center; self.right = right }

    var body: some View {
        HStack {
            Text(left).font(.caption2).foregroundColor(.gray)
            if let c = center {
                Spacer()
                Text(c).font(.caption2).foregroundColor(.gray)
            }
            Spacer()
            Text(right).font(.caption2).foregroundColor(.gray)
        }
    }
}

// MARK: - Extensions

extension ControllerModel {
    var transposeSigned: String { transpose != 0 ? "\(transpose > 0 ? "+" : "")\(transpose)" : "0" }

    func trl(_ key: String, _ args: CVarArg...) -> String {
        RolandFP30XController._tr(lang, key, args)
    }

    func toneCategoryLabel(_ cat: String) -> String {
        if let k = toneCategoryI18nKeys[cat] { return trl(k) }
        return cat
    }
}

private extension View {
    func sectionStyle() -> some View {
        VStack(spacing: 4) {
            self.padding(.vertical, 8)
            SectionDivider()
        }
    }
}
