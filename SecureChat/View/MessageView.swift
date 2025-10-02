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
        
        HStack(spacing: 10) {
            Text(viewModel.content)
            Text(viewModel.time)
        }
        
    }
}
