import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAuth

// Firebase setup + anonymous auth at launch
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()

    // Sign in anonymously so Firestore writes work without UI
    if Auth.auth().currentUser == nil {
      Auth.auth().signInAnonymously { _, error in
        if let error = error { print("[Auth] Anonymous sign-in failed: \(error)") }
      }
    }
    return true
  }
}

@main
struct GraffNetApp: App {
  // Register app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  var body: some Scene {
    WindowGroup {
      ZStack {
        AppBackground()
        NavigationView { TagsMapView() }
          .background(Color.clear)
      }
    }
  }
}
