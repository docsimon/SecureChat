//
//  ChatView.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI

struct ChatView: View {

    @State var viewModel: ChatViewModelProtocol
    @State var dep: DependencyManager

    private var messageIDs: [MessageID] { viewModel.chat?.messages ?? [] }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(messageIDs, id: \.self) { messageID in
                        MessageView(viewModel: dep.makeMessageViewModel(from: messageID))
                            .id(messageID)
                    }
                }
                .defaultScrollAnchor(.bottom)          // iOS 17+
                .onChange(of: messageIDs.count) {
                    scrollToBottom(proxy, animated: true)
                }
            }

            SendMessageView(viewModel: viewModel)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = messageIDs.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }
}

