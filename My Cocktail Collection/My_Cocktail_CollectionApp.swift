//
//  My_Cocktail_CollectionApp.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData
import SwiftData

@main
@MainActor
struct My_Cocktail_CollectionApp: App {
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
