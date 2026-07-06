import SwiftUI
import RolandMIDI

@main
struct RolandFP30XControllerApp: App {
    @StateObject private var model = ControllerModel()
    @AppStorage(kSettingConnectHelpSkipStartup) private var connectHelpSkipStartup = false

    var body: some Scene {
        WindowGroup {
            MainContentView(model: model)
                .frame(minWidth: 560, minHeight: 580)
                .accentColor(accentOrange)
                .sheet(isPresented: $model.showConnectHelp) {
                    ConnectHelpDialog(model: model)
                }
                .onAppear {
                    if !connectHelpSkipStartup {
                        model.showConnectHelp = true
                    }
                    model.refreshPorts()
                }
                .alert(loc("pd_warning_title"),
                       isPresented: $model.showPdWarning) {
                    Button(loc("dlg_yes")) {
                        if model.keyboardMode != 0 {
                            model.keyboardMode = 0
                            model.sendKeyboardMode(0)
                        }
                        model.setPdWarningShown()
                    }
                    Button(loc("dlg_no"), role: .cancel) {}
                    Button(loc("pd_warning_dont_show")) { model.setPdWarningShown() }
                } message: {
                    Text(loc("pd_warning_text"))
                }
        }
    }
}
