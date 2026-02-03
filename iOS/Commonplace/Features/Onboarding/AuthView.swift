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
                    case .failure:
                        break
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

    enum AuthMode: String, CaseIterable {
        case otp = "Email Code"
        case password = "Password"
    }

    @State private var email = ""
    @State private var password = ""
    @State private var otpCode = ""
    @State private var authMode: AuthMode = .otp
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var otpSent = false
    @State private var resendCooldown = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: CPSpacing.lg) {
                // Toggle between OTP / Password
                Picker("Mode", selection: $authMode) {
                    ForEach(AuthMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, CPSpacing.lg)
                .onChange(of: authMode) { _, _ in
                    // Reset state when switching modes
                    otpSent = false
                    otpCode = ""
                    errorMessage = nil
                }

                if authMode == .otp {
                    otpAuthView
                } else {
                    passwordAuthView
                }

                Spacer()
            }
            .padding(.horizontal, CPSpacing.screenHorizontal)
            .navigationTitle("Sign In")
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

    // MARK: - OTP Auth View

    private var otpAuthView: some View {
        VStack(spacing: CPSpacing.lg) {
            if !otpSent {
                // Step 1: Enter email
                Text("Sign in with email code")
                    .font(.cpTitle2)
                    .padding(.top, CPSpacing.md)

                Text("We'll send a 6-digit code to your email")
                    .font(.cpBody)
                    .foregroundColor(.cpTextSecondary)
                    .multilineTextAlignment(.center)

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

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.cpSubhead)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Send OTP button
                Button {
                    Task { await sendOTP() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Send Code")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isEmailValid ? Color.cpTint : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }
                .disabled(!isEmailValid || isLoading)

            } else {
                // Step 2: Enter OTP code
                Text("Enter verification code")
                    .font(.cpTitle2)
                    .padding(.top, CPSpacing.md)

                Text("Sent to \(email)")
                    .font(.cpBody)
                    .foregroundColor(.cpTextSecondary)

                // OTP code field
                VStack(alignment: .leading, spacing: CPSpacing.xs) {
                    Text("6-digit code")
                        .font(.cpSubhead)
                        .foregroundColor(.cpTextSecondary)

                    TextField("000000", text: $otpCode)
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(CPSpacing.cornerRadiusMedium)
                        .onChange(of: otpCode) { _, newValue in
                            // Limit to 6 digits
                            otpCode = String(newValue.filter { $0.isNumber }.prefix(6))
                        }
                }

                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.cpSubhead)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Verify button
                Button {
                    Task { await verifyOTP() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Verify")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(otpCode.count == 6 ? Color.cpTint : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(CPSpacing.cornerRadiusMedium)
                }
                .disabled(otpCode.count != 6 || isLoading)

                // Resend / Change email
                HStack(spacing: CPSpacing.md) {
                    Button {
                        otpSent = false
                        otpCode = ""
                        errorMessage = nil
                    } label: {
                        Text("Change email")
                            .font(.cpSubhead)
                            .foregroundColor(.cpTextSecondary)
                    }

                    Spacer()

                    if resendCooldown > 0 {
                        Text("Resend in \(resendCooldown)s")
                            .font(.cpSubhead)
                            .foregroundColor(.cpTextTertiary)
                    } else {
                        Button {
                            Task { await sendOTP() }
                        } label: {
                            Text("Resend code")
                                .font(.cpSubhead)
                                .foregroundColor(.cpTint)
                        }
                        .disabled(isLoading)
                    }
                }
                .padding(.top, CPSpacing.sm)
            }
        }
    }

    // MARK: - Password Auth View

    private var passwordAuthView: some View {
        VStack(spacing: CPSpacing.lg) {
            // Toggle between Sign In / Sign Up
            Picker("Mode", selection: $isSignUp) {
                Text("Sign In").tag(false)
                Text("Create Account").tag(true)
            }
            .pickerStyle(.segmented)

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

                SecureField("Enter password", text: $password)
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
                Task { await authenticateWithPassword() }
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
                .background(isPasswordValid ? Color.cpTint : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(CPSpacing.cornerRadiusMedium)
            }
            .disabled(!isPasswordValid || isLoading)
        }
    }

    // MARK: - Validation

    private var isEmailValid: Bool {
        !email.isEmpty && email.contains("@") && email.contains(".")
    }

    private var isPasswordValid: Bool {
        !email.isEmpty && email.contains("@") && password.count >= 6
    }

    // MARK: - Actions

    private func sendOTP() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.sendOTP(email: email)
            otpSent = true
            startResendCooldown()
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func verifyOTP() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.verifyOTP(email: email, token: otpCode)
            dismiss()
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            if case .otpExpired = error {
                // Allow resend immediately if expired
                resendCooldown = 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func authenticateWithPassword() async {
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
            if case .userAlreadyExists = error {
                isSignUp = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func startResendCooldown() {
        resendCooldown = 60
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    resendCooldown -= 1
                }
            }
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthService.shared)
}
