//
//  My_Cocktail_CollectionApp.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import CloudKit
import SwiftUI
import CoreData
import SwiftData
import UIKit

@main
@MainActor
struct My_Cocktail_CollectionApp: App {
    /// Receives invitations to shared libraries (sync and sharing, step 4).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// UI tests launch the app with "-uiTesting" so they start from fresh, in-memory databases.
    private static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// Today's Core Data database. Screens move off it one area at a time during the refactor.
    @StateObject private var dataController = DataController(inMemory: My_Cocktail_CollectionApp.isUITesting)

    /// The new SwiftData database, prepared (imported and seeded) before any screen appears.
    private let modelContainer: ModelContainer

    init() {
        modelContainer = AppStartup.makeModelContainer(isUITesting: Self.isUITesting)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
                .modelContainer(modelContainer)
        }
    }
}

// MARK: - Invitations to shared libraries

/// Gives each window a scene delegate, which is where iOS delivers an accepted iCloud share.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Tapping an invitation to someone's library opens the app here, either at launch or while it's running.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in await CloudSync.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in await CloudSync.accept(cloudKitShareMetadata) }
    }
}

