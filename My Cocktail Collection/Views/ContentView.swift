//
//  ContentView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var drinks: FetchedResults<Drink>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
    @State var isPreview = false
    @State var addNewCocktail = false
    @State var createMenu = false
    @State var viewSpirits = false
    @State var viewMenus = false
    @State var viewInFiles =  false
    @State private var viewInventory = false
    
    let billsFaves = ["Cherry Bourbon Sour", "Blood Orange Margarita", "Irish Whiskey Sour", "Ranch Water", "Chocolate Peanutbutter Sundae", "Bourbon Renewal"]
    @State var areFavesAdded = false
    @State private var confirmDeleteMenus = false
    
    var body: some View {
        NavigationView{
            VStack{
                HStack{
                    if !areFavesAdded {
                        Button("Add Our Favorite Cocktails") {
                            DataController.addBillsFaves(context: context)
                            areFavesAdded = true
                        }
                        .padding()
                    }
                    Spacer()
                    VStack {
                        // "SwiftUI." is needed because the app's Core Data entity is also named Menu.
                        SwiftUI.Menu {
                            Button("Add Cocktail") {
                                addNewCocktail = true
                            }
                            Button("View Spirit List") {
                                viewSpirits.toggle()
                            }
                            Button("View Inventory") {
                                viewInventory = true
                            }
                            Button("View Menus") {
                                viewMenus.toggle()
                            }
                            Button("Create a Menu") {
                                createMenu = true
                            }
                            Button("View Saved Files") {
                                viewInFiles.toggle()
                            }
                            Button("Delete Menu Data", role: .destructive) {
                                confirmDeleteMenus = true
                            }
                        } label: {
                            Image(systemName: "filemenu.and.cursorarrow")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.blue)
                                .padding()
                                .accessibilityLabel("Menu")
                        }
                    }
                    .padding(.horizontal)
                }
                CocktailListView()
                HStack{
                    LinearGradient(gradient: Gradient(colors: [Color.white, Color.red]), startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/)
                        .frame(height: 20)
                }
            }
            .onAppear {
                if !isPreview {
                    DataController.seedIfNeeded(context: context)
                }
                areFavesAdded = drinks.contains { drink in billsFaves.contains(drink.drinkName ?? "") }
            }
        }
        .alert("Delete All Menus?", isPresented: $confirmDeleteMenus) {
            Button("Delete", role: .destructive) {
                DataController.deleteStuff(context: context)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every menu and its cocktail list. Your cocktail recipes are not affected.")
        }
        .sheet(isPresented: $addNewCocktail) {
            AddEditCocktailRecipeView()
        }
        .sheet(isPresented: $viewMenus) {
            MenusListView()
        }
        .sheet(isPresented: $viewSpirits) {
            SpiritListView()
        }
        .sheet(isPresented: $viewInventory) {
            InventoryListView()
        }
        .sheet(isPresented: $createMenu) {
            AddEditMenuView()
        }
        .sheet(isPresented: $viewInFiles) {
            if #available(iOS 16.0, *) {
                DocPicker(url: URL.documentsDirectory)
            }
            else {
                let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                let documentsURL = paths[0] as NSURL
                DocPicker(url: documentsURL as URL)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(isPreview: true)
    }
}
