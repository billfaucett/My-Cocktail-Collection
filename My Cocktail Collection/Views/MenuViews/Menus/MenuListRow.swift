//
//  MenuListRow.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/4/24.
//

import SwiftUI
import CoreData

/// One menu in the list: name, date created and number of cocktails.
struct MenuListRow: View {
    @ObservedObject var menu: Menu
    let cocktailCount: Int

    init(menu: Menu, cocktailCount: Int) {
        _menu = ObservedObject(wrappedValue: menu)
        self.cocktailCount = cocktailCount
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = menu.dateCreated {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append(cocktailCount == 1 ? "1 cocktail" : "\(cocktailCount) cocktails")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ItemRow(
            menu.menuName ?? "Untitled Menu",
            subtitle: subtitle,
            thumbnail: Thumbnail(image: nil, placeholder: .menu)
        )
    }
}
