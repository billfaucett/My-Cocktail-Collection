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
        NavigationView {
            let myMenuItems = menuItems.filter({ $0.menu == menu })
            List(myMenuItems) { item in
                HStack {
                    //Text(item.menu?.menuName ?? "")
                    Text(item.drink?.drinkName ?? "" )
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
