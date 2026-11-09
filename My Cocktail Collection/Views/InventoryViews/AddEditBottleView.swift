//
//  AddEditBottleView.swift
//  My Cocktail Collection
//
//  Form for adding a bottle to the inventory or editing one, on the new database (data model refactor, phase 5).
//

import SwiftUI
import SwiftData

struct AddEditBottleView: View {
    @Environment(\.modelContext) private var context

    /// The bottle being edited, or nil when adding a new one.
    private let bottle: V1.Bottle?

    @State private var brand = ""
    @State private var style: V1.SpiritStyle?
    @State private var stock: StockLevel = .full
    @State private var bottleCount = 1
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var rating = 0
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var hasLoaded = false

    /// - Parameters:
    ///   - bottle: The bottle to edit. Leave out to add a new bottle.
    ///   - style: A style to pre-select when adding.
    init(bottle: V1.Bottle? = nil, style: V1.SpiritStyle? = nil) {
        self.bottle = bottle
        _style = State(initialValue: style)
    }

    private var canSave: Bool { !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FormScreen(bottle == nil ? "Add Bottle" : "Edit Bottle", canSave: canSave, onSave: save) {
            PhotoSection(photo: $photo, photoChanged: $photoChanged, placeholder: .bottle, addTitle: "Add Label Photo")

            Section {
                TextField("Brand or name (e.g. Buffalo Trace)", text: $brand)
                    .textInputAutocapitalization(.words)
                StylePicker(selection: $style, title: "Type")
            } header: {
                Text("Bottle")
            } footer: {
                if let style {
                    Text("Listed under \(style.family.displayName).")
                } else {
                    Text("The type (Bourbon, London Dry, Aperitivo…) groups your bottles and links them to recipes.")
                }
            }

            Section {
                Picker("How Much Is Left", selection: $stock) {
                    ForEach(StockLevel.allCases, id: \.self) { level in
                        Text(level.description).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                Stepper(value: $bottleCount, in: 0...99) {
                    LabeledContent("Number of Bottles", value: "\(bottleCount)")
                }
            } header: {
                Text("Stock")
            } footer: {
                Text("How much is left in the bottle you're using, and how many bottles you have including backups. Low and Out bottles go on the shopping list.")
            }

            Section("Rating") {
                Toggle("Favorite", isOn: $isFavorite)
                RatingPicker(rating: $rating)
            }

            Section("Notes") {
                TextField("Tasting notes, where it came from…", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        // Keep stock level and bottle count consistent, matching the rules in BottleStore.
        .onChange(of: bottleCount) { _, newCount in
            if newCount == 0 { stock = .out }
        }
        .onChange(of: stock) { _, newLevel in
            if newLevel.isInStock && bottleCount == 0 { bottleCount = 1 }
        }
        .onAppear(perform: loadBottle)
    }

    private func loadBottle() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let bottle else { return }
        brand = bottle.brand
        style = bottle.style
        stock = bottle.stock
        bottleCount = bottle.bottleCount
        notes = bottle.notes
        isFavorite = bottle.isFavorite
        rating = bottle.rating
        photo = bottle.photo.flatMap(UIImage.init(data:))
    }

    private func save() throws {
        let store = BottleStore(context: context)
        if let bottle {
            let photoData = photo?.cocktailPhotoData()
            try store.update(bottle) {
                $0.brand = brand
                $0.style = style
                $0.stock = stock
                $0.bottleCount = bottleCount
                $0.notes = notes
                $0.isFavorite = isFavorite
                $0.rating = rating
                if photoChanged {
                    $0.photo = photoData
                }
            }
        } else {
            try store.addBottle(
                brand: brand,
                style: style,
                stock: stock,
                bottleCount: bottleCount,
                notes: notes,
                isFavorite: isFavorite,
                rating: rating,
                photo: photo
            )
        }
    }
}

#Preview("Add") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.addMissingStyles(context: container.mainContext, defaults: nil)
    return AddEditBottleView()
        .modelContainer(container)
}

#Preview("Edit") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    let context = container.mainContext
    try? ModelSeeder.addMissingStyles(context: context, defaults: nil)
    let bottle = try! BottleStore(context: context).addBottle(
        brand: "Buffalo Trace", style: try? StyleStore(context: context).style(named: "Bourbon"), stock: .low, bottleCount: 2,
        notes: "Our go-to for Old Fashioneds", isFavorite: true, rating: 8
    )
    return AddEditBottleView(bottle: bottle)
        .modelContainer(container)
}
