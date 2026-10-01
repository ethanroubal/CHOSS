#if canImport(Supabase)
import SwiftUI
import AuthenticationServices

/// First screen when signed out: Sign in with Apple, or email and password.
struct SignInView: View {
    @Bindable var session: SupabaseSession
    @Environment(\.colorScheme) private var colorScheme

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: Self { self }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var nonce = ""
    @State private var notice: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    HoldMarkView(size: 64).foregroundStyle(.tint)
                    WordmarkView(height: 36)
                    Text("Share your sends. Find the beta.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                SignInWithAppleButton(mode == .signIn ? .signIn : .signUp) { request in
                    let made = session.makeNonce()
                    nonce = made.raw
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = made.hashed
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)

                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or").font(.footnote).foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }

                VStack(spacing: 12) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    SecureField("Password (8+ characters)", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focused)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    Button(action: submitEmail) {
                        Group {
                            if session.isWorking {
                                ProgressView()
                            } else {
                                Text(mode.rawValue).bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Brand.onAccent)
                    .disabled(!canSubmit || session.isWorking)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            Task {
                                await session.sendPasswordReset(email: email)
                                if session.errorMessage == nil { notice = "Check your email for a reset link." }
                            }
                        }
                        .font(.footnote)
                        .disabled(email.isEmpty || session.isWorking)
                    }
                }

                if let message = session.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if let notice {
                    Label(notice, systemImage: "envelope.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if session.environment == .test {
                    Text("Connected to the test server")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: mode) { _, _ in
            session.errorMessage = nil
            notice = nil
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 8
    }

    private func submitEmail() {
        focused = false
        notice = nil
        Task {
            switch mode {
            case .signIn:
                await session.signIn(email: email, password: password)
            case .signUp:
                let signedIn = await session.signUp(email: email, password: password)
                if !signedIn && session.errorMessage == nil {
                    notice = "Almost there: tap the link we emailed to \(email), then sign in."
                    mode = .signIn
                }
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                session.errorMessage = "Apple didn't return a sign-in token. Try again."
                return
            }
            Task { await session.signInWithApple(idToken: token, rawNonce: nonce) }
        case .failure(let error):
            // Cancelling isn't an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                session.errorMessage = error.localizedDescription
            }
        }
    }
}
#endif
