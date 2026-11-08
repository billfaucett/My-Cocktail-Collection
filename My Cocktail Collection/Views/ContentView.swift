//
//  ContentView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData
import SwiftData

/// The main screen: a tab for each part of the app.
struct ContentView: View {
    @Environment(\.managedObjectContext) var context
    var isPreview = false
    @State private var startupError: String?

    var body: some View {
        TabView {
            CocktailListView()
                .tabItem { Label("Cocktails", systemImage: "wineglass") }
            InventoryListView()
                .tabItem { Label("Inventory", systemImage: "archivebox") }
            MenusListView()
                .tabItem { Label("Menus", systemImage: "menucard") }
            StyleListView()
                .tabItem { Label("Styles", systemImage: "square.stack.3d.up") }
        }
        .onAppear {
            if !isPreview {
                DataController.seedIfNeeded(context: context)
                startupError = AppStartup.lastErrorMessage
            }
        }
        .alert("Couldn't Move Your Recipes", isPresented: Binding(
            get: { startupError != nil },
            set: { if !$0 { startupError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(startupError ?? "") Your recipes are safe in the old database, and the app will try again next time it opens.")
        }
    }
}

#Preview {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedIfNeeded(context: context)
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    return ContentView(isPreview: true)
        .environment(\.managedObjectContext, context)
        .modelContainer(container)
}
