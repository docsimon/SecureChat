//
//  ChatView.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI

struct ChatView: View {
    
    @State var viewModel: ChatViewModelProtocol
    
    var body: some View {
        List(viewModel.chat?.messages ?? []) { messageID in 
            MessageView(viewModel: MessageViewModel(message: viewModel.getMessage(from: messageID)))
        }
    }
}

