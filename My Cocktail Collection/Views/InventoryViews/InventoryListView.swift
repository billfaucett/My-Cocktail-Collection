//
//  InventoryListView.swift
//  My Cocktail Collection
//
//  The spirit inventory: every bottle on hand. Tap a bottle to edit it, or + to add one.
//

import SwiftUI
import CoreData

struct InventoryListView: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: Inventory.sortByBrand, animation: .default)
    private var bottles: FetchedResults<Bottle>

    @State private var showAddBottle = false
    @State private var bottleToEdit: Bottle?

    var body: some View {
        NavigationStack {
            Group {
                if bottles.isEmpty {
                    ContentUnavailableView {
                        Label("No Bottles Yet", systemImage: "wineglass")
                    } description: {
                        Text("Add the spirits you have on hand to keep track of what's in stock.")
                    } actions: {
                        Button("Add a Bottle") { showAddBottle = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(bottles) { bottle in
                        Button {
                            bottleToEdit = bottle
                        } label: {
                            BottleRow(bottle: bottle)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Spirit Inventory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddBottle = true
                    } label: {
                        Label("Add Bottle", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddBottle) {
                AddEditBottleView()
            }
            .sheet(item: $bottleToEdit) { bottle in
                AddEditBottleView(bottle: bottle)
            }
        }
    }
}

/// One bottle in the list: photo, brand, category, stock level and count.
struct BottleRow: View {
    @ObservedObject var bottle: Bottle

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = bottle.image, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "wineglass")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.secondarySystemBackground))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(bottle.brand ?? "Unnamed Bottle")
                        .font(.headline)
                    if bottle.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(bottle.spirit?.spiritName ?? "No Category")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StockBadge(level: bottle.stock)
                if bottle.bottleCount > 1 {
                    Text("\(bottle.bottleCount) bottles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A small coloured label for a stock level.
struct StockBadge: View {
    let level: StockLevel

    var body: some View {
        Text(level.description)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(level.color)
            .background(level.color.opacity(0.15), in: Capsule())
    }
}

extension StockLevel {
    var color: Color {
        switch self {
        case .full: return .green
        case .half: return .teal
        case .low: return .orange
        case .out: return .red
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
