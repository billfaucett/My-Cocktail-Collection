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
    
    @State private var menuIsSaved = false
    @State private var menuTitle: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    
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
                    AddMenuItemView(menu: menu)
                }
                .alert(isPresented: $showAlert){
                    Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
                }
                Divider()
                if menuIsSaved {
                    MenuItemListView(menu: menu)
                }
            }
        }
        .onAppear {
            if let menu = menu {
                menuTitle = menu.menuName ?? ""
            }
        }
    }
    
    private func saveMenu() {
        guard menu != nil else {
            let newMenu = Menu(context: context)
            newMenu.id = UUID()
            newMenu.menuName = menuTitle
            newMenu.dateCreated = Date()
            
            do {
                try context.save()
                menuIsSaved = true
            } catch {
                showAlert = true
                alertMessage = "Failed to save menu: \(error.localizedDescription)"
            }
            return
        }
    }
}


struct AddEditMenuView_Previews: PreviewProvider {
    static var previews: some View {
        AddEditMenuView()
    }
}
