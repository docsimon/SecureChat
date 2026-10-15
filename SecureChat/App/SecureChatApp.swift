//
//  SecureChatApp.swift
//  SecureChat
//
//  Created by doc on 01/10/2025.
//

import SwiftUI

@main
struct SecureChatApp: App {

    /// Built when the first window appears, not at launch: the database is
    /// unreadable while the phone is locked (`DatabaseLocation`), and iOS
    /// may start ("prewarm") an app's process before the phone is unlocked.
    @State private var dep: DependencyManager?

    var body: some Scene {
        WindowGroup {
            if let dep {
                RootView(dep: dep, registrationViewModel: dep.registrationViewModel)
            } else {
                Color.clear.onAppear { dep = DependencyManager() }
            }
        }
    }
}
