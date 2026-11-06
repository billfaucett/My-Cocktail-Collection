//
//  ContentView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData

/// The main screen: a tab for each part of the app.
struct ContentView: View {
    @Environment(\.managedObjectContext) var context
    var isPreview = false

    var body: some View {
        TabView {
            CocktailListView()
                .tabItem { Label("Cocktails", systemImage: "wineglass") }
            InventoryListView()
                .tabItem { Label("Inventory", systemImage: "archivebox") }
            MenusListView()
                .tabItem { Label("Menus", systemImage: "menucard") }
            SpiritListView()
                .tabItem { Label("Spirits", systemImage: "drop") }
        }
        .onAppear {
            if !isPreview {
                DataController.seedIfNeeded(context: context)
            }
        }
    }
}

#Preview {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedIfNeeded(context: context)
    return ContentView(isPreview: true)
        .environment(\.managedObjectContext, context)
}
