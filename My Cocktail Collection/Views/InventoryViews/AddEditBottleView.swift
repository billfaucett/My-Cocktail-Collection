//
//  AddEditBottleView.swift
//  My Cocktail Collection
//
//  Form for adding a bottle to the inventory or editing one.
//

import SwiftUI
import CoreData

struct AddEditBottleView: View {
    @Environment(\.managedObjectContext) private var context

    /// The bottle being edited, or nil when adding a new one.
    private let bottle: Bottle?

    @State private var brand = ""
    @State private var spirit: Spirit?
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
    ///   - spirit: A category to pre-select when adding.
    init(bottle: Bottle? = nil, spirit: Spirit? = nil) {
        self.bottle = bottle
        _spirit = State(initialValue: spirit)
    }

    private var canSave: Bool { !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FormScreen(bottle == nil ? "Add Bottle" : "Edit Bottle", canSave: canSave, onSave: save) {
            PhotoSection(photo: $photo, photoChanged: $photoChanged, placeholder: .bottle, addTitle: "Add Label Photo")

            Section("Bottle") {
                TextField("Brand or name (e.g. Buffalo Trace)", text: $brand)
                    .textInputAutocapitalization(.words)
                SpiritPicker(selection: $spirit, title: "Category", addTitle: "Add a New Category")
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
                Text("How much is left in the bottle you're using, and how many bottles you have including backups.")
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
        // Keep stock level and bottle count consistent, matching the rules in Inventory.
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
        brand = bottle.brand ?? ""
        spirit = bottle.spirit
        stock = bottle.stock
        bottleCount = Int(bottle.bottleCount)
        notes = bottle.notes ?? ""
        isFavorite = bottle.isFavorite
        rating = Int(bottle.rating)
        photo = bottle.image.flatMap(UIImage.init(data:))
    }

    private func save() throws {
        let inventory = Inventory(context: context)
        if let bottle {
            try inventory.update(bottle) { bottle in
                bottle.brand = brand
                bottle.spirit = spirit
                bottle.stock = stock
                bottle.bottleCount = Int16(bottleCount)
                bottle.notes = notes
                bottle.isFavorite = isFavorite
                bottle.rating = Int16(rating)
                if photoChanged {
                    bottle.setPhoto(photo)
                }
            }
        } else {
            try inventory.addBottle(
                brand: brand,
                spirit: spirit,
                stock: stock,
                bottleCount: Int16(bottleCount),
                notes: notes,
                isFavorite: isFavorite,
                rating: Int16(rating),
                photo: photo
            )
        }
    }
}

#Preview("Add") {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    return AddEditBottleView()
        .environment(\.managedObjectContext, context)
}

#Preview("Edit") {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    let bourbon = try? context.fetch(NSFetchRequest<Spirit>(entityName: "Spirit")).first { $0.spiritName == "Bourbon" }
    let bottle = try! Inventory(context: context).addBottle(
        brand: "Buffalo Trace", spirit: bourbon, stock: .low, bottleCount: 2,
        notes: "Our go-to for Old Fashioneds", isFavorite: true, rating: 8
    )
    return AddEditBottleView(bottle: bottle)
        .environment(\.managedObjectContext, context)
}
