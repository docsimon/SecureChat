//
//  OTPVerificationView.swift
//  SecureChat
//
//  Created by Simone Barbara on 19/08/2026.
//
//
//  Requires iOS 17+ (two-parameter `onChange`, `#Preview`).
//



import SwiftUI

// MARK: - View Model Contract

/// Conform your own view model to this. The view owns no business logic:
/// it only reads state and calls `verify()` / `resend()`.
@MainActor
protocol OTPVerificationViewModel: ObservableObject {
    /// Two-way bound to the field. Already sanitised by the view (digits only, max `codeLength`).
    var code: String { get set }

    /// Shown in the subtitle, e.g. "+44 7700 900123". Formatted for display.
    var phoneNumber: String { get }

    /// Number of digits expected. Defaults to 6.
    var codeLength: Int { get }

    /// Drives the activity indicator inside the primary button.
    var isVerifying: Bool { get }

    /// Drives the small spinner next to the resend button.
    var isResending: Bool { get }

    /// Seconds left before another code can be requested. `0` means resend is available.
    var resendCooldown: Int { get }

    /// Non-nil renders the inline error and puts the field in its error state.
    var errorMessage: String? { get }

    func verify() async throws -> Date
    func resend() async
}

extension OTPVerificationViewModel {
    var codeLength: Int { 6 }
    var isCodeComplete: Bool { code.count == codeLength }
    var canResend: Bool { resendCooldown == 0 && !isResending && !isVerifying }
}

// MARK: - Screen

struct OTPVerificationView<ViewModel: OTPVerificationViewModel>: View {
    @ObservedObject var viewModel: ViewModel

    /// Pop back to the phone-number screen. Navigation stays out of the view model.
    var onChangePhoneNumber: () async throws -> Void
    var onContinue: (Date) async throws -> Void

    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            OTPCodeField(
                code: $viewModel.code,
                isFocused: $isCodeFieldFocused,
                length: viewModel.codeLength,
                hasError: viewModel.errorMessage != nil
            )
            .disabled(viewModel.isVerifying)
            .padding(.top, 32)

            errorLabel
                .padding(.top, 12)

            verifyButton
                .padding(.top, 24)

            resendButton
                .padding(.top, 20)

            Spacer(minLength: 24)

            changePhoneNumberButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isVerifying)
        .onChange(of: viewModel.code) { _, newValue in
            // Auto-submit once the last digit lands (also covers SMS autofill).
            guard newValue.count == viewModel.codeLength, !viewModel.isVerifying else { return }
            submit()
        }
        .task {
            isCodeFieldFocused = true
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 8) {
            Text("Verify your number")
                .font(.title2.bold())

            Text("Enter the \(viewModel.codeLength)-digit code we sent to \(viewModel.phoneNumber).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var verifyButton: some View {
        Button(action: submit) {
            ZStack {
                Text("Verify")
                    .fontWeight(.semibold)
                    .opacity(viewModel.isVerifying ? 0 : 1)

                if viewModel.isVerifying {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.isCodeComplete || viewModel.isVerifying)
        .accessibilityLabel(viewModel.isVerifying ? "Verifying" : "Verify")
    }

    private var resendButton: some View {
        Button {
            Task { await viewModel.resend() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isResending {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(resendTitle)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        .disabled(!viewModel.canResend)
    }

    private var resendTitle: String {
        if viewModel.isResending { return "Sending a new code…" }
        if viewModel.resendCooldown > 0 { return "Resend code in \(viewModel.resendCooldown)s" }
        return "Resend code"
    }

    private var changePhoneNumberButton: some View {
        Button {
            isCodeFieldFocused = false
            Task {
               try await onChangePhoneNumber()
            }
        } label: {
            Text("Wrong number? Change it")
                .font(.subheadline)
        }
        .disabled(viewModel.isVerifying)
    }

    // MARK: Actions

    private func submit() {
        isCodeFieldFocused = false
        Task {
            let otpDate = try await viewModel.verify()
            try await onContinue(otpDate)
        }
    }
}

// MARK: - Code Field

/// A hidden `TextField` under a row of digit boxes, so we get real keyboard
/// behaviour, paste and `.oneTimeCode` autofill while drawing a custom UI.
struct OTPCodeField: View {
    @Binding var code: String
    @FocusState.Binding var isFocused: Bool

    var length: Int = 6
    var hasError: Bool = false

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.001) // Invisible but still hit-testable and focusable.

            HStack(spacing: 10) {
                ForEach(0..<length, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onChange(of: code) { _, newValue in
            let sanitised = String(newValue.filter(\.isNumber).prefix(length))
            if sanitised != newValue { code = sanitised }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verification code")
        .accessibilityValue(code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " "))
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private func digitBox(at index: Int) -> some View {
        let digits = Array(code)
        let digit = index < digits.count ? String(digits[index]) : ""
        let isCursor = isFocused && index == min(digits.count, length - 1)

        return Text(digit)
            .font(.title2.weight(.semibold).monospacedDigit())
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor(isCursor: isCursor), lineWidth: isCursor || hasError ? 2 : 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isCursor)
    }

    private func borderColor(isCursor: Bool) -> Color {
        if hasError { return .red }
        if isCursor { return .accentColor }
        return Color(.separator)
    }
}

// MARK: - Preview

//@MainActor
//private final class PreviewOTPViewModel: OTPVerificationViewModel {
//    @Published var code = ""
//    @Published var isVerifying = false
//    @Published var isResending = false
//    @Published var resendCooldown = 0
//    @Published var errorMessage: String?
//
//    let phoneNumber = "+44 7700 900123"
//
//    private var cooldownTask: Task<Void, Never>?
//
//    init() { startCooldown() }
//
//    func verify() async {
//        isVerifying = true
//        errorMessage = nil
//        try? await Task.sleep(for: .seconds(1.5))
//        isVerifying = false
//        errorMessage = "That code isn't right. Check it and try again."
//    }
//
//    func resend() async {
//        isResending = true
//        errorMessage = nil
//        code = ""
//        try? await Task.sleep(for: .seconds(1))
//        isResending = false
//        startCooldown()
//    }
//
//    private func startCooldown(seconds: Int = 30) {
//        cooldownTask?.cancel()
//        resendCooldown = seconds
//        cooldownTask = Task { [weak self] in
//            while let self, self.resendCooldown > 0, !Task.isCancelled {
//                try? await Task.sleep(for: .seconds(1))
//                self.resendCooldown -= 1
//            }
//        }
//    }
//}
//
//#Preview {
//    OTPVerificationScreen(
//        viewModel: PreviewOTPViewModel(),
//        onChangePhoneNumber: {}
//    )
//}
