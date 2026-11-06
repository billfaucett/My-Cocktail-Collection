//
//  AddEditBottleView.swift
//  My Cocktail Collection
//
//  Form for adding a bottle to the inventory or editing one.
//

import SwiftUI
import CoreData
import PhotosUI

struct AddEditBottleView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)])
    private var spirits: FetchedResults<Spirit>

    /// The bottle being edited, or nil when adding a new one.
    let bottle: Bottle?

    @State private var brand = ""
    @State private var spirit: Spirit?
    @State private var stock: StockLevel = .full
    @State private var bottleCount = 1
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var rating = 0
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showAddCategory = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    /// - Parameters:
    ///   - bottle: The bottle to edit. Leave out to add a new bottle.
    ///   - spirit: A category to pre-select when adding.
    init(bottle: Bottle? = nil, spirit: Spirit? = nil) {
        self.bottle = bottle
        _spirit = State(initialValue: spirit)
    }

    private var isEditing: Bool { bottle != nil }
    private var canSave: Bool { !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section("Bottle") {
                    TextField("Brand or name (e.g. Buffalo Trace)", text: $brand)
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $spirit) {
                        Text("None").tag(nil as Spirit?)
                        ForEach(spirits) { spirit in
                            Text(spirit.spiritName ?? "").tag(spirit as Spirit?)
                        }
                    }
                    Button("Add a New Category") {
                        showAddCategory = true
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
                    Text("How much is left in the bottle you're using, and how many bottles you have including backups.")
                }

                Section("Rating") {
                    Toggle("Favorite", isOn: $isFavorite)
                    Picker(selection: $rating) {
                        Text("Not Rated").tag(0)
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    } label: {
                        HStack {
                            Text("Rating")
                            if rating > 0 {
                                StarRatingView(rating: Double(rating) / 2.0)
                                    .font(.caption2)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Tasting notes, where it came from…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Bottle" : "Add Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            // Keep stock level and bottle count consistent, matching the rules in Inventory.
            .onChange(of: bottleCount) { _, newCount in
                if newCount == 0 { stock = .out }
            }
            .onChange(of: stock) { _, newLevel in
                if newLevel.isInStock && bottleCount == 0 { bottleCount = 1 }
            }
            .onChange(of: photoItem) { _, item in
                loadPhoto(from: item)
            }
            .onAppear(perform: loadBottle)
            .sheet(isPresented: $showAddCategory) {
                AddEditSpirit()
            }
            .alert("Couldn't Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                Group {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "wineglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground))
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(photo == nil ? "Add Label Photo" : "Change Photo")
                    }
                    if photo != nil {
                        Button("Remove Photo", role: .destructive) {
                            photo = nil
                            photoItem = nil
                            photoChanged = true
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                photo = image
                photoChanged = true
            }
        }
    }

    // MARK: Load and save

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

    private func save() {
        let inventory = Inventory(context: context)
        do {
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
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
