//
//  SendMessageView.swift
//  SecureChat
//
//  Created by Simone Barbara on 06/10/2025.
//
//
import SwiftUI

struct SendMessageView: View {
    
    @State var viewModel: ChatViewModelProtocol
    
    @State private var inputText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        // Input Bar (sticky at bottom)
        HStack(spacing: 8) {
            TextField("Type a message...", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .submitLabel(.send)
               
            
            Button {
               Task {
                   await viewModel.createMessage(with: inputText)
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.blue)
                    .padding(8)
            }
            .disabled(inputText.isEmpty)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(.keyboard) // Prevents input from jumping with keyboard
        .onAppear {
            // Optional: Focus input on load
            isTextFieldFocused = true
        }
    }
}

