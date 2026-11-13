//
//  SharedLibraryView.swift
//  My Cocktail Collection
//
//  Sync and sharing, step 4b: browse a library someone shares with you. Its cocktails open on the usual
//  recipe screen, which hides editing when the library is view only and offers Copy to My Cocktails.
//  Its menus can be looked at but not changed here.
//

import SwiftData
import SwiftUI

/// A library shared with you: its cocktails (searchable) and menus.
struct SharedLibraryView: View {
    let library: DB.Library

    @Query(sort: \DB.Cocktail.name) private var allCocktails: [DB.Cocktail]
    @Query(sort: \DB.Menu.dateCreated, order: .reverse) private var allMenus: [DB.Menu]
    @State private var searchText = ""

    var body: some View {
        // After the owner stops sharing, the library is removed; show a note while the screen is still up.
        if library.modelContext == nil || library.isDeleted {
            ContentUnavailableView("No Longer Shared", systemImage: "person.2.slash",
                                   description: Text("This library was removed because its owner stopped sharing it."))
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                Label(library.canEdit ? "You can edit this library. Changes are shared with everyone in it."
                                      : "View only. Copy any recipe to My Cocktails to make it your own.",
                      systemImage: library.canEdit ? "pencil" : "eye")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Cocktails") {
                if cocktails.isEmpty {
                    Text(searchText.isEmpty ? "No cocktails yet." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(cocktails) { cocktail in
                    NavigationLink {
                        CocktailDetailView(cocktail: cocktail)
                    } label: {
                        ItemRow(cocktail.name, subtitle: cocktail.baseStyle?.name,
                                thumbnail: Thumbnail(data: cocktail.photo, placeholder: .cocktail), isFavorite: false) {
                            EmptyView()
                        }
                    }
                }
            }

            if !menus.isEmpty && searchText.isEmpty {
                Section("Menus") {
                    ForEach(menus) { menu in
                        NavigationLink {
                            SharedMenuView(menu: menu)
                        } label: {
                            LabeledContent(menu.name, value: Self.cocktailCount(menu.orderedEntries.count))
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search \(library.name)")
        .navigationTitle(library.name)
    }

    private var cocktails: [DB.Cocktail] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return allCocktails.filter { cocktail in
            guard cocktail.library?.id == library.id else { return false }
            if query.isEmpty { return true }
            return cocktail.name.localizedCaseInsensitiveContains(query)
                || cocktail.orderedIngredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private var menus: [DB.Menu] {
        allMenus.filter { $0.library?.id == library.id }
    }

    /// "1 cocktail", "5 cocktails".
    static func cocktailCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "cocktail" : "cocktails")"
    }
}

/// A menu from a library shared with you, to look at. Its cocktails open on the recipe screen.
struct SharedMenuView: View {
    let menu: DB.Menu

    var body: some View {
        List {
            if !menu.notes.isEmpty {
                Section("Notes") {
                    Text(menu.notes)
                }
            }
            Section("Cocktails") {
                let cocktails = menu.orderedEntries.compactMap(\.cocktail)
                if cocktails.isEmpty {
                    Text("No cocktails on this menu.")
                        .foregroundStyle(.secondary)
                }
                ForEach(cocktails) { cocktail in
                    NavigationLink {
                        CocktailDetailView(cocktail: cocktail)
                    } label: {
                        ItemRow(cocktail.name, subtitle: cocktail.baseStyle?.name,
                                thumbnail: Thumbnail(data: cocktail.photo, placeholder: .cocktail), isFavorite: false) {
                            EmptyView()
                        }
                    }
                }
            }
        }
        .navigationTitle(menu.name)
    }
}

#Preview {
    let container = try! CocktailModelContainer.make(inMemory: true)
    let library = AppStartup.addSampleSharedLibrary(to: container.mainContext)
    return NavigationStack {
        SharedLibraryView(library: library)
    }
    .modelContainer(container)
}
