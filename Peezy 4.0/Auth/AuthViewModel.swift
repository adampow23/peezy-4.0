//
//  AuthViewModel.swift
//  PeezyV1.0
//
//  Created by user285836 on 11/11/25.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    // Unhashed nonce for Apple Sign In
    private var currentNonce: String?
    
    // Store the listener handle for cleanup
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        // Listen for auth state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isAuthenticated = user != nil
        }
    }
    
    deinit {
        // Remove the listener when the view model is deallocated
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Sign In with Apple
    
    func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }
    
    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>, completion: @escaping (Error?) -> Void) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                guard let nonce = currentNonce else {
                    completion(NSError(domain: "AuthViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid state: A login callback was received, but no login request was sent."]))
                    return
                }
                
                guard let appleIDToken = appleIDCredential.identityToken else {
                    completion(NSError(domain: "AuthViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"]))
                    return
                }
                
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    completion(NSError(domain: "AuthViewModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to serialize token string from data"]))
                    return
                }
                
                // Initialize a Firebase credential
                let credential = OAuthProvider.credential(
                    providerID: AuthProviderID.apple,
                    idToken: idTokenString,
                    rawNonce: nonce
                )
                
                // Sign in with Firebase
                Auth.auth().signIn(with: credential) { (authResult, error) in
                    if let error = error {
                        completion(error)
                        return
                    }

                    print("✅ Successfully signed in with Apple: \(authResult?.user.uid ?? "")")
                    completion(nil)
                }
            }
            
        case .failure(let error):
            completion(error)
        }
    }
    
    // MARK: - Sign In with Google
    
    func signInWithGoogle(completion: @escaping (Error?) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            completion(NSError(domain: "AuthViewModel", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Missing client ID"]))
            return
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            completion(NSError(domain: "AuthViewModel", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "No root view controller"]))
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                completion(error)
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                completion(NSError(domain: "AuthViewModel", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Missing ID token"]))
                return
            }
            
            let accessToken = user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    completion(error)
                    return
                }

                print("✅ Successfully signed in with Google: \(authResult?.user.uid ?? "")")
                completion(nil)
            }
        }
    }
    
    // MARK: - Email/Password Sign Up
    
    func signUp(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            if let error = error {
                completion(error)
                return
            }
            
            print("✅ Successfully created account: \(authResult?.user.uid ?? "")")
            completion(nil)
        }
    }
    
    // MARK: - Email/Password Sign In
    
    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                completion(error)
                return
            }
            
            print("✅ Successfully signed in: \(authResult?.user.uid ?? "")")
            completion(nil)
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        try Auth.auth().signOut()
        isAuthenticated = false
        currentUser = nil
    }
    
    // MARK: - Helper Functions
    
    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Failed to generate secure random bytes")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}
