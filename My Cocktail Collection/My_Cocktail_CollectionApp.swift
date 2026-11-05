//
//  My_Cocktail_CollectionApp.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

@main
struct My_Cocktail_CollectionApp: App {
    // UI tests launch the app with "-uiTesting" so they start from a fresh, in-memory database.
    @StateObject private var dataController = DataController(
        inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting")
    )
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
        }
    }
}
