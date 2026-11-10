//
//  AddEditBottleView.swift
//  My Cocktail Collection
//
//  Form for adding a bottle to the inventory or editing one, on the new database (data model refactor, phase 5).
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddEditBottleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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

    // Label scanning (adding only)
    private let scanOnAppear: Bool
    @State private var scanState = LabelScanState.idle
    @State private var lastScan: LabelSuggestion?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    /// A bottle already in My Bar with the scanned brand, to offer adding another bottle to it.
    @State private var existingMatch: V1.Bottle?
    @State private var errorMessage: String?

    /// - Parameters:
    ///   - bottle: The bottle to edit. Leave out to add a new bottle.
    ///   - style: A style to pre-select when adding.
    ///   - scanOnAppear: Open the camera (or Photos, where there's no camera) straight away to scan a label.
    init(bottle: V1.Bottle? = nil, style: V1.SpiritStyle? = nil, scanOnAppear: Bool = false) {
        self.bottle = bottle
        self.scanOnAppear = scanOnAppear && bottle == nil
        _style = State(initialValue: style)
    }

    private var canSave: Bool { !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        FormScreen(bottle == nil ? "Add Bottle" : "Edit Bottle", canSave: canSave, onSave: save) {
            if bottle == nil {
                LabelScanSection(state: scanState, libraryItem: $libraryItem, currentBrand: brand) {
                    showCamera = true
                } onPickBrand: { picked in
                    brand = picked
                    lastScan?.brand = picked
                    offerExistingBottle(for: picked)
                }
            }

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
        .task {
            guard scanOnAppear, scanState == .idle else { return }
            // Let the sheet finish opening before presenting the camera over it.
            try? await Task.sleep(for: .milliseconds(450))
            if CameraPicker.isAvailable {
                showCamera = true
            } else {
                showPhotoLibrary = true
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in scan(image) }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $libraryItem, matching: .images)
        .alert("Already in My Bar", isPresented: Binding(
            get: { existingMatch != nil },
            set: { if !$0 { existingMatch = nil } }
        ), presenting: existingMatch) { match in
            Button("Add Another Bottle") { addAnother(to: match) }
            Button("Add as a Separate Bottle", role: .cancel) { }
        } message: { match in
            Text("You have \(match.brand) (\(match.stock.description), \(match.bottleCount == 1 ? "1 bottle" : "\(match.bottleCount) bottles")). Add one more to it, or keep adding this as a separate bottle?")
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    scan(image)
                }
                libraryItem = nil
            }
        }
    }

    // MARK: Label scanning

    /// Uses the photo as the bottle's picture, reads its label, and fills in the form.
    private func scan(_ image: UIImage) {
        photo = image
        photoChanged = true
        scanState = .reading
        Task {
            let lines = (try? await LabelReader.read(image)) ?? []
            apply(LabelMatcher.suggest(from: lines))
        }
    }

    /// Fills in fields that are empty, or that an earlier scan filled in, so nothing typed by hand is replaced.
    private func apply(_ suggestion: LabelSuggestion) {
        guard !suggestion.isEmpty else {
            scanState = .unreadable
            return
        }
        if let scannedBrand = suggestion.brand,
           brand.trimmingCharacters(in: .whitespaces).isEmpty || brand == lastScan?.brand {
            brand = scannedBrand
        }
        if let styleName = suggestion.styleName,
           style == nil || style?.name == lastScan?.styleName,
           let found = try? StyleStore(context: context).style(named: styleName) {
            style = found
        }
        notes = LabelMatcher.mergedNotes(notes, adding: suggestion.notes)
        lastScan = suggestion
        scanState = .filled(suggestion)
        offerExistingBottle(for: brand)
    }

    /// Asks whether to add another bottle when the brand is already in My Bar.
    private func offerExistingBottle(for brandName: String) {
        let bottles = (try? BottleStore(context: context).bottles()) ?? []
        existingMatch = LabelMatcher.existingBottle(matching: brandName, in: bottles)
    }

    /// Adds one to the existing bottle's count (an Out bottle becomes Full) and closes the form.
    private func addAnother(to match: V1.Bottle) {
        do {
            try BottleStore(context: context).addAnotherBottle(to: match, photo: photo)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
