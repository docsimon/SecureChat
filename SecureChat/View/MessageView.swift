//
//  MessageView.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI

struct MessageView: View {
    
    var viewModel: MessageViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("[\(viewModel.guest)]")
            HStack(spacing: 10) {
                Text(viewModel.content)
                VStack(alignment: .trailing) {
                    Spacer()
                    Text(viewModel.time)
                }
            }
        }
    }
}
