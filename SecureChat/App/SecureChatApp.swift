//
//  SecureChatApp.swift
//  SecureChat
//
//  Created by doc on 01/10/2025.
//

import SwiftUI

@main
struct SecureChatApp: App {
    
    let dep = DependencyManager()
    
    var body: some Scene {
        WindowGroup {
            //ContentView(chatListViewModel: dep.makeChatListViewModel(), dep: dep)
            RouterView(dep: dep)
        }
    }
}
