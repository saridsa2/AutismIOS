import SwiftUI

@main struct VoiceLabApp: App {
    @StateObject private var lab = LabStore()
    var body: some Scene { WindowGroup { VoiceLabView().environmentObject(lab) } }
}
struct VoiceLabView: View {
    @EnvironmentObject var lab: LabStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var email = ""
    @State private var password = ""
    @State private var deletion: LabSample?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("On-device speaker enrollment",systemImage:"waveform.circle.fill").font(.title3.bold())
                    Text("Record three samples of one speaker, then test with a fresh recording. Matching is experimental and may return Unknown.")
                    Toggle("I have permission to record this speaker",isOn:$lab.consent)
                        .onChange(of:lab.consent) { _,allowed in if !allowed { lab.cancelRecording() } }
                }
                Section("Speakers") {
                    HStack { TextField("Speaker name",text:$lab.profileName); Button("Add") { lab.addProfile() }.disabled(lab.profileName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
                    if !lab.profiles.isEmpty {
                        Picker("Selected speaker",selection:$lab.selectedProfile) {
                            ForEach(lab.profiles) { p in Text("\(p.name) · \(p.embeddings.count) samples\(p.ready ? " · Ready" : " · Need 3")").tag(Optional(p.id)) }
                        }
                    }
                }.disabled(lab.recording || lab.processing || lab.busy)
                Section("Record & compare") {
                    if lab.recording {
                        ProgressView(value:lab.elapsed,total:10)
                        Text("Recording · \(Int(lab.elapsed)) / 10 seconds").monospacedDigit()
                        ProgressView(value:Double(lab.level)).tint(.orange).accessibilityLabel("Microphone level")
                        Button("Cancel recording",role:.destructive) { lab.cancelRecording() }
                    } else {
                        Button { Task { await lab.startRecording(kind:"enrollment") } } label: { Label("Record enrollment sample",systemImage:"mic.fill") }
                            .disabled(!lab.consent || !lab.modelReady || lab.selectedProfile == nil || lab.processing || lab.busy)
                        Button { Task { await lab.startRecording(kind:"test") } } label: { Label("Test speaker recognition",systemImage:"person.wave.2") }
                            .disabled(!lab.consent || !lab.modelReady || !lab.profiles.contains(where: \.ready) || lab.processing || lab.busy)
                    }
                    if lab.processing { ProgressView("Processing locally…") }
                    Text(lab.status).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("lab.status")
                }
                Section("Samples & timing") {
                    if lab.samples.isEmpty { Text("No recordings yet.").foregroundStyle(.secondary) }
                    ForEach(lab.samples.reversed()) { sample in
                        VStack(alignment:.leading,spacing:6) {
                            HStack { Text(sample.label).bold(); Spacer(); Text(sample.kind.capitalized).font(.caption) }
                            Text("\(Int(sample.durationMs)) ms capture · \(Int(sample.inferenceMs)) ms processing").font(.caption).monospacedDigit()
                            if let upload = sample.uploadMs { Text("\(Int(upload)) ms upload · uploaded").font(.caption) }
                            else { Text("On this device").font(.caption).foregroundStyle(.secondary) }
                            Button("Delete sample",role:.destructive) { deletion = sample }.font(.caption)
                        }
                    }
                }.disabled(lab.recording || lab.processing || lab.busy)
                Section("Remote sync") {
                    if let account = lab.account {
                        Text(account.user.email)
                        Toggle("Upload samples and fingerprints to my account",isOn:$lab.uploadConsent)
                        Text("Uploads include microphone audio, speaker name, fingerprint and processing timings. Remote retention: 30 days. Recording never starts automatically.").font(.footnote).foregroundStyle(.secondary)
                        Button("Upload pending samples") { Task { await lab.uploadPending() } }.disabled(!lab.uploadConsent || lab.samples.allSatisfy{$0.uploadedOwner != nil})
                        Button("Sign out") { Task { await lab.signOut() } }
                    } else {
                        TextField("Account email",text:$email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password",text:$password).textContentType(.password)
                        Button("Sign in for remote sync") { let secret = password; password = ""; Task { await lab.login(email:email,password:secret) } }.disabled(email.isEmpty || password.isEmpty)
                        Text("Use an existing Little Company account. Enrollment and matching work without signing in.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if lab.busy { ProgressView() }
                }.disabled(lab.busy || lab.recording || lab.processing)
                Section("Matching") {
                    LabeledContent("Similarity threshold",value:String(format:"%.2f",lab.threshold))
                    Slider(value:$lab.threshold,in:0.5...0.95,step:0.01)
                    Text("Similarity is not a probability. This threshold is uncalibrated; test known and unknown speakers in your environment. This prototype does not authenticate users.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Model") {
                    Text("WeSpeaker / pyannote Community-1 · 256-dimensional embeddings. Modified Core ML conversions by Fluid Inference. Attribution: pyannote, WeSpeaker and BUT Speech@FIT.").font(.footnote)
                    Link("Model attribution · CC BY 4.0",destination:URL(string:"https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/df2625ac79a7ac6b65ad868fee6d80f320da4232/NOTICE.md")!)
                }
            }
            .navigationTitle("Voice Lab")
            .task { await lab.prepare() }
            .onChange(of:scenePhase) { _,phase in if phase != .active { lab.cancelRecording() } }
            .alert("Delete this voice sample?",isPresented:Binding(get:{deletion != nil},set:{if !$0 { deletion = nil }})) {
                Button("Delete",role:.destructive) { if let sample = deletion { Task { await lab.deleteSample(sample) } }; deletion = nil }
                Button("Cancel",role:.cancel) { deletion = nil }
            } message: { Text("This deletes the local recording and fingerprint, plus the uploaded copy if present.") }
        }.tint(Color(red:0.2,green:0.45,blue:0.4))
    }
}
