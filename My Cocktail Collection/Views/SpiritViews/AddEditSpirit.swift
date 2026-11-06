//
//  AddEditSpirit.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/26/24.
//

import SwiftUI
import CoreData

struct AddEditSpirit: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var allSpirits: FetchedResults<Spirit>

    /// The spirit being edited, or nil when adding a new one.
    private let spirit: Spirit?

    @State private var spiritName = ""
    @State private var spiritType: SpiritType = .liquor
    @State private var hasLoaded = false

    /// - Parameter spirit: The spirit to edit. Leave out to add a new spirit.
    init(spirit: Spirit? = nil) {
        self.spirit = spirit
    }

    private var trimmedName: String { spiritName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        FormScreen(spirit == nil ? "Add Spirit" : "Edit Spirit", canSave: !trimmedName.isEmpty, onSave: save) {
            Section {
                TextField("Name (e.g. Bourbon, Amaro, Dry Vermouth)", text: $spiritName)
                    .textInputAutocapitalization(.words)
                Picker("Type", selection: $spiritType) {
                    ForEach(SpiritType.allCases, id: \.self) { type in
                        Text(type.description).tag(type)
                    }
                }
            } footer: {
                Text("Spirits are the categories used for your cocktails' base spirit and your inventory.")
            }
        }
        .onAppear(perform: loadSpirit)
    }

    private func loadSpirit() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let spirit else { return }
        spiritName = spirit.spiritName ?? ""
        spiritType = SpiritType(rawValue: spirit.type) ?? .liquor
    }

    private func save() throws {
        let name = trimmedName
        let isDuplicate = allSpirits.contains {
            $0 != spirit && ($0.spiritName ?? "").caseInsensitiveCompare(name) == .orderedSame
        }
        if isDuplicate {
            throw FormError("You already have a spirit named \(name).")
        }

        let target = spirit ?? Spirit(context: context)
        if spirit == nil {
            target.id = UUID()
        }
        target.spiritName = name
        target.type = spiritType.rawValue

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

#Preview("Add") {
    AddEditSpirit()
        .environment(\.managedObjectContext, DataController(inMemory: true).container.viewContext)
}

#Preview("Edit") {
    let context = DataController(inMemory: true).container.viewContext
    let spirit = Spirit(context: context)
    spirit.id = UUID()
    spirit.spiritName = "Amaro"
    spirit.type = SpiritType.liqueur.rawValue
    return AddEditSpirit(spirit: spirit)
        .environment(\.managedObjectContext, context)
}
