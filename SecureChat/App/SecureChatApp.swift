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
            RouterView(dep: dep, registrationRouterViewModel: dep.makeRegistrationRouterViewModel())
        }
    }
}
