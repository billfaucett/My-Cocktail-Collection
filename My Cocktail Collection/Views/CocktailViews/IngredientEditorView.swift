//
//  IngredientEditorView.swift
//  My Cocktail Collection
//
//  Data model refactor, phase 6: edit one ingredient row with pickers instead of typing text,
//  and paste a recipe's ingredients as text to read them into rows.
//

import SwiftUI
import SwiftData

/// How an ingredient is measured, as offered in the editor.
enum Measure: String, CaseIterable, Identifiable {
    case parts, dashes, drops, barspoons, count, slices, sprigs, topUp, none

    var id: Self { self }

    var unit: IngredientUnit {
        switch self {
        case .parts: return .part
        case .dashes: return .dash
        case .drops: return .drop
        case .barspoons: return .barspoon
        case .count: return .piece
        case .slices: return .slice
        case .sprigs: return .sprig
        case .topUp: return .topUp
        case .none: return .unspecified
        }
    }

    init(unit: IngredientUnit) {
        self = Measure.allCases.first { $0.unit == unit } ?? .none
    }

    var displayName: String {
        switch self {
        case .parts: return "Parts"
        case .dashes: return "Dashes"
        case .drops: return "Drops"
        case .barspoons: return "Barspoons"
        case .count: return "Count (e.g. 1 egg white)"
        case .slices: return "Slices"
        case .sprigs: return "Sprigs"
        case .topUp: return "Top Up"
        case .none: return "No Amount"
        }
    }

    /// False for "top up" and "no amount", which have no number.
    var usesAmount: Bool { self != .topUp && self != .none }

    /// Parts and barspoons are often fractions; dashes, drops and counts are whole numbers.
    var allowsFractions: Bool { self == .parts || self == .barspoons || self == .count }
}

/// The fractions offered beside the whole-number stepper.
private let fractionOptions: [(value: Double, label: String)] = [
    (0, "0"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")
]

/// Splits an amount into a whole number and the nearest offered fraction.
private func splitAmount(_ value: Double) -> (whole: Int, fraction: Double) {
    var whole = Int(value.rounded(.down))
    let remainder = value - Double(whole)
    var fraction = fractionOptions.min { abs($0.value - remainder) < abs($1.value - remainder) }?.value ?? 0
    if 1 - remainder < abs(fraction - remainder) {
        whole += 1
        fraction = 0
    }
    return (whole, fraction)
}

/// An amount entered as a whole number plus a fraction, e.g. 1 and ½.
private struct AmountField: View {
    let title: String
    @Binding var whole: Int
    @Binding var fraction: Double
    let allowsFractions: Bool
    let unit: IngredientUnit

    /// The amount with its measure, e.g. "1½ parts".
    private var summary: String {
        let value = Double(whole) + (allowsFractions ? fraction : 0)
        return IngredientFormatter.line(amount: value, amountMax: nil, unit: unit, name: "",
                                        note: nil, isGarnish: false, isOptional: false)
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Stepper(value: $whole, in: 0...99) {
            HStack {
                Text(title)
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        if allowsFractions {
            Picker("\(title) fraction", selection: $fraction) {
                ForEach(fractionOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Edits one ingredient row: measure, amount (with an optional range), name, style,
/// garnish and optional switches, and a note. Shows the finished line as you go.
struct IngredientEditorView: View {
    private let isNew: Bool
    private let original: IngredientInput
    private let onDone: (IngredientInput) -> Void

    @State private var measure: Measure
    @State private var whole: Int
    @State private var fraction: Double
    @State private var isRange: Bool
    @State private var maxWhole: Int
    @State private var maxFraction: Double
    @State private var name: String
    @State private var style: V1.SpiritStyle?
    /// True once the style was picked by hand, so typing the name stops changing it.
    @State private var styleChosenByHand: Bool
    @State private var isGarnish: Bool
    @State private var isOptional: Bool
    @State private var note: String

    @Query private var styles: [V1.SpiritStyle]

    /// - Parameters:
    ///   - ingredient: The row to edit. Leave out to add a new one (1 part, no name).
    ///   - onDone: Called with the edited row when Done is tapped.
    init(ingredient: IngredientInput? = nil, onDone: @escaping (IngredientInput) -> Void) {
        let row = ingredient ?? IngredientInput(amount: 1, unit: .part)
        isNew = ingredient == nil
        original = row
        self.onDone = onDone
        let amount = splitAmount(row.amount ?? 1)
        let maxAmount = splitAmount(row.amountMax ?? (row.amount ?? 1) + 1)
        _measure = State(initialValue: Measure(unit: row.unit))
        _whole = State(initialValue: amount.whole)
        _fraction = State(initialValue: amount.fraction)
        _isRange = State(initialValue: row.amountMax != nil)
        _maxWhole = State(initialValue: maxAmount.whole)
        _maxFraction = State(initialValue: maxAmount.fraction)
        _name = State(initialValue: row.name)
        _style = State(initialValue: row.style)
        // An existing row keeps its style unless the user changes it; a new row follows the name.
        _styleChosenByHand = State(initialValue: ingredient != nil && row.style != nil)
        _isGarnish = State(initialValue: row.isGarnish)
        _isOptional = State(initialValue: row.isOptional)
        _note = State(initialValue: row.note ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var amount: Double? {
        guard measure.usesAmount else { return nil }
        return Double(whole) + (measure.allowsFractions ? fraction : 0)
    }

    private var amountMax: Double? {
        guard measure.usesAmount, isRange, let amount else { return nil }
        let top = Double(maxWhole) + (measure.allowsFractions ? maxFraction : 0)
        return top > amount ? top : nil
    }

    /// The row as it stands. Editing by hand means it no longer needs review.
    private var edited: IngredientInput {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var row = original
        row.amount = amount
        row.amountMax = amountMax
        row.unit = measure.unit
        row.name = trimmedName
        row.note = trimmedNote.isEmpty ? nil : trimmedNote
        row.isGarnish = isGarnish
        row.isOptional = isOptional
        row.style = style
        row.needsReview = false
        return row
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }
        guard measure.usesAmount else { return true }
        return (amount ?? 0) > 0
    }

    var body: some View {
        FormScreen(isNew ? "Add Ingredient" : "Edit Ingredient", saveTitle: "Done", canSave: canSave) {
            onDone(edited)
        } content: {
            Section("Preview") {
                Text(trimmedName.isEmpty ? "Enter a name below" : edited.displayText)
                    .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
                    .accessibilityIdentifier("ingredientPreview")
            }

            Section {
                Picker("Measure", selection: $measure) {
                    ForEach(Measure.allCases) { measure in
                        Text(measure.displayName).tag(measure)
                    }
                }
                if measure.usesAmount {
                    AmountField(title: isRange ? "From" : "Amount", whole: $whole, fraction: $fraction,
                                allowsFractions: measure.allowsFractions, unit: measure.unit)
                    Toggle("Range (e.g. 2 to 3)", isOn: $isRange.animation())
                    if isRange {
                        AmountField(title: "Up To", whole: $maxWhole, fraction: $maxFraction,
                                    allowsFractions: measure.allowsFractions, unit: measure.unit)
                    }
                }
            } header: {
                Text("Amount")
            } footer: {
                if measure == .parts {
                    Text("A part is whatever measure you use: a jigger, a shot, an ounce.")
                } else if isRange && measure.usesAmount && amountMax == nil {
                    Text("“Up to” should be more than the starting amount.")
                }
            }

            Section {
                TextField("Name (e.g. Bourbon, Lime Juice)", text: $name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { _, newName in
                        suggestStyle(for: newName)
                    }
                StylePicker(selection: Binding(
                    get: { style },
                    set: { newStyle in
                        style = newStyle
                        styleChosenByHand = true
                    }
                ), title: "Type")
            } header: {
                Text("Ingredient")
            } footer: {
                Text("The type links this ingredient to the bottles in My Bar. It's filled in from the name unless you pick one.")
            }

            Section("Details") {
                Toggle("Garnish", isOn: $isGarnish)
                Toggle("Optional", isOn: $isOptional)
                TextField("Note (e.g. freshly squeezed)", text: $note)
            }
        }
    }

    /// Fills in the style the name suggests (Campari → Aperitivo), until one is picked by hand.
    private func suggestStyle(for newName: String) {
        guard !styleChosenByHand else { return }
        guard let styleName = IngredientParser.styleName(forIngredient: newName) else {
            style = nil
            return
        }
        style = styles.first { $0.name.caseInsensitiveCompare(styleName) == .orderedSame }
    }
}

/// Paste or type a recipe's ingredients as text, one per line, to add them as rows.
struct PasteIngredientsView: View {
    @Environment(\.modelContext) private var context
    @State private var text = ""
    private let onAdd: ([IngredientInput]) -> Void

    init(onAdd: @escaping ([IngredientInput]) -> Void) {
        self.onAdd = onAdd
    }

    private var rows: [IngredientInput] {
        CocktailStore(context: context).rows(fromText: text)
    }

    var body: some View {
        FormScreen("Add from Text", saveTitle: "Add", canSave: !rows.isEmpty) {
            onAdd(rows)
        } content: {
            Section {
                TextField("2 oz Bourbon\n¾ oz Lemon Juice\n2 dashes Angostura Bitters", text: $text, axis: .vertical)
                    .lineLimit(6...16)
                    .autocorrectionDisabled()
            } header: {
                Text("Ingredients")
            } footer: {
                Text("One per line, or separated by commas. Ounces become parts; ml and cl are converted and marked for checking.")
            }

            if !rows.isEmpty {
                Section("Will Add \(rows.count)") {
                    ForEach(rows) { row in
                        IngredientRowLabel(row: row)
                    }
                }
            }
        }
    }
}

/// One ingredient row as shown in lists: the line, a warning when it needs checking, and its style.
struct IngredientRowLabel: View {
    let row: IngredientInput

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if row.needsReview {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Needs checking")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayText)
                    .foregroundStyle(.primary)
                if let style = row.style {
                    Text(style.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("New ingredient") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.addMissingStyles(context: container.mainContext, defaults: nil)
    return IngredientEditorView { _ in }
        .modelContainer(container)
}

#Preview("Paste") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.addMissingStyles(context: container.mainContext, defaults: nil)
    return PasteIngredientsView { _ in }
        .modelContainer(container)
}
