//
//  AddCocktailRecipe.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

struct AddEditCocktailRecipeView: View {
    @Environment(\.managedObjectContext) var context
    @State private var selectedSource: Int = 0
    @State private var drinkName: String = ""
    @State private var ingredients: String = ""
    @State private var method: String = ""
    @State private var isSaved = false
    
    var drink: Drink?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    HStack {
                        Spacer()
                        Button("Save") {
                            saveRecipe()
                        }
                        .padding()
                        .disabled(isSaved)
                    }
                    .padding()
                    
                    NavigationLink(destination: CocktailListView(), isActive: $isSaved) {
                        EmptyView()
                    }
                    
                    Section {
                        VStack {
                            HStack{
                                Text("Source")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            
                            Picker(selection: $selectedSource, label: Text("Source")) {
                                Text("Original").tag(0)
                                Text("Website").tag(1)
                                Text("Menu").tag(2)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onAppear {
                                if let drink = drink {
                                    selectedSource = Int(drink.source)
                                }
                            }
                        }
                        .padding()
                    }
                    Spacer()
                    Section {
                        VStack{
                            HStack{
                                Text("Drink Name")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            TextField("Drink Name", text: $drinkName)
                                .padding(.horizontal)
                                .onAppear {
                                    if let drink = drink {
                                        drinkName = drink.drinkName!
                                    }
                                }
                        }
                    }
                    Spacer()
                    Section {
                        VStack{
                            HStack{
                                Text("Ingredients")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            TextEditor(text: $ingredients)
                                .border(Color.gray, width: 1)
                                .frame(height: 200)
                                .padding(.horizontal)
                                .onAppear {
                                    if let drink = drink {
                                        ingredients = drink.ingredients!
                                    }
                                }
                        }
                    }
                    Spacer()
                    Section {
                        VStack{
                            HStack{
                                Text("How to Make")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            TextEditor(text: $method)
                                .border(Color.gray, width: 1)
                                .frame(height: 200)
                                .padding(.horizontal)
                                .onAppear {
                                    if let drink = drink {
                                        method = drink.method!
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle(drink == nil ? "Add a New Cocktail" : "Edit Cocktail")
        }
    }
    
    func saveRecipe() {
        guard let drink = drink else {
            let drink = Drink(context: context)
            drink.id = UUID()
            drink.drinkName = drinkName
            drink.source = Int16(selectedSource)
            drink.ingredients = ingredients
            drink.method = method
            try? context.save()
            isSaved = true
            return
        }
        
        drink.drinkName = drinkName
        drink.source = Int16(selectedSource)
        drink.ingredients = ingredients
        drink.method = method
        try? context.save()
        isSaved = true
    }
}

struct AddCocktailRecipeView_Previews: PreviewProvider {
    static var previews: some View {
        AddEditCocktailRecipeView()
    }
}

