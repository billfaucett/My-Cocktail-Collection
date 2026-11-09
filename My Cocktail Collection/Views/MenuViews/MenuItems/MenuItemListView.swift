//
//  MenuItemListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//


import SwiftUI
import SwiftData

/// One cocktail on a menu: photo, name, ingredients and favorite heart.
struct MenuEntryRow: View {
    let entry: V1.MenuEntry

    var body: some View {
        if let cocktail = entry.cocktail {
            ItemRow(
                cocktail.name,
                subtitle: MenuExporter.ingredientSummary(for: cocktail),
                thumbnail: Thumbnail(data: cocktail.photo, placeholder: .cocktail),
                isFavorite: cocktail.isFavorite
            )
        } else {
            ItemRow("Deleted Cocktail", thumbnail: Thumbnail(image: nil, placeholder: .cocktail))
        }
    }
}

/// Turns a menu into text for sharing or saving to the Files app.
enum MenuExporter {
    /// A cocktail's ingredients on one line, in parts: "2 parts Gin · ¾ part Lime Juice".
    static func ingredientSummary(for cocktail: V1.Cocktail) -> String {
        cocktail.orderedIngredients.map(\.displayText).joined(separator: " · ")
    }

    /// The menu as plain text: its name, then each cocktail in menu order with its ingredients.
    static func text(for menu: V1.Menu) -> String {
        let cocktails = menu.orderedEntries.compactMap(\.cocktail).map { cocktail in
            let ingredients = ingredientSummary(for: cocktail)
            return ingredients.isEmpty ? cocktail.name : "\(cocktail.name)\n\(ingredients)"
        }
        return ([menu.name] + cocktails).joined(separator: "\n\n") + "\n"
    }

    /// Saves the menu as a text file in the app's Documents/Menus folder, which appears in the Files app.
    /// - Returns: Where the file was saved.
    @discardableResult
    static func saveToFiles(_ menu: V1.Menu, folder: URL = URL.documentsDirectory.appendingPathComponent("Menus", isDirectory: true)) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(fileName(for: menu.name))
        try text(for: menu).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// A safe file name for a menu: "Friday Night.txt". Slashes and colons are removed.
    static func fileName(for menuName: String) -> String {
        let safeName = menuName
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (safeName.isEmpty ? "Menu" : safeName) + ".txt"
    }
}
