//
//  PartSizeSettingsView.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 6: pick how big a part is, so recipes also show ounces or millilitres.
//

import SwiftUI

/// Settings for how recipes are shown. Changes apply straight away.
struct PartSizeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PartSize.storageKey) private var partSize = PartSize.off

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Part Size", selection: $partSize) {
                        ForEach(PartSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Part Size")
                } footer: {
                    Text("Recipes are kept in parts, so they work with any jigger. Pick a size to also see each amount in ounces or millilitres on the recipe screen.")
                }

                if partSize != .off {
                    Section("Example") {
                        ConvertedIngredientRow(text: "2 parts Bourbon", converted: partSize.converted(amount: 2))
                        ConvertedIngredientRow(text: "¾ part Lemon Juice", converted: partSize.converted(amount: 0.75))
                        ConvertedIngredientRow(text: "2 dashes Angostura Bitters", converted: nil)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// An ingredient line with its converted amount on the right, as the recipe screen shows it.
struct ConvertedIngredientRow: View {
    let text: String
    let converted: String?
    var isSecondary = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .foregroundStyle(isSecondary ? .secondary : .primary)
            if let converted {
                Spacer(minLength: 12)
                Text(converted)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    PartSizeSettingsView()
}
