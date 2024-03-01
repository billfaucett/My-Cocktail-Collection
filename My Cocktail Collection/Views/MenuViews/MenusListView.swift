//
//  MenusListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI

struct MenusListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var menus: FetchedResults<Menu>
    
    var body: some View {
        NavigationView{
            VStack {
                if menus.count > 0 {
                    List(menus) { menu in
                        NavigationLink(destination: AddEditMenuView(menu: menu)){
                            HStack{
                                Text(menu.menuName ?? "??")
                            }
                        }
                    }
                } else {
                    Text("No Menus Found...")
                }
            }
        }
    }
}

struct MenusListView_Preview: PreviewProvider {
    static var previews: some View {
        MenusListView()
    }
}
