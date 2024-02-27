//
//  CocktailDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData
import MessageUI

struct CocktailDetailView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    let drinkID: NSManagedObjectID
    @State private var showingAlert = false
    @State private var showingMessageComposer = false
    
    var body: some View {
        let drink = context.object(with: drinkID) as! Drink
        
        NavigationView{
            ScrollView{
                VStack {
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
                                        do {
                                            try context.save()
                                            dismiss()
                                        } catch {
                                            print("Error deleting drink: \(error)")
                                        }
                                    }, secondaryButton: .cancel())
                                }
                                .padding()
                                Spacer()
                                NavigationLink ("Edit Drink") {
                                    AddEditCocktailRecipeView(drink: drink)
                                }
                                .padding()
                            }
                        }
                    }
                    Section {
                        VStack {
                            Text(drink.drinkName ?? "")
                                .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                                .padding()
                            if let sourceType = SourceType(rawValue: drink.source) {
                                Text("Source:")
                                    .font(.caption)
                                Text(sourceType.description)
                                    .padding(.bottom)
                            }
                            if drink.baseSpirit != nil {
                                @FetchRequest(sortDescriptors: []) var spirits: FetchedResults<Spirit>
                                let myBaseSpirit = spirits.first(where: { $0.id == drink.baseSpirit })?.spiritName
                                Text(myBaseSpirit ?? "None")
                            }
                            Text("Ingredient List:")
                                .font(.caption)
                                .bold()
                                .padding(.horizontal)
                            Text(drink.ingredients ?? "")
                                .padding()
                            Text("How to Make:")
                                .font(.caption)
                                .bold()
                                .padding(.horizontal)
                            Text(drink.method ?? "")
                                .padding()
                        }
                    }
                    .padding()
                    Section {
                        VStack {
                            HStack {
                                Button("Share Recipe") {
                                    showingMessageComposer = true
                                }
                                .sheet(isPresented: $showingMessageComposer) {
                                    MessageComposer(isShowing: $showingMessageComposer, cocktailName: drink.drinkName ?? "", ingredients: drink.ingredients ?? "", method: drink.method ?? "")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CocktailDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        let drink = Drink(context: context)
        drink.source = 1
        drink.drinkName = "Mocktail"
        drink.ingredients = "Ingredient 1, Ingredient 2"
        drink.method = "Mix ingredients and serve chilled."
        return CocktailDetailView(drinkID: drink.objectID)
            .environment(\.managedObjectContext, context)
    }
}
