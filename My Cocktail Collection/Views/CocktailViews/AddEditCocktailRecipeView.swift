//
//  AddCocktailRecipe.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData
import UIKit

struct AddEditCocktailRecipeView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var spirits: FetchedResults<Spirit>

    /// The cocktail being edited, or nil when adding a new one.
    private let drink: Drink?

    @State private var drinkName = ""
    @State private var source: SourceType = .classic
    @State private var baseSpirit: Spirit?
    @State private var rating = 0
    @State private var isFavorite = false
    @State private var ingredients = ""
    @State private var method = ""
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var hasLoaded = false

    /// - Parameter drink: The cocktail to edit. Leave out to add a new cocktail.
    init(drink: Drink? = nil) {
        self.drink = drink
    }

    private var canSave: Bool { !drinkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FormScreen(drink == nil ? "Add Cocktail" : "Edit Cocktail", canSave: canSave, onSave: save) {
            PhotoSection(photo: $photo, photoChanged: $photoChanged, placeholder: .cocktail)

            Section("Cocktail") {
                TextField("Name (e.g. Old Fashioned)", text: $drinkName)
                    .textInputAutocapitalization(.words)
                SpiritPicker(selection: $baseSpirit)
            }

            Section("Source") {
                Picker("Source", selection: $source) {
                    ForEach(SourceType.allCases, id: \.self) { source in
                        Text(source.description).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Rating") {
                Toggle("Favorite", isOn: $isFavorite)
                RatingPicker(rating: $rating)
            }

            Section {
                TextField("e.g. 2 oz Bourbon", text: $ingredients, axis: .vertical)
                    .lineLimit(4...12)
            } header: {
                Text("Ingredients")
            } footer: {
                Text("One ingredient per line works best.")
            }

            Section("How to Make") {
                TextField("e.g. Stir with ice and strain over a large cube", text: $method, axis: .vertical)
                    .lineLimit(4...12)
            }
        }
        .onAppear(perform: loadDrink)
    }

    private func loadDrink() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let drink else { return }
        drinkName = drink.drinkName ?? ""
        source = SourceType(rawValue: drink.source) ?? .classic
        if let spiritID = drink.baseSpirit {
            baseSpirit = spirits.first { $0.id == spiritID }
        }
        rating = Int(drink.rating)
        isFavorite = drink.isFavorite
        ingredients = drink.ingredients ?? ""
        method = drink.method ?? ""
        photo = drink.image.flatMap(UIImage.init(data:))
    }

    private func save() throws {
        let target = drink ?? Drink(context: context)
        if drink == nil {
            target.id = UUID()
        }
        target.drinkName = drinkName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.source = source.rawValue
        target.baseSpirit = baseSpirit?.id
        target.rating = Int16(rating)
        target.isFavorite = isFavorite
        target.ingredients = ingredients
        target.method = method
        if photoChanged {
            if let photo {
                target.setPhoto(photo)
            } else {
                target.image = nil
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

#Preview("Add") {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    return AddEditCocktailRecipeView()
        .environment(\.managedObjectContext, context)
}

#Preview("Edit") {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    DataController.seedCocktails(context: context)
    let drink = try? context.fetch(NSFetchRequest<Drink>(entityName: "Drink")).first { $0.drinkName == "Old Fashioned" }
    drink?.rating = 9
    return AddEditCocktailRecipeView(drink: drink)
        .environment(\.managedObjectContext, context)
}

extension UIImage {
    /// Shrinks the image so its longest side is at most `maxDimension` pixels, keeping its proportions.
    func scaledToFit(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Data for storing a cocktail photo: at most 600px on the longest side, saved as 80% quality JPEG.
    func cocktailPhotoData() -> Data? {
        scaledToFit(maxDimension: 600).jpegData(compressionQuality: 0.8)
    }
}

extension Drink {
    /// Stores a photo for this drink, shrunk and compressed by `cocktailPhotoData()`.
    func setPhoto(_ photo: UIImage) {
        image = photo.cocktailPhotoData()
    }
}
