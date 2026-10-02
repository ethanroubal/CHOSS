#if canImport(Supabase)
import SwiftUI

/// "Choose a new password", opened only by the link in a password-reset email (the link signs
/// you in, proving you own the email). Saving sets the new password and carries on into the
/// app; Cancel signs out without changing anything.
struct ResetPasswordView: View {
    @Bindable var session: SupabaseSession

    @State private var password = ""
    @State private var confirmation = ""
    @State private var problem: String?
    @State private var isDone = false
    @FocusState private var focused: Bool

    /// Supabase's default minimum password length.
    private let minimumPassword = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: isDone ? "checkmark.shield.fill" : "lock.rotation")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .padding(.top, 32)

                    if isDone {
                        Text("Password changed").font(.title2.bold())
                        Text("You're signed in with your new password.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            Text("Choose a new password").font(.title2.bold())
                            if let email = session.email {
                                Text("for \(email)").foregroundStyle(.secondary)
                            }
                        }

                        VStack(spacing: 12) {
                            SecureField("New password (\(minimumPassword)+ characters)", text: $password)
                                .textContentType(.newPassword)
                                .focused($focused)
                                .padding(12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            SecureField("Confirm new password", text: $confirmation)
                                .textContentType(.newPassword)
                                .focused($focused)
                                .padding(12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                .onSubmit(save)
                        }

                        Button(action: save) {
                            Group {
                                if session.isWorking {
                                    ProgressView().tint(Brand.onAccent)
                                } else {
                                    Text("Save new password").bold().foregroundStyle(Brand.onAccent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isWorking)

                        if let message = problem ?? session.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isDone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            Task { await session.cancelPasswordReset() }
                        }
                    }
                }
            }
            .onAppear { focused = true }
        }
        // Can't be swiped away: it's done or cancelled.
        .interactiveDismissDisabled()
    }

    private func save() {
        focused = false
        problem = nil
        session.errorMessage = nil
        if password.count < minimumPassword {
            problem = "Use at least \(minimumPassword) characters."
            return
        }
        if password != confirmation {
            problem = "The two passwords don't match."
            return
        }
        Task {
            guard await session.setNewPassword(password) else { return }
            // Show "Password changed" for a moment, then carry on into the app.
            withAnimation { isDone = true }
            try? await Task.sleep(for: .seconds(1.5))
            session.finishPasswordReset()
        }
    }
}
#endif
