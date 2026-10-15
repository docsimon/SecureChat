//
//  SendMessageView.swift
//  SecureChat
//
//  Created by Simone Barbara on 06/10/2025.
//
//
import SwiftUI

struct SendMessageView: View {

    @Bindable var viewModel: ConversationViewModel

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.draftIsTooLong {
                Text("Too long for one message.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            // Input Bar (sticky at bottom)
            HStack(spacing: 8) {
                TextField("Type a message...", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isTextFieldFocused)

                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .padding(8)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .onAppear {
            isTextFieldFocused = true
        }
    }
}
