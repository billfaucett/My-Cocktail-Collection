//
//  CocktailListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import SwiftData

/// Which cocktails the base spirit filter shows.
enum CocktailFilter: Hashable {
    case all
    case family(SpiritFamily)
    case style(V1.SpiritStyle)
}

/// The Cocktails tab. Reads the new SwiftData database (data model refactor, phase 5).
struct CocktailListView: View {
    @Environment(\.modelContext) private var context
    @Query(animation: .default) private var cocktails: [V1.Cocktail]

    @State private var searchText = ""
    @State private var filter = CocktailFilter.all
    @State private var sortOption = SortingOption.name
    @State private var favoritesOnly = false
    @State private var showAddCocktail = false
    @State private var cocktailToDelete: V1.Cocktail?
    @State private var errorMessage: String?

    var body: some View {
        let visible = visibleCocktails

        NavigationStack {
            ListScreen(
                "My Cocktails",
                isEmpty: visible.isEmpty,
                emptyState: emptyState,
                addLabel: "Add Cocktail",
                onAdd: { showAddCocktail = true },
                favoritesOnly: $favoritesOnly
            ) {
                ForEach(visible) { cocktail in
                    NavigationLink(value: cocktail) {
                        CocktailRow(cocktail: cocktail)
                    }
                    .deleteSwipeAction { cocktailToDelete = cocktail }
                    .favoriteSwipeAction(isFavorite: cocktail.isFavorite) {
                        run { try CocktailStore(context: context).toggleFavorite(cocktail) }
                    }
                }
            } moreMenu: {
                Picker(selection: $sortOption) {
                    ForEach(SortingOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)

                Picker(selection: $filter) {
                    Text("All Cocktails").tag(CocktailFilter.all)
                    ForEach(familiesInUse) { family in
                        Section(family.displayName) {
                            Text("All \(family.displayName)").tag(CocktailFilter.family(family))
                            ForEach(stylesInUse(in: family)) { style in
                                Text(style.name).tag(CocktailFilter.style(style))
                            }
                        }
                    }
                } label: {
                    Label("Base Spirit", systemImage: "line.3.horizontal.decrease.circle")
                }
                .pickerStyle(.menu)

                if !houseFavoritesAdded {
                    Divider()
                    Button {
                        run { try ModelSeeder.addHouseFavorites(context: context) }
                    } label: {
                        Label("Add Our Favorite Cocktails", systemImage: "heart")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search names and ingredients")
            .navigationDestination(for: V1.Cocktail.self) { cocktail in
                CocktailDetailView(cocktail: cocktail)
            }
            .sheet(isPresented: $showAddCocktail) {
                AddEditCocktailRecipeView()
            }
            .confirmDelete($cocktailToDelete) { cocktail in
                "Are you sure you want to delete \(cocktail.name)?"
            } onDelete: { cocktail in
                run { try CocktailStore(context: context).delete(cocktail) }
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

    // MARK: Filtering and sorting

    private var visibleCocktails: [V1.Cocktail] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return cocktails
            .filter { cocktail in
                switch filter {
                case .all: break
                case .family(let family): if cocktail.baseStyle?.family != family { return false }
                case .style(let style): if cocktail.baseStyle !== style { return false }
                }
                if favoritesOnly && !cocktail.isFavorite { return false }
                if query.isEmpty { return true }
                return cocktail.name.localizedCaseInsensitiveContains(query)
                    || (cocktail.ingredients ?? []).contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .sorted { first, second in
                if sortOption == .rating && first.rating != second.rating {
                    return first.rating > second.rating
                }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
    }

    /// Families that at least one cocktail uses as its base, in display order.
    private var familiesInUse: [SpiritFamily] {
        let used = Set(cocktails.compactMap { $0.baseStyle?.family })
        return SpiritFamily.allCases.filter { used.contains($0) }
    }

    /// Base styles in use within a family, in display order.
    private func stylesInUse(in family: SpiritFamily) -> [V1.SpiritStyle] {
        var seen = Set<UUID>()
        return cocktails
            .compactMap(\.baseStyle)
            .filter { $0.family == family && seen.insert($0.id).inserted }
            .sorted(by: StyleStore.displayOrder)
    }

    private var houseFavoritesAdded: Bool {
        let names = Set(SeedData.favorites.map(\.name))
        return cocktails.contains { names.contains($0.name) }
    }

    private var emptyState: EmptyState {
        if cocktails.isEmpty {
            return EmptyState(title: "No Cocktails Yet", systemImage: "wineglass",
                              message: "Add your first recipe to start your collection.", actionTitle: "Add a Cocktail")
        }
        return EmptyState(title: "No Matches", systemImage: "magnifyingglass",
                          message: "No cocktails match your search or base spirit filter.")
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One cocktail in the list: photo, name, base style and rating.
struct CocktailRow: View {
    let cocktail: V1.Cocktail

    var body: some View {
        ItemRow(
            cocktail.name,
            subtitle: cocktail.baseStyle?.name,
            thumbnail: Thumbnail(data: cocktail.photo, placeholder: .cocktail),
            isFavorite: cocktail.isFavorite
        ) {
            if cocktail.rating > 0 {
                StarRatingView(rating: Double(cocktail.rating) / 2.0)
                    .font(.caption2)
            }
        }
    }
}

enum SortingOption: String, CaseIterable {
    case name = "Name"
    case rating = "Rating"
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    return CocktailListView()
        .modelContainer(container)
}
