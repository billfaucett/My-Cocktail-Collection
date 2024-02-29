//
//  AddEditMenuView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI

struct AddEditMenuView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var menuItems: FetchedResults<MenuItem>
    @Environment(\.dismiss) private var dismiss
    
    @State var menuIsSaved = false
    @State var menuTitle: String = ""
    
    var menu: Menu?
    
    var body: some View {
        ScrollView {
            VStack {
                Text("Create a Cocktail Menu")
                    .font(.title)
                    .padding()
                Divider()
                TextField("Menu Title", text: $menuTitle)
                    .padding()
                Button("Add a Menu Item") {
                    if !menuIsSaved {
                        saveMenu()
                    } else {
                        menuIsSaved = true
                    }
                }
                .padding()
                .sheet(isPresented: $menuIsSaved) {
                    AddMenuItemView(menuId: menu?.id)
                }
                Divider()
                if menuIsSaved {
                    MenuItemListView(menu: menu)
                }
            }
        }
    }
    
    func saveMenu() {
        guard let menu = menu else {
            menu?.id = UUID()
            menu?.menuName = menuTitle
            menu?.dateCreated = Date()
            
            try? context.save()
            menuIsSaved = true
            return
        }
        
        menu.menuName = menuTitle
    }
}

struct AddEditMenuView_Previews: PreviewProvider {
    static var previews: some View {
        AddEditMenuView()
    }
}
