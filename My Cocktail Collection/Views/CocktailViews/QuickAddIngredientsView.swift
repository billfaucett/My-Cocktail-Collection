//
//  QuickAddIngredientsView.swift
//  My Cocktail Collection
//
//  Pick-from-list ingredient entry: add ingredients with a few taps and no typing.
//  Tap an ingredient and its row opens with amounts in its usual measure ("Bourbon → 2");
//  garnishes and top-ups are added with one tap.
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
    case noAmount = "No Amount"

    var id: Self { self }

    var unit: IngredientUnit {
        switch self {
        case .parts: return .part
        case .dashes: return .dash
        case .barspoons: return .barspoon
        case .count: return .piece
        case .topUp: return .topUp
        case .garnish, .noAmount: return .unspecified
        }
    }

    /// The measure an ingredient is usually picked in: Angostura → Dashes, Club Soda → Top Up, Orange Peel → Garnish.
    init(for item: CatalogItem) {
        if item.isGarnish {
            self = .garnish
            return
        }
        switch item.usualUnit {
        case .part: self = .parts
        case .dash, .drop: self = .dashes
        case .barspoon: self = .barspoons
        case .piece, .slice, .sprig: self = .count
        case .topUp: self = .topUp
        case .unspecified: self = .noAmount
        }
    }

    /// The word shown on the measure menu in an open row, e.g. "parts".
    var menuLabel: String {
        switch self {
        case .count: return "count"
        default: return rawValue.lowercased()
        }
    }

    /// The amount buttons for this measure. Top Up and Garnish have none.
    var amounts: [Double] {
        switch self {
        case .parts: return [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3]
        case .dashes: return [1, 2, 3, 4, 6]
        case .barspoons: return [0.5, 1, 2]
        case .count: return [1, 2, 3, 4, 6, 8]
        case .topUp, .garnish, .noAmount: return []
        }
    }

    /// The amount picked when switching to this measure.
    var defaultAmount: Double? {
        switch self {
        case .parts, .dashes: return 2
        case .barspoons, .count: return 1
        case .topUp, .garnish, .noAmount: return nil
        }
    }

    /// The amount buttons for an ingredient: the usual ones, plus your usual amount if it isn't among them.
    func amounts(for item: CatalogItem) -> [Double] {
        guard !amounts.isEmpty else { return [] }
        guard let usual = highlightedAmount(for: item), !amounts.contains(usual) else { return amounts }
        return (amounts + [usual]).sorted()
    }

    /// The amount to highlight: your usual amount when this is the ingredient's usual measure, otherwise the default.
    func highlightedAmount(for item: CatalogItem) -> Double? {
        guard !amounts.isEmpty else { return nil }
        if self == QuickMeasure(for: item), let usual = item.usualAmount {
            return usual
        }
        return defaultAmount
    }

    /// The recipe row for an ingredient picked with this measure, e.g. Parts, 2, Bourbon → "2 parts Bourbon".
    func row(for item: CatalogItem, amount: Double?, style: V1.SpiritStyle?) -> IngredientInput {
        switch self {
        case .garnish:
            return IngredientInput(unit: .unspecified, name: item.name, isGarnish: true)
        case .topUp:
            return IngredientInput(unit: .topUp, name: item.name, style: style)
        case .noAmount:
            return IngredientInput(unit: .unspecified, name: item.name, style: style)
        case .parts, .dashes, .barspoons, .count:
            return IngredientInput(amount: amount ?? defaultAmount, unit: unit, name: item.name, style: style)
        }
    }
}

/// Adds ingredients to a recipe by tapping. Tap an ingredient and its row opens with amount buttons in its
/// usual measure, your usual amount highlighted; tap an amount to add it. Garnishes and top-ups add with one tap.
/// Rows are added to `rows` straight away, so the recipe builds up as you go.
struct QuickAddIngredientsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var styles: [V1.SpiritStyle]
    @Binding private var rows: [IngredientInput]

    @State private var catalog = IngredientCatalog()
    /// Items added with "Add …" in this sheet, so they show in the list straight away.
    @State private var newItems: [CatalogItem] = []
    @State private var searchText = ""
    /// Whether the search field is active. Adding an ingredient closes it, so the keyboard goes away
    /// and Done is back in the corner (an active search replaces it with Close).
    @State private var isSearching = false
    /// The open row, as section + ingredient, since an ingredient can appear in more than one section.
    @State private var expandedKey: String?
    @State private var expandedMeasure = QuickMeasure.parts
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
            .safeAreaInset(edge: .bottom) { addedBanner }
            .sensoryFeedback(.impact(weight: .light), trigger: addCount)
            .animation(.snappy(duration: 0.2), value: expandedKey)
            .task {
                if let loaded = try? IngredientCatalog.load(context: context) {
                    catalog = loaded
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var browseSections: some View {
        let goesWith = catalog.goesWith(rows.map(\.name))
        if !goesWith.isEmpty {
            Section("Goes With") {
                ForEach(goesWith) { itemRow($0, in: "goesWith") }
            }
        }
        let mostUsed = catalog.mostUsed()
        if !mostUsed.isEmpty {
            Section("Most Used") {
                ForEach(mostUsed) { itemRow($0, in: "mostUsed") }
            }
        }
        let inMyBar = catalog.inMyBar
        if !inMyBar.isEmpty {
            Section("In My Bar") {
                ForEach(inMyBar) { itemRow($0, in: "myBar") }
            }
        }
        ForEach(CatalogGroup.allCases) { group in
            let items = (catalog.items(in: group) + newItems.filter { $0.group == group && catalog.item(named: $0.name) == nil })
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !items.isEmpty {
                Section(group.displayName) {
                    ForEach(items) { itemRow($0, in: group.rawValue) }
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
            ForEach(results) { itemRow($0, in: "search") }
        } footer: {
            if results.isEmpty {
                Text("Not in the list yet. Add it, and it'll be here next time you use it in a recipe.")
            }
        }
    }

    // MARK: Rows

    /// An ingredient: tap to open its amounts (or add it straight away when it has no amount).
    private func itemRow(_ item: CatalogItem, in section: String) -> some View {
        let key = section + "|" + item.id
        let isExpanded = expandedKey == key
        let oneTap = QuickMeasure(for: item).amounts.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                tap(item, key: key)
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
                    Image(systemName: oneTap ? "plus.circle" : (isExpanded ? "chevron.up" : "chevron.down"))
                        .font(oneTap ? .body : .footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("catalog.\(item.name)")
            .accessibilityHint(oneTap ? "Adds it to the recipe" : "Shows amounts")

            if isExpanded {
                amountPicker(for: item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Amount buttons in the chosen measure, the highlighted one first in mind, and a menu to change the measure.
    private func amountPicker(for item: CatalogItem) -> some View {
        let amounts = expandedMeasure.amounts(for: item)
        let highlighted = expandedMeasure.highlightedAmount(for: item)
        return HStack(spacing: 8) {
            if amounts.isEmpty {
                Button(expandedMeasure == .garnish ? "Add as Garnish" : (expandedMeasure == .topUp ? "Add to Top Up" : "Add")) {
                    add(item, measure: expandedMeasure, amount: nil)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("amount.add")
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(amounts, id: \.self) { amount in
                            Button {
                                add(item, measure: expandedMeasure, amount: amount)
                            } label: {
                                Text(IngredientFormatter.amount(amount))
                                    .font(.subheadline.weight(amount == highlighted ? .semibold : .regular))
                                    .frame(minWidth: 28)
                            }
                            .buttonStyle(.bordered)
                            .tint(amount == highlighted ? Color.accentColor : Color.gray)
                            .accessibilityIdentifier("amount.\(IngredientFormatter.amount(amount))")
                            .accessibilityLabel("\(IngredientFormatter.amount(amount)) \(expandedMeasure.menuLabel)")
                        }
                    }
                }
            }
            SwiftUI.Menu {
                Picker("Measure", selection: $expandedMeasure) {
                    ForEach(QuickMeasure.allCases) { measure in
                        Text(measure.rawValue).tag(measure)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(expandedMeasure.menuLabel)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("measureMenu")
            .accessibilityLabel("Measure: \(expandedMeasure.rawValue)")
        }
    }

    /// After adding: what was added, with Undo.
    @ViewBuilder
    private var addedBanner: some View {
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
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: Adding

    /// Opens or closes an ingredient's amounts, or adds it straight away when it has no amount.
    private func tap(_ item: CatalogItem, key: String) {
        let measure = QuickMeasure(for: item)
        if measure.amounts.isEmpty {
            add(item, measure: measure, amount: nil)
        } else if expandedKey == key {
            expandedKey = nil
        } else {
            expandedMeasure = measure
            expandedKey = key
        }
    }

    private func add(_ item: CatalogItem, measure: QuickMeasure, amount: Double?) {
        let style = item.styleName.flatMap { name in
            styles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        let row = measure.row(for: item, amount: amount, style: style)
        rows.append(row)
        lastAdded = row
        addCount += 1
        expandedKey = nil
        searchText = ""
        isSearching = false
    }

    /// Adds a name that isn't in the list: opens its amounts, or adds it straight away when it has no amount.
    private func addNew(named name: String) {
        let item = IngredientCatalog.newItem(named: name)
        guard !item.name.isEmpty else { return }
        newItems.append(item)
        tap(item, key: "search|" + item.id)
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
