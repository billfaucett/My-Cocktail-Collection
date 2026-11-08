//
//  AddEditStyleView.swift
//  My Cocktail Collection
//
//  Form for adding a style or editing one. Part of the data model refactor (phase 5).
//

import SwiftUI
import SwiftData

struct AddEditStyleView: View {
    @Environment(\.modelContext) private var context

    /// The style being edited, or nil when adding a new one.
    private let style: V1.SpiritStyle?

    @State private var name = ""
    @State private var family: SpiritFamily
    @State private var hasLoaded = false

    /// - Parameters:
    ///   - style: The style to edit. Leave out to add a new style.
    ///   - family: The family to pre-select when adding.
    init(style: V1.SpiritStyle? = nil, family: SpiritFamily = .other) {
        self.style = style
        _family = State(initialValue: style?.family ?? family)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        FormScreen(style == nil ? "Add Style" : "Edit Style", canSave: !trimmedName.isEmpty, onSave: save) {
            Section {
                TextField("Name (e.g. Bourbon, Amaro, Overproof Rum)", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Family", selection: $family) {
                    ForEach(SpiritFamily.allCases) { family in
                        Label(family.displayName, systemImage: family.symbolName).tag(family)
                    }
                }
            } footer: {
                Text("Styles group your bottles and set each cocktail's base spirit. The family decides where the style is listed.")
            }

            if let style {
                let bottles = style.bottles?.count ?? 0
                let cocktails = style.cocktails?.count ?? 0
                if bottles + cocktails > 0 {
                    Section("Used By") {
                        LabeledContent("Bottles", value: "\(bottles)")
                        LabeledContent("Cocktails", value: "\(cocktails)")
                    }
                }
            }
        }
        .onAppear(perform: loadStyle)
    }

    private func loadStyle() {
        guard !hasLoaded else { return }
        hasLoaded = true
        name = style?.name ?? ""
    }

    private func save() throws {
        let store = StyleStore(context: context)
        if let style {
            try store.update(style, name: name, family: family)
        } else {
            try store.addStyle(name: name, family: family)
        }
    }
}

#Preview("Add") {
    AddEditStyleView(family: .rum)
        .modelContainer(try! CocktailModelContainer.make(inMemory: true))
}
