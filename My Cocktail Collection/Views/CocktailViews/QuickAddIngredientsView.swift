//
//  QuickAddIngredientsView.swift
//  My Cocktail Collection
//
//  Pick-from-list ingredient entry, step 2: add ingredients with a few taps and no typing.
//  Pick a measure and amount at the bottom, then tap an ingredient: "Parts → 2 → Bourbon".
//

import SwiftUI
import SwiftData

/// The measures offered in quick add, each with the amounts that suit it.
enum QuickMeasure: String, CaseIterable, Identifiable {
    case parts = "Parts"
    case dashes = "Dashes"
    case barspoons = "Barspoons"
    case count = "Count"
    case topUp = "Top Up"
    case garnish = "Garnish"

    var id: Self { self }

    var unit: IngredientUnit {
        switch self {
        case .parts: return .part
        case .dashes: return .dash
        case .barspoons: return .barspoon
        case .count: return .piece
        case .topUp: return .topUp
        case .garnish: return .unspecified
        }
    }

    /// The amount buttons for this measure. Top Up and Garnish have none.
    var amounts: [Double] {
        switch self {
        case .parts: return [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3]
        case .dashes: return [1, 2, 3, 4, 6]
        case .barspoons: return [0.5, 1, 2]
        case .count: return [1, 2, 3, 4, 6, 8]
        case .topUp, .garnish: return []
        }
    }

    /// The amount picked when switching to this measure.
    var defaultAmount: Double? {
        switch self {
        case .parts, .dashes: return 2
        case .barspoons, .count: return 1
        case .topUp, .garnish: return nil
        }
    }

    /// The recipe row for an ingredient picked with this measure, e.g. Parts, 2, Bourbon → "2 parts Bourbon".
    func row(for item: CatalogItem, amount: Double?, style: V1.SpiritStyle?) -> IngredientInput {
        switch self {
        case .garnish:
            return IngredientInput(unit: .unspecified, name: item.name, isGarnish: true)
        case .topUp:
            return IngredientInput(unit: .topUp, name: item.name, style: style)
        case .parts, .dashes, .barspoons, .count:
            return IngredientInput(amount: amount ?? defaultAmount, unit: unit, name: item.name, style: style)
        }
    }
}

/// Adds ingredients to a recipe by tapping: measure and amount at the bottom, ingredients in a searchable list.
/// Rows are added to `rows` straight away, so the recipe builds up as you go.
struct QuickAddIngredientsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var styles: [V1.SpiritStyle]
    @Binding private var rows: [IngredientInput]

    @State private var catalog = IngredientCatalog()
    /// Items added with "Add …" in this sheet, so they show in the list straight away.
    @State private var newItems: [CatalogItem] = []
    @State private var measure = QuickMeasure.parts
    @State private var amount: Double? = QuickMeasure.parts.defaultAmount
    @State private var searchText = ""
    /// Whether the search field is active. Picking an ingredient closes it, so the keyboard goes away
    /// and Done is back in the corner (an active search replaces it with Close).
    @State private var isSearching = false
    @State private var lastAdded: IngredientInput?
    @State private var addCount = 0

    init(rows: Binding<[IngredientInput]>) {
        _rows = rows
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    if !rows.isEmpty {
                        Section("In This Recipe") {
                            ForEach(rows) { row in
                                IngredientRowLabel(row: row)
                            }
                            .onDelete { rows.remove(atOffsets: $0) }
                        }
                    }
                    browseSections
                } else {
                    searchSection
                }
            }
            .searchable(text: $searchText, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search or add an ingredient")
            .autocorrectionDisabled()
            .navigationTitle("Add Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { measureBar }
            .sensoryFeedback(.impact(weight: .light), trigger: addCount)
            .task {
                if let loaded = try? IngredientCatalog.load(context: context) {
                    catalog = loaded
                }
            }
        }
    }

    // MARK: Ingredient list

    @ViewBuilder
    private var browseSections: some View {
        let mostUsed = catalog.mostUsed()
        if !mostUsed.isEmpty {
            Section("Most Used") {
                ForEach(mostUsed) { itemButton($0) }
            }
        }
        let inMyBar = catalog.inMyBar
        if !inMyBar.isEmpty {
            Section("In My Bar") {
                ForEach(inMyBar) { itemButton($0) }
            }
        }
        ForEach(CatalogGroup.allCases) { group in
            let items = (catalog.items(in: group) + newItems.filter { $0.group == group && catalog.item(named: $0.name) == nil })
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !items.isEmpty {
                Section(group.displayName) {
                    ForEach(items) { itemButton($0) }
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        let typedKey = IngredientCatalog.key(query)
        let extra = newItems.filter { $0.id.contains(typedKey) && catalog.item(named: $0.name) == nil }
        let results = catalog.search(query) + extra
        Section {
            if !results.contains(where: { $0.id == typedKey }) {
                Button {
                    addNew(named: query)
                } label: {
                    Label("Add “\(query)”", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("catalog.addNew")
            }
            ForEach(results) { itemButton($0) }
        } footer: {
            if results.isEmpty {
                Text("Not in the list yet. Add it, and it'll be here next time you use it in a recipe.")
            }
        }
    }

    private func itemButton(_ item: CatalogItem) -> some View {
        Button {
            add(item)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    if !item.bottleBrands.isEmpty {
                        Text("You have \(item.bottleBrands.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("catalog.\(item.name)")
    }

    // MARK: Measure and amount

    private var measureBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastAdded {
                HStack {
                    Label("Added \(lastAdded.displayText)", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Undo", action: undoLast)
                        .font(.footnote.weight(.semibold))
                }
            }
            chips(QuickMeasure.allCases, isSelected: { $0 == measure }, label: { $0.rawValue }, identifier: { "measure.\($0.rawValue)" }) {
                measure = $0
                amount = $0.defaultAmount
            }
            if measure.amounts.isEmpty {
                Text(measure == .topUp ? "Tap an ingredient to top up with it." : "Tap an ingredient to add it as a garnish.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 34)
            } else {
                chips(measure.amounts, isSelected: { $0 == amount }, label: { IngredientFormatter.amount($0) },
                      identifier: { "amount.\(IngredientFormatter.amount($0))" }) {
                    amount = $0
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func chips<Value: Hashable>(_ values: [Value], isSelected: @escaping (Value) -> Bool, label: @escaping (Value) -> String,
                                        identifier: @escaping (Value) -> String, action: @escaping (Value) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        action(value)
                    } label: {
                        Text(label(value))
                            .font(.subheadline.weight(isSelected(value) ? .semibold : .regular))
                            .frame(minWidth: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected(value) ? Color.accentColor : Color.gray)
                    .accessibilityIdentifier(identifier(value))
                    .accessibilityAddTraits(isSelected(value) ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Adding

    private func add(_ item: CatalogItem) {
        let style = item.styleName.flatMap { name in
            styles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        let row = measure.row(for: item, amount: amount, style: style)
        rows.append(row)
        lastAdded = row
        addCount += 1
        searchText = ""
        isSearching = false
    }

    private func addNew(named name: String) {
        let item = IngredientCatalog.newItem(named: name)
        guard !item.name.isEmpty else { return }
        newItems.append(item)
        add(item)
    }

    private func undoLast() {
        guard let lastAdded, let index = rows.lastIndex(where: { $0.id == lastAdded.id }) else { return }
        rows.remove(at: index)
        self.lastAdded = nil
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    return QuickAddIngredientsView(rows: .constant([]))
        .modelContainer(container)
}
