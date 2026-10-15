//
//  MessageView.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI

struct MessageView: View {

    let message: StoredMessage

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(message.isMine ? .white : .primary)
                    .background(bubbleColor, in: bubbleShape)

                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(message.status == .notDelivered ? .red : .secondary)
                    .padding(.horizontal, 6)
            }

            if !message.isMine { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var caption: String {
        let time = message.date.formatted(date: .omitted, time: .shortened)
        switch message.status {
        case .received, .sent: return time
        case .waiting: return "\(time) · Waiting"
        case .notDelivered: return "\(time) · Not delivered"
        }
    }

    private var bubbleColor: Color {
        guard message.isMine else { return Color(.systemGray5) }
        return message.status == .notDelivered ? Color(.systemGray) : .accentColor
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: message.isMine
                ? .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 4, topTrailing: 18)
                : .init(topLeading: 18, bottomLeading: 4, bottomTrailing: 18, topTrailing: 18),
            style: .continuous
        )
    }
}
