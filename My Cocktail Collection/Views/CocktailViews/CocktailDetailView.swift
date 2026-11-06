//
//  TestView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/28/24.
//

import SwiftUI
import CoreData

/// A cocktail's recipe. Shown pushed from the cocktail list.
struct CocktailDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) private var spirits: FetchedResults<Spirit>
    @ObservedObject private var drink: Drink

    @State private var showEdit = false
    @State private var confirmDelete = false

    init(drink: Drink) {
        _drink = ObservedObject(wrappedValue: drink)
    }

    private var name: String { drink.drinkName ?? "Cocktail" }

    private var spiritName: String? {
        guard let id = drink.baseSpirit else { return nil }
        return spirits.first { $0.id == id }?.spiritName
    }

    private var shareText: String {
        "Check out this cocktail recipe: \nCocktail Name: \(drink.drinkName ?? "")\nIngredients: \(drink.ingredients ?? "")\nMethod: \(drink.method ?? "")"
    }

    var body: some View {
        // After a delete the object is gone; show nothing while the screen closes.
        if drink.managedObjectContext == nil || drink.isDeleted {
            Color.clear
        } else {
            recipe
        }
    }

    private var recipe: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Thumbnail(data: drink.image, placeholder: .cocktail, size: Theme.ImageSize.detail, cornerRadius: Theme.Radius.detail)
                    if drink.rating > 0 {
                        StarRatingView(rating: Double(drink.rating) / 2.0)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                LabeledContent("Base Spirit", value: spiritName ?? "None")
                LabeledContent("Source", value: SourceType(rawValue: drink.source)?.description ?? "Unknown")
            }

            Section("Ingredients") {
                textOrPlaceholder(drink.ingredients, placeholder: "No ingredients added yet.")
            }

            Section("How to Make") {
                textOrPlaceholder(drink.method, placeholder: "No directions added yet.")
            }
        }
        .navigationTitle(name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // "SwiftUI." is needed because the app's Core Data entity is also named Menu.
                SwiftUI.Menu {
                    ShareLink(item: shareText) {
                        Label("Share Recipe", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Cocktail", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                Button("Edit") {
                    showEdit = true
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditCocktailRecipeView(drink: drink)
        }
        .alert("Delete \(name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                DataController.delete(drink, context: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will be removed from your collection and from any menus.")
        }
    }

    @ViewBuilder
    private func textOrPlaceholder(_ text: String?, placeholder: String) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(text)
        } else {
            Text(placeholder)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    DataController.seedCocktails(context: context)
    let drink = try! context.fetch(NSFetchRequest<Drink>(entityName: "Drink")).first { $0.drinkName == "Old Fashioned" }!
    drink.rating = 9
    return NavigationStack {
        CocktailDetailView(drink: drink)
    }
    .environment(\.managedObjectContext, context)
}
