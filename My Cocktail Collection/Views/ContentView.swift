//
//  ContentView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var drinks: FetchedResults<Drink>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
    @State var isPreview = false
    @State var addNewCocktail = false
    @State var createMenu = false
    @State var isMenuSelected = false
    @State var viewSpirits = false
    @State var viewMenus = false
    
    let billsFaves = ["Cherry Bourbon Sour", "Blood Orange Margarita", "Irish Whiskey Sour", "Ranch Water", "Chocolate Peanutbutter Sundae", "Bourbon Renewal"]
    @State var areFavesAdded = false
    
    var body: some View {
        NavigationView{
            VStack{
                HStack{
                    if !areFavesAdded {
                        Button("Add Our Favorite Cocktails") {
                            DataController().addBillsFaves(context: context, spirits: spirits, loadedDrinks: drinks)
                        }
                        .padding()
                    }
                    Spacer()
                    VStack {
                        Image(systemName: "filemenu.and.cursorarrow")
                            .foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                            .padding()
                            .onTapGesture {
                                isMenuSelected.toggle()
                            }
                            .contextMenu {
                                Button("Add Cocktail") {
                                    addNewCocktail = true
                                }
                                Button("View Spirit List") {
                                    viewSpirits.toggle()
                                }
                                Button("View Menus") {
                                    viewMenus.toggle()
                                }
                                Button("Create a Menu") {
                                    createMenu = true
                                }
                                Button("Delete Menu Data"){
                                    DataController().deleteStuff(context: context)
                                }
                                .foregroundColor(.red)
                            }
                    }
                    .padding()
                }
                CocktailListView()
                HStack{
                    LinearGradient(gradient: Gradient(colors: [Color.white, Color.red]), startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/)
                        .frame(height: 20)
                }
            }
            .onAppear {
                if spirits.isEmpty && !isPreview {
                    DataController().seedSpirits(context: context)
                }
                if drinks.isEmpty && !isPreview {
                    DataController().seedCocktails(context: context, spirits: spirits)
                }
                areFavesAdded = drinks.contains { drink in billsFaves.contains(drink.drinkName ?? "") }
            }
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(isPreview: true)
    }
}
