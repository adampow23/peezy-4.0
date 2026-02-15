//
//  PeezyV1App.swift
//  PeezyV1.0
//
//  Updated by user285836 on 11/11/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@main
struct PeezyV1App: App {

    // This runs ONCE when the app launches, before any views appear
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    // Handle Google Sign-In URL callback
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
