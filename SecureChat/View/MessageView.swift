//
//  MessageView.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI

struct MessageView: View {
    
    var content: String
    var time: String
    
    var body: some View {
        
        HStack(spacing: 10) {
            Text(content)
            Text(time)
        }
        
    }
}
