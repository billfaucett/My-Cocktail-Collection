//
//  InventoryListView.swift
//  My Cocktail Collection
//
//  The spirit inventory: every bottle on hand, grouped by family. Tap a bottle to edit it, or + to add one.
//

import SwiftUI
import SwiftData

/// Which bottles the inventory shows, by how much is left.
enum StockFilter: String, CaseIterable, Identifiable {
    case all = "All Bottles"
    case inStock = "In Stock"
    case shoppingList = "Shopping List"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .inStock: return "checkmark.circle"
        case .shoppingList: return "cart"
        }
    }

    func includes(_ level: StockLevel) -> Bool {
        switch self {
        case .all: return true
        case .inStock: return level.isInStock
        case .shoppingList: return level.needsRestock
        }
    }
}

/// The My Bar tab (the bottles you have). Reads the new SwiftData database (data model refactor, phase 5).
struct InventoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(animation: .default) private var bottles: [V1.Bottle]

    @State private var searchText = ""
    @State private var stockFilter = StockFilter.all
    /// Only this family's bottles, or every family when nil.
    @State private var familyFilter: SpiritFamily?
    @State private var favoritesOnly = false
    @State private var showAddBottle = false
    @State private var showScanBottle = false
    @State private var bottleToEdit: V1.Bottle?
    @State private var bottleToDelete: V1.Bottle?
    @State private var errorMessage: String?

    var body: some View {
        let visible = visibleBottles

        NavigationStack {
            ListScreen(
                title,
                isEmpty: visible.isEmpty,
                emptyState: emptyState,
                addLabel: "Add Bottle",
                onAdd: { showAddBottle = true },
                favoritesOnly: $favoritesOnly
            ) {
                ForEach(groups(of: visible), id: \.title) { group in
                    Section {
                        ForEach(group.bottles) { bottle in
                            Button {
                                bottleToEdit = bottle
                            } label: {
                                BottleRow(bottle: bottle)
                            }
                            .foregroundStyle(.primary)
                            .deleteSwipeAction { bottleToDelete = bottle }
                            .favoriteSwipeAction(isFavorite: bottle.isFavorite) {
                                run { try BottleStore(context: context).setFavorite(!bottle.isFavorite, for: bottle) }
                            }
                        }
                    } header: {
                        Label(group.title, systemImage: group.systemImage)
                    }
                }
            } moreMenu: {
                Picker(selection: $stockFilter) {
                    ForEach(StockFilter.allCases) { filter in
                        Label(filter.rawValue, systemImage: filter.systemImage).tag(filter)
                    }
                } label: {
                    Label("Show", systemImage: "line.3.horizontal.decrease.circle")
                }
                .pickerStyle(.inline)

                Picker(selection: $familyFilter) {
                    Text("All Families").tag(nil as SpiritFamily?)
                    ForEach(familiesInUse) { family in
                        Label(family.displayName, systemImage: family.symbolName).tag(family as SpiritFamily?)
                    }
                } label: {
                    Label("Family", systemImage: "square.stack.3d.up")
                }
                .pickerStyle(.menu)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showScanBottle = true
                    } label: {
                        Label("Scan a Bottle", systemImage: "camera.viewfinder")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search brands and types")
            .sheet(isPresented: $showAddBottle) {
                AddEditBottleView()
            }
            .sheet(isPresented: $showScanBottle) {
                AddEditBottleView(scanOnAppear: true)
            }
            .sheet(item: $bottleToEdit) { bottle in
                AddEditBottleView(bottle: bottle)
            }
            .confirmDelete($bottleToDelete, title: "Delete Bottle?") { bottle in
                "\(bottle.brand) will be removed from My Bar."
            } onDelete: { bottle in
                run { try BottleStore(context: context).delete(bottle) }
            }
            .alert("Something Went Wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Filtering and grouping

    private var visibleBottles: [V1.Bottle] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return bottles
            .filter { bottle in
                guard stockFilter.includes(bottle.stock) else { return false }
                if let familyFilter, bottle.style?.family != familyFilter { return false }
                if favoritesOnly && !bottle.isFavorite { return false }
                if query.isEmpty { return true }
                return bottle.brand.localizedCaseInsensitiveContains(query)
                    || (bottle.style?.name.localizedCaseInsensitiveContains(query) ?? false)
                    || (bottle.style?.family.displayName.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.brand.localizedCaseInsensitiveCompare($1.brand) == .orderedAscending }
    }

    /// Families with at least one bottle, in display order.
    private var familiesInUse: [SpiritFamily] {
        let used = Set(bottles.compactMap { $0.style?.family })
        return SpiritFamily.allCases.filter { used.contains($0) }
    }

    /// Bottles in family order (Whiskey, Gin, Rum…), with bottles that have no style last.
    private func groups(of bottles: [V1.Bottle]) -> [BottleGroup] {
        var groups = SpiritFamily.allCases.compactMap { family -> BottleGroup? in
            let inFamily = bottles.filter { $0.style?.family == family }
            return inFamily.isEmpty ? nil : BottleGroup(title: family.displayName, systemImage: family.symbolName, bottles: inFamily)
        }
        let noStyle = bottles.filter { $0.style == nil }
        if !noStyle.isEmpty {
            groups.append(BottleGroup(title: "No Type", systemImage: "questionmark.circle", bottles: noStyle))
        }
        return groups
    }

    /// "My Bar", "Shopping List", or the family when one is picked, e.g. "Whiskey".
    private var title: String {
        if let familyFilter {
            return stockFilter == .shoppingList ? "\(familyFilter.displayName) to Buy" : familyFilter.displayName
        }
        return stockFilter == .shoppingList ? "Shopping List" : "My Bar"
    }

    private var emptyState: EmptyState {
        if bottles.isEmpty {
            return EmptyState(title: "No Bottles Yet", systemImage: "wineglass",
                              message: "Add the spirits you have on hand to keep track of what's in stock.",
                              actionTitle: "Add a Bottle")
        }
        if stockFilter == .shoppingList && searchText.isEmpty && familyFilter == nil {
            return EmptyState(title: "Nothing to Buy", systemImage: "cart",
                              message: "Bottles marked Low or Out show up here.")
        }
        return EmptyState(title: "No Matches", systemImage: "magnifyingglass",
                          message: "No bottles match your search or filter.")
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One family's bottles in the inventory list.
private struct BottleGroup {
    let title: String
    let systemImage: String
    let bottles: [V1.Bottle]
}

/// One bottle in the list: photo, brand, style, stock level and count.
struct BottleRow: View {
    let bottle: V1.Bottle

    var body: some View {
        ItemRow(
            bottle.brand,
            subtitle: bottle.style?.name ?? "No Type",
            thumbnail: Thumbnail(data: bottle.photo, placeholder: .bottle),
            isFavorite: bottle.isFavorite
        ) {
            VStack(alignment: .trailing, spacing: 4) {
                Badge(bottle.stock.description, color: bottle.stock.color)
                if bottle.bottleCount > 1 {
                    Text("\(bottle.bottleCount) bottles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("With Bottles") {
    let container = try! CocktailModelContainer.make(inMemory: true)
    let context = container.mainContext
    try? ModelSeeder.addMissingStyles(context: context, defaults: nil)
    let styles = StyleStore(context: context)
    let bottles = BottleStore(context: context)
    _ = try? bottles.addBottle(brand: "Buffalo Trace", style: try? styles.style(named: "Bourbon"), stock: .half, bottleCount: 2, isFavorite: true)
    _ = try? bottles.addBottle(brand: "Hendrick's", style: try? styles.style(named: "London Dry"), stock: .full)
    _ = try? bottles.addBottle(brand: "Espolòn Blanco", style: try? styles.style(named: "Tequila Blanco"), stock: .low)
    _ = try? bottles.addBottle(brand: "Campari", style: try? styles.style(named: "Aperitivo"), stock: .out, bottleCount: 0)
    return InventoryListView()
        .modelContainer(container)
}

#Preview("Empty") {
    InventoryListView()
        .modelContainer(try! CocktailModelContainer.make(inMemory: true))
}
