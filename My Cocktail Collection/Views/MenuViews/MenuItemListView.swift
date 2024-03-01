//
//  MenuItemListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI

struct MenuItemListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var menuItems: FetchedResults<MenuItem>
    var menu: Menu?
    
    var body: some View {
        VStack {
            Text("Menu: \(menu?.menuName ?? "None")")
            Text("count of drinks \(String(menuItems.count))")
            let myMenuItems = menuItems.filter({ $0.menu == menu })
            Text(menuItems.first?.menu?.menuName ?? "??")
            Text(menuItems.first?.drink?.drinkName ?? "??")
            Text(menuItems.first?.id?.uuidString ?? "no Id")
            List(menuItems) { item in
                HStack {
                    Text(item.menu?.menuName ?? "menu")
                    Text(item.drink?.drinkName ?? "drink" )
                }
            }
            List(myMenuItems) { item in
                HStack {
                    Text(item.drink?.drinkName ?? "Where is my Drink Name?" )
                }
            }
        }
    }
}

struct MenuItemListView_Previews: PreviewProvider {
    static var previews: some View {
        MenuItemListView()
    }
}
