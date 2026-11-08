//
//  AddCocktailRecipe.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData
import SwiftData
import UIKit

/// Form for adding a cocktail or editing one, on the new database (data model refactor, phase 5).
/// Ingredients are edited as text, one per line, and read into rows when saved.
struct AddEditCocktailRecipeView: View {
    @Environment(\.modelContext) private var context

    /// The cocktail being edited, or nil when adding a new one.
    private let cocktail: V1.Cocktail?

    @State private var name = ""
    @State private var source: CocktailSource = .original
    @State private var baseStyle: V1.SpiritStyle?
    @State private var rating = 0
    @State private var isFavorite = false
    @State private var ingredientsText = ""
    @State private var loadedIngredientsText = ""
    @State private var method = ""
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var hasLoaded = false

    /// - Parameter cocktail: The cocktail to edit. Leave out to add a new cocktail.
    init(cocktail: V1.Cocktail? = nil) {
        self.cocktail = cocktail
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Lines the parser isn't sure about, so they can be pointed out while editing.
    private var unclearLines: [String] {
        IngredientParser.parse(ingredientsText).ingredients.filter(\.needsReview).map(\.original)
    }

    var body: some View {
        FormScreen(cocktail == nil ? "Add Cocktail" : "Edit Cocktail", canSave: canSave, onSave: save) {
            PhotoSection(photo: $photo, photoChanged: $photoChanged, placeholder: .cocktail)

            Section("Cocktail") {
                TextField("Name (e.g. Old Fashioned)", text: $name)
                    .textInputAutocapitalization(.words)
                StylePicker(selection: $baseStyle)
            }

            Section("Source") {
                Picker("Source", selection: $source) {
                    ForEach(CocktailSource.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
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
                TextField("e.g. 2 parts Bourbon", text: $ingredientsText, axis: .vertical)
                    .lineLimit(4...14)
            } header: {
                Text("Ingredients")
            } footer: {
                if unclearLines.isEmpty {
                    Text("One ingredient per line, in parts: \"2 parts Gin\", \"¾ part Lime Juice\", \"2 dashes Bitters\".")
                } else {
                    Label("Check: \(unclearLines.joined(separator: "; "))", systemImage: "exclamationmark.triangle")
                }
            }

            Section("How to Make") {
                TextField("e.g. Stir with ice and strain over a large cube", text: $method, axis: .vertical)
                    .lineLimit(4...12)
            }
        }
        .onAppear(perform: loadCocktail)
    }

    private func loadCocktail() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let cocktail else { return }
        name = cocktail.name
        source = cocktail.source
        baseStyle = cocktail.baseStyle
        rating = cocktail.rating
        isFavorite = cocktail.isFavorite
        ingredientsText = IngredientFormatter.text(for: cocktail.orderedIngredients)
        loadedIngredientsText = ingredientsText
        method = cocktail.method
        photo = cocktail.photo.flatMap(UIImage.init(data:))
    }

    private func save() throws {
        let store = CocktailStore(context: context)
        let photoData = photo?.cocktailPhotoData()
        if let cocktail {
            try store.update(cocktail) {
                $0.name = name
                $0.source = source
                $0.baseStyle = baseStyle
                $0.rating = rating
                $0.isFavorite = isFavorite
                $0.method = method
                if photoChanged {
                    $0.photo = photoData
                }
            }
            // Only re-read the ingredients if they were changed, so untouched recipes keep their rows exactly.
            if ingredientsText != loadedIngredientsText {
                try store.setIngredients(fromText: ingredientsText, for: cocktail)
            }
        } else {
            try store.addCocktail(
                name: name,
                source: source,
                baseStyle: baseStyle,
                ingredients: IngredientParser.parse(ingredientsText).ingredients,
                method: method,
                rating: rating,
                isFavorite: isFavorite,
                photo: photo
            )
        }
    }
}

#Preview("Add") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.addMissingStyles(context: container.mainContext, defaults: nil)
    return AddEditCocktailRecipeView()
        .modelContainer(container)
}

#Preview("Edit") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    let oldFashioned = try! container.mainContext.fetch(FetchDescriptor<V1.Cocktail>()).first { $0.name == "Old Fashioned" }!
    return AddEditCocktailRecipeView(cocktail: oldFashioned)
        .modelContainer(container)
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
