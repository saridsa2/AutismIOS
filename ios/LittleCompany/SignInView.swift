import SwiftUI

struct SignInView: View {
    @EnvironmentObject var model: Companion
    @State private var mode = Mode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    enum Mode { case signIn, signUp, verify, recover, reset }
    private var title: String {
        switch mode {
        case .signIn: return "Welcome back"
        case .signUp: return "A space for your family"
        case .verify: return "Check your email"
        case .recover: return "Forgot your password?"
        case .reset: return "A fresh start"
        }
    }
    private var action: String {
        switch mode {
        case .signIn: return "Sign in"
        case .signUp: return "Create account"
        case .verify: return "Verify email"
        case .recover: return "Send recovery code"
        case .reset: return "Save new password"
        }
    }
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Just for grown-ups", systemImage: "leaf")
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                Text(title).font(.system(.title2, design: .rounded, weight: .semibold))
                Text(mode == .verify || mode == .reset ? "Enter the code sent to \(email). You can also check your spam folder." : "Sign in once. Your family’s preferences stay with you on iPhone and iPad.")
                    .font(.body).foregroundStyle(.secondary)
            }.padding(.vertical, 12)
            if mode != .reset {
                TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("account.email")
            }
            if mode == .verify || mode == .reset {
                TextField("Email code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                    .accessibilityIdentifier("account.code")
            }
            if mode == .signIn || mode == .signUp || mode == .reset {
                SecureField(mode == .reset ? "New password" : "Password", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword).accessibilityIdentifier("account.password")
                if mode != .signIn { Text("Use at least 10 characters.").font(.caption).foregroundStyle(.secondary) }
            }
            Button { Task { await submit() } } label: {
                HStack { Text(action); Spacer(); if model.authBusy { ProgressView() } }
            }.disabled(model.authBusy || email.isEmpty).accessibilityIdentifier("account.submit")
            if !model.authMessage.isEmpty { Text(model.authMessage).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("account.message") }
        }
        Section {
            if mode == .signIn {
                Button("Create a family account") { change(.signUp) }
                Button("Forgot password?") { change(.recover) }
                Button("Verify my email") { change(.verify) }
            } else {
                if mode == .verify {
                    Button("Send a new code") { Task { _ = await model.authenticate("resend", email: email) } }.disabled(model.authBusy || email.isEmpty)
                }
                Button("Back to sign in") { change(.signIn) }.disabled(model.authBusy)
            }
        }.disabled(model.authBusy)
    }
    private func change(_ next: Mode) {
        mode = next; password = ""; code = ""; model.authMessage = ""
    }
    private func submit() async {
        let route: String
        switch mode {
        case .signIn: route = "sign-in"
        case .signUp: route = "sign-up"
        case .verify: route = "verify"
        case .recover: route = "recover"
        case .reset: route = "reset"
        }
        let success = await model.authenticate(route, email: email, password: password, code: code)
        guard success else { return }
        password = ""; code = ""
        if mode == .signUp { mode = .verify }
        else if mode == .recover { mode = .reset }
    }
}
