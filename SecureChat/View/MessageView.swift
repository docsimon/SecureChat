//
//  MessageView.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI

struct MessageView: View {

    let viewModel: MessageViewModelProtocol

    var body: some View {
        HStack {
            if viewModel.isOwner { Spacer(minLength: 48) }

            VStack(alignment: viewModel.isOwner ? .trailing : .leading, spacing: 3) {
                // Sender name only for received messages
                if !viewModel.isOwner {
                    Text(viewModel.guestUsername)
                        .font(.caption).bold()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }

                Text(viewModel.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(viewModel.isOwner ? .white : .primary)
                    .background(bubbleColor, in: bubbleShape)

                Text(viewModel.time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }

            if !viewModel.isOwner { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var bubbleColor: Color {
        viewModel.isOwner ? .accentColor : Color(.systemGray5)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: viewModel.isOwner
                ? .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 4, topTrailing: 18)
                : .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 18, topTrailing: 18),
            style: .continuous
        )
    }
}
