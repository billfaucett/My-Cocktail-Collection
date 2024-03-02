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
            Text("Number of Cocktails: \(String(menuItems.count))")
                .font(.caption2)
            let myMenuItems = menuItems.filter({ $0.menu == menu })
        
            List(myMenuItems) { item in
                VStack{
                    HStack {
                        Text(item.drink?.drinkName ?? "Where is my Drink Name?" )
                            .padding()
                    }
                    Text(item.drink?.ingredients ?? "")
                        .padding()
                        .lineLimit(nil)
                        .fixedSize(horizontal: true, vertical: false)
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
