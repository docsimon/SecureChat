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
    
    var body: some View {
       
        VStack {
            
            List {
                ForEach(viewModel.chat?.messages ?? [], id: \.self) { messageID in
                    let messageViewModel = dep.makeMessageViewModel(from: messageID)
                    MessageView(viewModel: messageViewModel)
                }
            }
            SendMessageView(viewModel: viewModel)
                .onAppear {
                    SCLogger.logger.info(message: "Chat id: \(viewModel.chat?.id)", category: .Message)
                }
        }
    }
}
