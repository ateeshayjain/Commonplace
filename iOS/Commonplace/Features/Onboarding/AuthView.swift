import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showingEmailAuth = false
    @State private var showOnboarding = true

    var body: some View {
        if showOnboarding {
            OnboardingView(isComplete: $showOnboarding)
        } else {
            mainAuthView
        }
    }

    private var mainAuthView: some View {
        VStack(spacing: CPSpacing.xxl) {
            Spacer()

            // Logo & Title
            VStack(spacing: CPSpacing.md) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.cpTint)

                Text("Commonplace")
                    .font(.cpLargeTitle)

                Text("Your personal knowledge library")
                    .font(.cpBody)
                    .foregroundColor(.cpTextSecondary)
            }

            Spacer()

            // Auth Options
            VStack(spacing: CPSpacing.md) {
                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    switch result {
                    case .success:
                        authService.signInWithApple()
                    case .failure(let error):
                        print("Apple Sign In failed: \(error)")
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(CPSpacing.cornerRadiusMedium)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.cpSeparator)
                        .frame(height: 1)

                    Text("or")
                        .font(.cpFootnote)
                        .foregroundColor(.cpTextSecondary)
                        .padding(.horizontal, CPSpacing.sm)

                    Rectangle()
                        .fill(Color.cpSeparator)
                        .frame(height: 1)
                }

                // Email + Password
                Button {
                    showingEmailAuth = true
                } label: {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Continue with Email")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemGray5))
                    .foregroundColor(.cpText)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }

                // Demo mode (for testing)
                Button {
                    authService.signInDemo()
                } label: {
                    Text("Try Demo Mode")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)
                }
                .padding(.top, CPSpacing.xs)
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)

            Spacer()

            // Terms
            Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                .font(.cpCaption1)
                .foregroundColor(.cpTextTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CPSpacing.xl)
                .padding(.bottom, CPSpacing.lg)
        }
        .sheet(isPresented: $showingEmailAuth) {
            EmailAuthSheet()
        }
        .alert("Error", isPresented: .init(
            get: { authService.error != nil },
            set: { if !$0 { authService.error = nil } }
        )) {
            Button("OK") { authService.error = nil }
        } message: {
            Text(authService.error?.localizedDescription ?? "An error occurred")
        }
    }
}

// MARK: - Email Auth Sheet

struct EmailAuthSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: CPSpacing.lg) {
                // Toggle between Sign In / Sign Up
                Picker("Mode", selection: $isSignUp) {
                    Text("Sign In").tag(false)
                    Text("Create Account").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.top, CPSpacing.lg)

                Text(isSignUp ? "Create your account" : "Welcome back!")
                    .font(.cpTitle2)
                    .padding(.top, CPSpacing.md)

                // Email field
                VStack(alignment: .leading, spacing: CPSpacing.xs) {
                    Text("Email")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)

                    TextField("you@example.com", text: $email)
                        .font(.cpBody)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(CPSpacing.cornerRadiusMedium)
                }

                // Password field
                VStack(alignment: .leading, spacing: CPSpacing.xs) {
                    Text("Password")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)

                    SecureField("••••••••", text: $password)
                        .font(.cpBody)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(CPSpacing.cornerRadiusMedium)
                }

                if isSignUp {
                    Text("Password must be at least 6 characters")
                        .font(.cpCaption1)
                        .foregroundColor(.cpTextTertiary)
                }

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.cpSubhead)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Submit button
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isSignUp ? "Create Account" : "Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isValid ? Color.cpTint : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }
                .disabled(!isValid || isLoading)

                Spacer()
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .navigationTitle(isSignUp ? "Create Account" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6
    }

    private func authenticate() async {
        isLoading = true
        errorMessage = nil

        do {
            if isSignUp {
                try await authService.signUp(email: email, password: password)
            } else {
                try await authService.signIn(email: email, password: password)
            }
            dismiss()
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            // If user exists, suggest signing in
            if case .userAlreadyExists = error {
                isSignUp = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthService.shared)
}
