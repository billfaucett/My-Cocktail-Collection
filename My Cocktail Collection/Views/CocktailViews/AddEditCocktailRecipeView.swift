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
/// Ingredients are a list of rows: Add Ingredient picks them from a list with a few taps,
/// tap a row to fine-tune it, swipe to delete, Reorder to drag, or Add from Text to paste a recipe.
struct AddEditCocktailRecipeView: View {
    @Environment(\.modelContext) private var context

    /// The cocktail being edited, or nil when adding a new one.
    private let cocktail: DB.Cocktail?

    @State private var name = ""
    @State private var source: CocktailSource = .original
    @State private var baseStyle: DB.SpiritStyle?
    @State private var isFavorite = false
    @State private var template: CocktailTemplate?
    @State private var rows: [IngredientInput] = []
    @State private var loadedRows: [IngredientInput] = []
    @State private var editingRow: IngredientInput?
    @State private var showAddIngredient = false
    @State private var showPasteIngredients = false
    @State private var isReordering = false
    @State private var method = ""
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var hasLoaded = false

    /// - Parameter cocktail: The cocktail to edit. Leave out to add a new cocktail.
    init(cocktail: DB.Cocktail? = nil) {
        self.cocktail = cocktail
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var reviewCount: Int { rows.filter(\.needsReview).count }

    var body: some View {
        FormScreen(cocktail == nil ? "Add Cocktail" : "Edit Cocktail", canSave: canSave, onSave: save) {
            PhotoSection(photo: $photo, photoChanged: $photoChanged, placeholder: .cocktail)

            Section("Cocktail") {
                TextField("Name (e.g. Old Fashioned)", text: $name)
                    .textInputAutocapitalization(.words)
                StylePicker(selection: $baseStyle)
                TemplatePicker(selection: $template, suggestion: TemplateSuggester.suggest(rows: rows))
                Toggle("Favorite", isOn: $isFavorite)
            }

            Section {
                ForEach(rows) { row in
                    Button {
                        editingRow = row
                    } label: {
                        IngredientRowLabel(row: row)
                    }
                    .tint(.primary)
                }
                .onDelete { rows.remove(atOffsets: $0) }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

                if !isReordering {
                    Button {
                        showAddIngredient = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                    }
                    Button {
                        showPasteIngredients = true
                    } label: {
                        Label("Add from Text…", systemImage: "text.badge.plus")
                    }
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    if rows.count > 1 {
                        Button(isReordering ? "Done" : "Reorder") {
                            withAnimation { isReordering.toggle() }
                        }
                        .font(.subheadline)
                        .textCase(nil)
                    }
                }
            } footer: {
                if reviewCount > 0 {
                    Label("\(reviewCount == 1 ? "1 ingredient needs" : "\(reviewCount) ingredients need") checking. Tap it to fix.",
                          systemImage: "exclamationmark.triangle")
                } else if rows.isEmpty {
                    Text("Tap Add Ingredient to pick from the list. A part is whatever measure you use.")
                }
            }
            .environment(\.editMode, .constant(isReordering ? .active : .inactive))

            Section("How to Make") {
                TextField("e.g. Stir with ice and strain over a large cube", text: $method, axis: .vertical)
                    .lineLimit(4...12)
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
        }
        .onAppear(perform: loadCocktail)
        .sheet(item: $editingRow) { row in
            IngredientEditorView(ingredient: row) { edited in
                if let index = rows.firstIndex(where: { $0.id == row.id }) {
                    rows[index] = edited
                }
            }
        }
        .sheet(isPresented: $showAddIngredient) {
            QuickAddIngredientsView(rows: $rows)
        }
        .sheet(isPresented: $showPasteIngredients) {
            PasteIngredientsView { rows.append(contentsOf: $0) }
        }
    }

    private func loadCocktail() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let cocktail else { return }
        name = cocktail.name
        source = cocktail.source
        baseStyle = cocktail.baseStyle
        isFavorite = cocktail.isFavorite
        template = cocktail.template
        rows = cocktail.orderedIngredients.map { ingredient in
            // Re-read each line to find the ones that still need checking.
            IngredientInput(stored: ingredient,
                            needsReview: cocktail.needsIngredientReview && IngredientParser.parseLine(ingredient.displayText).needsReview)
        }
        loadedRows = rows
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
                $0.isFavorite = isFavorite
                $0.template = template
                $0.method = method
                if photoChanged {
                    $0.photo = photoData
                }
            }
            // Only replace the ingredients if they were changed, so untouched recipes keep their rows exactly.
            if rows != loadedRows {
                try store.setIngredients(rows, for: cocktail)
            }
        } else {
            try store.addCocktail(
                name: name,
                source: source,
                baseStyle: baseStyle,
                rows: rows,
                method: method,
                isFavorite: isFavorite,
                photo: photo,
                template: template
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
    let oldFashioned = try! container.mainContext.fetch(FetchDescriptor<DB.Cocktail>()).first { $0.name == "Old Fashioned" }!
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
