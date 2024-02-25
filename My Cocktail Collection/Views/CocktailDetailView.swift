//
//  CocktailDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData

struct CocktailDetailView: View {
    @Environment(\.managedObjectContext) var context
    let drinkID: NSManagedObjectID
    @State private var showingAlert = false
    
    var body: some View {
        let drink = context.object(with: drinkID) as! Drink
        
        NavigationView{
            ScrollView{
                VStack {
                    Section {
                        VStack {
                            HStack {
                                Spacer()
                                NavigationLink ("Edit") {
                                    AddCocktailRecipeView(drink: drink)
                                }
                                .padding()
                            }
                        }
                    }
                    Section {
                        VStack {
                            Text(drink.drinkName!)
                                .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                                .padding()
                            Text("Ingredient List:")
                                .font(.caption)
                                .padding()
                            Text(drink.ingredients!)
                                .padding()
                            Text("Directions:")
                                .font(.caption)
                                .padding(.horizontal)
                            Text(drink.method!)
                        }
                    }
                    .padding()
                    Section {
                        VStack {
                            HStack {
                                Button("Delete Drink") {
                                    showingAlert = true
                                }
                                .foregroundColor(.red)
                                .alert(isPresented: $showingAlert) {
                                    Alert(title: Text("Confirm Deletion"), message: Text("Are you sure you want to delete this drink?"), primaryButton: .destructive(Text("Delete")) {
                                        context.delete(drink)
                                    }, secondaryButton: .cancel())
                                }
                                Spacer()
                            }
                        }
                        .padding()
                    }
                }
                .padding()
            }
        }
    }
}

struct CocktailDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        let drink = Drink(context: context)
        drink.drinkName = "Mocktail"
        drink.ingredients = "Ingredient 1, Ingredient 2"
        drink.method = "Mix ingredients and serve chilled."
        return CocktailDetailView(drinkID: drink.objectID)
            .environment(\.managedObjectContext, context)
    }
}
