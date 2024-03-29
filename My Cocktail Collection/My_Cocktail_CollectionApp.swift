//
//  My_Cocktail_CollectionApp.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

@main
struct My_Cocktail_CollectionApp: App {
    @StateObject private var dataController = DataController()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, dataController.container.viewContext)
        }
    }
}
