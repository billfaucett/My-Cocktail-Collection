//
//  MenuListRow.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/4/24.
//


import SwiftUI
import SwiftData

/// One menu in the list: name, date created and number of cocktails.
struct MenuListRow: View {
    let menu: DB.Menu

    private var subtitle: String {
        let count = menu.entries?.count ?? 0
        return [
            menu.dateCreated.formatted(date: .abbreviated, time: .omitted),
            count == 1 ? "1 cocktail" : "\(count) cocktails",
        ].joined(separator: " · ")
    }

    var body: some View {
        ItemRow(
            menu.name.isEmpty ? "Untitled Menu" : menu.name,
            subtitle: subtitle,
            thumbnail: Thumbnail(image: nil, placeholder: .menu)
        )
    }
}
