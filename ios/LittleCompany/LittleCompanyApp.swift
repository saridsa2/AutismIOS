import SwiftUI
import LocalAuthentication

@main
struct LittleCompanyApp: App {
    @StateObject private var companion = Companion()
    var body: some Scene {
        WindowGroup { CompanionView().environmentObject(companion) }
    }
}

struct CompanionView: View {
    @EnvironmentObject var model: Companion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false
    @State private var gateError = ""
    private var ink: Color { colorScheme == .dark ? Color(red: 0.84, green: 0.91, blue: 0.87) : Color(red: 0.20, green: 0.32, blue: 0.28) }
    private let sage = Color(red: 0.42, green: 0.58, blue: 0.50)
    private var motionEnabled: Bool {
        model.animateSpeech && !model.reduceMotion && !systemReduceMotion && scenePhase == .active
    }
    private var activity: String {
        if model.connected { return model.paused ? "Taking a break" : (model.speaking ? "Speaking" : "Listening") }
        return model.connectionLabel.lowercased().capitalized
    }
    var body: some View {
        NavigationStack {
            companionContent
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showSettings) { CaregiverView().environmentObject(model) }
        }
    }
    private var companionContent: some View {
        GeometryReader { geometry in
            leaf
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(1.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background((colorScheme == .dark ? Color(red: 0.10, green: 0.15, blue: 0.13) : Color(red: 0.91, green: 0.94, blue: 0.92)).ignoresSafeArea())
        .overlay(alignment: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { activityLabel; Spacer(minLength: 12); caregiverButton }
                VStack(spacing: 12) { activityLabel; caregiverButton }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .foregroundStyle(ink)
        }
        .statusBarHidden(UIDevice.current.userInterfaceIdiom == .pad)
        .alert("Caregiver access", isPresented: Binding(get: { !gateError.isEmpty }, set: { if !$0 { gateError = "" } })) {
            Button("OK") { gateError = "" }
        } message: { Text(gateError) }
        .task { UIApplication.shared.isIdleTimerDisabled = true; if !model.signedIn { showSettings = true }; await model.start() }
    }
    private var activityLabel: some View {
        Label(activity, systemImage: model.paused ? "pause" : (model.speaking ? "speaker.wave.2" : "mic"))
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .accessibilityLabel("Connection: \(activity)")
    }
    private var caregiverLabel: some View {
        Label("Grown-ups", systemImage: "lock")
            .font(.system(.body, design: .rounded, weight: .medium))
            .padding(.horizontal, 8).frame(minHeight: 44)
    }
    @ViewBuilder private var caregiverButton: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Button { Task { await openCaregiver() } } label: { caregiverLabel }
                .buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            Button { Task { await openCaregiver() } } label: { caregiverLabel }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .tint(ink)
        }
    }
    private var leaf: some View {
        SoboAnimation(speaking: model.connected && !model.paused && model.speaking, motionEnabled: motionEnabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A friendly green companion. \(activity).")
    }
    func openCaregiver() async {
        if !model.signedIn { showSettings = true; return }
        #if targetEnvironment(simulator)
        showSettings = true; return
        #else
        let context = LAContext()
        do { if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open caregiver settings") { showSettings = true } }
        catch { gateError = "Use the device passcode or biometrics to open settings. \(error.localizedDescription)" }
        #endif
    }
}

struct CaregiverView: View {
    @EnvironmentObject var model: Companion
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    var body: some View {
            Form {
                if !model.signedIn {
                    SignInView()
                } else {
                Section("Your account") {
                    Label(model.account?.user.email ?? "", systemImage: "person.crop.circle")
                    if let info = model.accountInfo {
                        Text("\(info.devices.count) devices used · \(info.sessionCount) voice sessions requested")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Sign out of this device", role: .destructive) { Task { await model.signOut() } }.disabled(model.authBusy)
                }
                Section("Conversation") {
                    Toggle(isOn: Binding(get: { model.wantsConnection }, set: { enabled in
                        Task { if enabled { await model.connect() } else { await model.stop() } }
                    })) {
                        Label("Voice connection", systemImage: "waveform")
                    }.disabled(model.connecting).accessibilityIdentifier("conversation.connection")
                    if model.connecting { ProgressView("Connecting…") }
                    Button { Task { await model.togglePause() } } label: {
                        Label(model.paused ? "Resume listening" : "Pause listening", systemImage: model.paused ? "mic" : "mic.slash")
                    }.disabled(!model.connected || model.connecting)
                    Text(model.detail).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Comfort & music") {
                    Toggle("Animate companion", isOn: $model.animateSpeech).onChange(of: model.animateSpeech) { _, _ in model.save() }
                    Text("Gentle movement while listening and a talking animation during speech. Reduce Motion turns all animation off.").font(.footnote)
                    Toggle("Reduce motion", isOn: $model.reduceMotion).onChange(of: model.reduceMotion) { _, _ in model.save() }
                    Button("Connect Apple Music") { Task { await model.authorizeMusic() } }
                    Text("Authorize music here before starting kiosk mode. Your child can then ask for songs entirely by voice.").font(.footnote)
                }
                Section("Artwork") {
                    Link("Sobo by Patgrivet", destination: URL(string: "https://rive.app/marketplace/28761-54484-sobo/")!)
                    Link("Creative Commons Attribution 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Text("Original artwork used with custom playback for Little Company.").font(.footnote)
                }
                Section("Family context") {
                    TextField("Child’s preferred name", text: $model.childName).textContentType(.givenName)
                    Button("Load saved context") { Task { await model.loadProfile() } }
                    Text("Today's plans").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.today).frame(minHeight: 70)
                    Text("People, places & preferences").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.context).frame(minHeight: 130)
                    Button("Save context") { Task { await model.saveProfile() } }
                    Text("Changes take effect after reconnecting. Only enter plans that are actually current.").font(.footnote)
                }
                }
                Section("Kiosk") {
                    Button { openURL(URL(string: UIApplication.openSettingsURLString)!) } label: {
                        Label("Open Settings", systemImage: "accessibility")
                    }
                    Text("In Settings, go to Accessibility → Guided Access. Turn it on, return to this app, then triple-click the top or Home button to start.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !model.settingsMessage.isEmpty { Section { Text(model.settingsMessage).foregroundStyle(.secondary) } }
            }
            .navigationTitle("Grown-up corner")
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { if model.signedIn { await model.loadAccount() } }
    }
}
