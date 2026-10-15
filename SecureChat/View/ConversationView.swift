//
//  ConversationView.swift
//  SecureChat
//
//  The chat with one contact.
//

import SwiftUI

struct ConversationView: View {

    @State var viewModel: ConversationViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.vertical)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: viewModel.messages.count) {
                    guard let last = viewModel.messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            SendMessageView(viewModel: viewModel)
        }
        .navigationTitle(viewModel.contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if !viewModel.statusText.isEmpty {
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(.bar)
            }
        }
        .onAppear { viewModel.appeared() }
        .onDisappear { viewModel.disappeared() }
    }
}
