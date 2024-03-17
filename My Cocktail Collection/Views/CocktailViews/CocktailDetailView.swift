//
//  TestView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/28/24.
//

import SwiftUI
import CoreData
import MessageUI

struct CocktailDetailView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) var spirits: FetchedResults<Spirit>
    let drinkID: NSManagedObjectID
    @State private var showingAlert = false
    @State private var showingMessageComposer = false
    @State private var showEdit = false
    @State private var refreshId = UUID()
    
    var body: some View {
        let drink = context.object(with: drinkID) as! Drink
        
        NavigationView {
            ScrollView {
                VStack {
                    HStack {
                        Button("Delete") {
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
                                    print("Error deleteing drink: \(error)")
                                }
                            }, secondaryButton: .cancel())
                        }
                        .padding()
                        Spacer()
                        Button ("Edit") {
                            showEdit = true
                        }
                        .padding()
                    }
                }
                VStack {
                    Text(drink.drinkName ?? "")
                        .font(.title)
                        .padding()
                    if drink.rating > 0 {
                        HStack {
                            Text("Drink Rating:")
                            StarRatingView(rating: getRatingStars(rating: drink.rating))
                                .padding(.horizontal)
                        }
                    }
                    if let image = drink.image, let uiImage = UIImage(data: image) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    } else {
                        Image("martini")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    }
                    if let base = drink.baseSpirit {
                        if let spirit = spirits.first(where: { $0.id == base }) {
                            Text("Base Spirit:")
                                .font(.caption)
                            Text(spirit.spiritName ?? "")
                                .padding(.bottom)
                        } else {
                            Text("No clue why this is not working")
                        }
                    }
                    if let sourceType = SourceType(rawValue: drink.source) {
                        Text("Source:")
                            .font(.caption)
                        Text(sourceType.description)
                            .padding(.bottom)
                    }
                    Text("Ingredient List:")
                        .font(.caption)
                        .bold()
                        .padding(.horizontal)
                    Text(drink.ingredients ?? "")
                        .padding()
                    Text("Directions:")
                        .font(.caption)
                        .bold()
                        .padding(.horizontal)
                    Text(drink.method ?? "")
                        .padding()
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
            .sheet(isPresented: $showEdit) {
                AddEditCocktailRecipeView(drink: drink)
            }
        }
        .id(refreshId)
    }
    
    private func getRatingStars(rating: Int16) -> Double {
        return Double(rating / 2)
    }
}

struct CocktailDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        let drink = Drink(context: context)
        let id = UUID()
        drink.source = 1
        drink.baseSpirit = id
        drink.drinkName = "Mocktail"
        drink.ingredients = "Ingredient 1, Ingredient 2"
        drink.method = "Mix ingredients and serve chilled."
        drink.rating = 9
        
        // Add mock data for spirits
        let spirit = Spirit(context: context)
        spirit.id = id
        spirit.spiritName = "Whiskey"
        spirit.type = 0
        
        return CocktailDetailView(drinkID: drink.objectID)
            .environment(\.managedObjectContext, context)
    }
}
