//
//  MenuItemListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI
import CoreData

/// One cocktail on a menu: photo, name, ingredients and favorite heart.
struct MenuItemRow: View {
    @ObservedObject var item: MenuItem

    var body: some View {
        if let drink = item.drink {
            MenuDrinkRow(drink: drink)
        } else {
            ItemRow("Deleted Cocktail", thumbnail: Thumbnail(image: nil, placeholder: .cocktail))
        }
    }
}

/// Watches the cocktail itself, so edits and favorites show up right away.
private struct MenuDrinkRow: View {
    @ObservedObject var drink: Drink

    var body: some View {
        ItemRow(
            drink.drinkName ?? "Unnamed Cocktail",
            subtitle: drink.ingredients,
            thumbnail: Thumbnail(data: drink.image, placeholder: .cocktail),
            isFavorite: drink.isFavorite
        )
    }
}

/// Turns a menu into text for sharing or saving to the Files app.
enum MenuExporter {
    /// The menu as plain text: each cocktail's name and ingredients.
    static func text(for items: [MenuItem], menuName: String) -> String {
        let cocktails = items.map { item in
            "\(item.drink?.drinkName ?? "Cocktail") - \(item.drink?.ingredients ?? "")"
        }
        return ([menuName] + cocktails).joined(separator: "\n\n") + "\n"
    }

    /// Saves the menu as a text file in the app's Documents/Menus folder, which appears in the Files app.
    /// - Returns: Where the file was saved.
    @discardableResult
    static func saveToFiles(items: [MenuItem], menuName: String) throws -> URL {
        let folder = URL.documentsDirectory.appendingPathComponent("Menus", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let safeName = menuName
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let file = folder.appendingPathComponent((safeName.isEmpty ? "Menu" : safeName) + ".txt")
        try text(for: items, menuName: menuName).write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
