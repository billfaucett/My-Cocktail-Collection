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
    case style(DB.SpiritStyle)
}

/// The Cocktails tab. Reads the new SwiftData database (data model refactor, phase 5).
struct CocktailListView: View {
    @Environment(\.modelContext) private var context
    @Query(animation: .default) private var allCocktails: [DB.Cocktail]
    /// Only My Library; libraries shared with you are shown separately.
    private var cocktails: [DB.Cocktail] { allCocktails.filter { $0.library == nil } }

    @State private var searchText = ""
    @State private var filter = CocktailFilter.all
    /// Only cocktails following this Cocktail Codex template, or all when nil.
    @State private var templateFilter: CocktailTemplate?
    @State private var favoritesOnly = false
    @State private var showAddCocktail = false
    @State private var showSettings = false
    @State private var cocktailToDelete: DB.Cocktail?
    @State private var errorMessage: String?
    /// Libraries other people share with you, listed in the More menu.
    @Query(sort: \DB.Library.name) private var libraries: [DB.Library]
    @State private var openLibrary: DB.Library?
    private var syncStatus = CloudSyncStatus.shared

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
                        CocktailRow(cocktail: cocktail) {
                            run { try CocktailStore(context: context).toggleFavorite(cocktail) }
                        }
                    }
                    .deleteSwipeAction { cocktailToDelete = cocktail }
                    .favoriteSwipeAction(isFavorite: cocktail.isFavorite) {
                        run { try CocktailStore(context: context).toggleFavorite(cocktail) }
                    }
                }
            } moreMenu: {
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

                Picker(selection: $templateFilter) {
                    Text("All Templates").tag(nil as CocktailTemplate?)
                    ForEach(templatesInUse) { template in
                        TemplateLabel(template: template).tag(template as CocktailTemplate?)
                    }
                } label: {
                    Label("Template", systemImage: "square.grid.3x2")
                }
                .pickerStyle(.menu)

                let sharedWithYou = libraries.filter { !$0.isOwned }
                if !sharedWithYou.isEmpty {
                    Section("Shared With You") {
                        ForEach(sharedWithYou) { library in
                            Button {
                                openLibrary = library
                            } label: {
                                Label(library.name, systemImage: "person.2")
                            }
                        }
                    }
                }

                Divider()
                Button {
                    showSettings = true
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }

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
            .navigationDestination(for: DB.Cocktail.self) { cocktail in
                CocktailDetailView(cocktail: cocktail)
            }
            .navigationDestination(item: $openLibrary) { library in
                SharedLibraryView(library: library)
            }
            .sheet(isPresented: $showAddCocktail) {
                AddEditCocktailRecipeView()
            }
            .sheet(isPresented: $showSettings) {
                PartSizeSettingsView()
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
            .alert("No Longer Shared", isPresented: Binding(
                get: { syncStatus.notice != nil },
                set: { if !$0 { syncStatus.notice = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(syncStatus.notice ?? "")
            }
        }
    }

    // MARK: Filtering and sorting

    private var visibleCocktails: [DB.Cocktail] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return cocktails
            .filter { cocktail in
                switch filter {
                case .all: break
                case .family(let family): if cocktail.baseStyle?.family != family { return false }
                case .style(let style): if cocktail.baseStyle !== style { return false }
                }
                if let templateFilter, cocktail.template != templateFilter { return false }
                if favoritesOnly && !cocktail.isFavorite { return false }
                if query.isEmpty { return true }
                return cocktail.name.localizedCaseInsensitiveContains(query)
                    || (cocktail.ingredients ?? []).contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Templates at least one cocktail follows, in Cocktail Codex order.
    private var templatesInUse: [CocktailTemplate] {
        let used = Set(cocktails.compactMap(\.template))
        return CocktailTemplate.allCases.filter { used.contains($0) }
    }

    /// Families that at least one cocktail uses as its base, in display order.
    private var familiesInUse: [SpiritFamily] {
        let used = Set(cocktails.compactMap { $0.baseStyle?.family })
        return SpiritFamily.allCases.filter { used.contains($0) }
    }

    /// Base styles in use within a family, in display order.
    private func stylesInUse(in family: SpiritFamily) -> [DB.SpiritStyle] {
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
                          message: "No cocktails match your search, base spirit or template filter.")
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One cocktail in the list: photo, name, base spirit, and a heart to favorite it.
struct CocktailRow: View {
    let cocktail: DB.Cocktail
    /// Called when the heart is tapped. Leave out to show the heart beside the name instead, with no button.
    let onToggleFavorite: (() -> Void)?

    init(cocktail: DB.Cocktail, onToggleFavorite: (() -> Void)? = nil) {
        self.cocktail = cocktail
        self.onToggleFavorite = onToggleFavorite
    }

    var body: some View {
        ItemRow(
            cocktail.name,
            subtitle: cocktail.baseStyle?.name,
            thumbnail: Thumbnail(data: cocktail.photo, placeholder: .cocktail),
            isFavorite: onToggleFavorite == nil && cocktail.isFavorite
        ) {
            if let onToggleFavorite {
                FavoriteButton(isFavorite: cocktail.isFavorite, action: onToggleFavorite)
            }
        }
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    try? ModelSeeder.seedBuiltIns(context: container.mainContext, defaults: nil)
    return CocktailListView()
        .modelContainer(container)
}
