//
//  CocktailListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData

struct CocktailListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [], animation: .default)
    private var drinks: FetchedResults<Drink>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)])
    private var spirits: FetchedResults<Spirit>

    @State private var searchText = ""
    @State private var spiritFilter: Spirit?
    @State private var sortOption = SortingOption.name
    @State private var showAddDrink = false
    @State private var drinkToDelete: Drink?

    var body: some View {
        let spiritNames = spiritNamesByID
        let visible = visibleDrinks

        NavigationStack {
            ListScreen(
                "My Cocktails",
                isEmpty: visible.isEmpty,
                emptyState: emptyState,
                addLabel: "Add Cocktail",
                onAdd: { showAddDrink = true }
            ) {
                ForEach(visible) { drink in
                    NavigationLink(value: drink) {
                        CocktailRow(drink: drink, spiritName: drink.baseSpirit.flatMap { spiritNames[$0] })
                    }
                    .deleteSwipeAction { drinkToDelete = drink }
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

                Picker(selection: $spiritFilter) {
                    Text("All Spirits").tag(nil as Spirit?)
                    ForEach(spirits) { spirit in
                        Text(spirit.spiritName ?? "").tag(spirit as Spirit?)
                    }
                } label: {
                    Label("Base Spirit", systemImage: "line.3.horizontal.decrease.circle")
                }
                .pickerStyle(.menu)

                if !favoritesAdded {
                    Divider()
                    Button {
                        DataController.addBillsFaves(context: context)
                    } label: {
                        Label("Add Our Favorite Cocktails", systemImage: "heart")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search names and ingredients")
            .navigationDestination(for: Drink.self) { drink in
                CocktailDetailView(drink: drink)
            }
            .sheet(isPresented: $showAddDrink) {
                AddEditCocktailRecipeView()
            }
            .confirmDelete($drinkToDelete) { drink in
                "Are you sure you want to delete \(drink.drinkName ?? "this cocktail")?"
            } onDelete: { drink in
                DataController.delete(drink, context: context)
            }
        }
    }

    // MARK: Filtering and sorting

    private var visibleDrinks: [Drink] {
        var result = Array(drinks)
        if let spiritID = spiritFilter?.id {
            result = result.filter { $0.baseSpirit == spiritID }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter {
                ($0.drinkName ?? "").localizedCaseInsensitiveContains(query)
                    || ($0.ingredients ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        return result.sorted(by: sortingComparator)
    }

    private func sortingComparator(_ first: Drink, _ second: Drink) -> Bool {
        let byName = (first.drinkName ?? "").localizedCaseInsensitiveCompare(second.drinkName ?? "") == .orderedAscending
        switch sortOption {
        case .name:
            return byName
        case .rating:
            return first.rating == second.rating ? byName : first.rating > second.rating
        }
    }

    private var spiritNamesByID: [UUID: String] {
        var names: [UUID: String] = [:]
        for spirit in spirits {
            if let id = spirit.id {
                names[id] = spirit.spiritName ?? ""
            }
        }
        return names
    }

    private var favoritesAdded: Bool {
        drinks.contains { DataController.favoriteCocktailNames.contains($0.drinkName ?? "") }
    }

    private var emptyState: EmptyState {
        if drinks.isEmpty {
            return EmptyState(
                title: "No Cocktails Yet",
                systemImage: "wineglass",
                message: "Add your first recipe to start your collection.",
                actionTitle: "Add a Cocktail"
            )
        }
        return EmptyState(
            title: "No Matches",
            systemImage: "magnifyingglass",
            message: "No cocktails match your search or base spirit filter."
        )
    }
}

/// One cocktail in the list: photo, name, base spirit and rating.
struct CocktailRow: View {
    @ObservedObject var drink: Drink
    let spiritName: String?

    var body: some View {
        ItemRow(
            drink.drinkName ?? "Unnamed Cocktail",
            subtitle: spiritName,
            thumbnail: Thumbnail(data: drink.image, placeholder: .cocktail)
        ) {
            if drink.rating > 0 {
                StarRatingView(rating: Double(drink.rating) / 2.0)
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
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    DataController.seedCocktails(context: context)
    return CocktailListView()
        .environment(\.managedObjectContext, context)
}
