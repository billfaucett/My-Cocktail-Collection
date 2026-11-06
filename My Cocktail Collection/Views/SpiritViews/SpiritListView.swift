//
//  SpiritListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/26/24.
//

import SwiftUI
import CoreData

struct SpiritListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "spiritName", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))],
        animation: .default
    )
    private var spirits: FetchedResults<Spirit>

    @State private var showAddSpirit = false
    @State private var spiritToEdit: Spirit?
    @State private var spiritToDelete: Spirit?

    var body: some View {
        NavigationStack {
            ListScreen(
                "Spirits",
                isEmpty: spirits.isEmpty,
                emptyState: EmptyState(
                    title: "No Spirits Yet",
                    systemImage: "drop",
                    message: "Spirits are the categories for your cocktails and inventory, like Bourbon or Gin.",
                    actionTitle: "Add a Spirit"
                ),
                addLabel: "Add Spirit",
                onAdd: { showAddSpirit = true }
            ) {
                ForEach(spirits) { spirit in
                    Button {
                        spiritToEdit = spirit
                    } label: {
                        SpiritRow(spirit: spirit)
                    }
                    .foregroundStyle(.primary)
                    .deleteSwipeAction { spiritToDelete = spirit }
                }
            }
            .sheet(isPresented: $showAddSpirit) {
                AddEditSpirit()
            }
            .sheet(item: $spiritToEdit) { spirit in
                AddEditSpirit(spirit: spirit)
            }
            .confirmDelete($spiritToDelete, title: "Delete Spirit?") { spirit in
                "\(spirit.spiritName ?? "This spirit") will be removed. Cocktails that use it will no longer show a base spirit, and its bottles will stay in your inventory without a category."
            } onDelete: { spirit in
                context.delete(spirit)
                context.saveOrRollback()
            }
        }
    }
}

/// One spirit in the list: name, how many bottles you have, and its type.
struct SpiritRow: View {
    @ObservedObject var spirit: Spirit

    private var bottleSummary: String {
        switch spirit.bottles?.count ?? 0 {
        case 0: return "No bottles in inventory"
        case 1: return "1 bottle in inventory"
        case let count: return "\(count) bottles in inventory"
        }
    }

    var body: some View {
        let type = SpiritType(rawValue: spirit.type) ?? .liquor
        ItemRow(spirit.spiritName ?? "Unnamed Spirit", subtitle: bottleSummary) {
            Badge(type.description, color: type.color)
        }
    }
}

#Preview {
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    return SpiritListView()
        .environment(\.managedObjectContext, context)
}
