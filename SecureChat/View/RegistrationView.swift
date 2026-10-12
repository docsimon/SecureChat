//
//  RegistrationView.swift
//  SecureChat
//
//  The first screen: one button that registers this device.
//

import SwiftUI

struct RegistrationView: View {

    let viewModel: RegistrationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("SecureChat")
                    .font(.largeTitle.bold())
                Text("Register this device to start chatting. No phone number or email needed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            status

            if showsButton {
                Button {
                    Task { await viewModel.register() }
                } label: {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.phase == .registering || viewModel.phase == .loading)
            }

#if DEBUG
            Text("Development server")
                .font(.footnote)
                .foregroundStyle(.tertiary)
#endif
        }
        .padding(24)
    }

    @ViewBuilder
    private var status: some View {
        switch viewModel.phase {
        case .registering:
            ProgressView("Registering…")
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        case .unsupported:
            Text("This device can't be verified, so it can't be registered. SecureChat needs a physical iPhone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .loading, .notRegistered, .registered:
            EmptyView()
        }
    }

    private var showsButton: Bool {
        viewModel.phase != .unsupported
    }

    private var buttonTitle: String {
        if case .failed = viewModel.phase { return "Try again" }
        return "Register"
    }
}
