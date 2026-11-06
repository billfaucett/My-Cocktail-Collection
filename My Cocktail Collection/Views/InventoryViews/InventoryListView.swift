//
//  InventoryListView.swift
//  My Cocktail Collection
//
//  The spirit inventory: every bottle on hand. Tap a bottle to edit it, or + to add one.
//

import SwiftUI
import CoreData

struct InventoryListView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: Inventory.sortByBrand, animation: .default)
    private var bottles: FetchedResults<Bottle>

    @State private var showAddBottle = false
    @State private var bottleToEdit: Bottle?
    @State private var bottleToDelete: Bottle?

    var body: some View {
        NavigationStack {
            ListScreen(
                "Spirit Inventory",
                isEmpty: bottles.isEmpty,
                emptyState: EmptyState(
                    title: "No Bottles Yet",
                    systemImage: "wineglass",
                    message: "Add the spirits you have on hand to keep track of what's in stock.",
                    actionTitle: "Add a Bottle"
                ),
                addLabel: "Add Bottle",
                onAdd: { showAddBottle = true }
            ) {
                ForEach(bottles) { bottle in
                    Button {
                        bottleToEdit = bottle
                    } label: {
                        BottleRow(bottle: bottle)
                    }
                    .foregroundStyle(.primary)
                    .deleteSwipeAction { bottleToDelete = bottle }
                }
            }
            .sheet(isPresented: $showAddBottle) {
                AddEditBottleView()
            }
            .sheet(item: $bottleToEdit) { bottle in
                AddEditBottleView(bottle: bottle)
            }
            .confirmDelete($bottleToDelete, title: "Delete Bottle?") { bottle in
                "\(bottle.brand ?? "This bottle") will be removed from your inventory."
            } onDelete: { bottle in
                do {
                    try Inventory(context: context).delete(bottle)
                } catch {
                    print("Failed to delete bottle: \(error)")
                }
            }
        }
    }
}

/// One bottle in the list: photo, brand, category, stock level and count.
struct BottleRow: View {
    @ObservedObject var bottle: Bottle

    var body: some View {
        ItemRow(
            bottle.brand ?? "Unnamed Bottle",
            subtitle: bottle.spirit?.spiritName ?? "No Category",
            thumbnail: Thumbnail(data: bottle.image, placeholder: .bottle),
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
    let context = DataController(inMemory: true).container.viewContext
    DataController.seedSpirits(context: context)
    let spirits = (try? context.fetch(NSFetchRequest<Spirit>(entityName: "Spirit"))) ?? []
    func spirit(_ name: String) -> Spirit? { spirits.first { $0.spiritName == name } }
    let inventory = Inventory(context: context)
    _ = try? inventory.addBottle(brand: "Buffalo Trace", spirit: spirit("Bourbon"), stock: .half, bottleCount: 2, isFavorite: true)
    _ = try? inventory.addBottle(brand: "Hendrick's", spirit: spirit("Gin"), stock: .full)
    _ = try? inventory.addBottle(brand: "Espolòn Blanco", spirit: spirit("Tequila"), stock: .low)
    _ = try? inventory.addBottle(brand: "Tito's", spirit: spirit("Vodka"), stock: .out, bottleCount: 0)
    return InventoryListView()
        .environment(\.managedObjectContext, context)
}

#Preview("Empty") {
    InventoryListView()
        .environment(\.managedObjectContext, DataController(inMemory: true).container.viewContext)
}
