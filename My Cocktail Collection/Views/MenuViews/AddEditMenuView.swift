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
    
    @State var menu: Menu?
    
    var body: some View {
        ScrollView {
            VStack {
                Text("Create a Cocktail Menu")
                    .font(.title)
                    .padding()
                Divider()
                TextField("Menu Title", text: $menuTitle)
                    .padding()
                Button("Save Menu") {
                    saveMenu()
                }
                .padding()
                .alert(isPresented: $showAlert){
                    Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
                }
                .sheet(item: $menu) { savedMenu in
                    CocktailMenuDetailView(menu: savedMenu)
                }
                Divider()
            }
        }
    }
    
    private func saveMenu() {
        guard !menuTitle.isEmpty else {
            showAlert = true
            alertMessage = "Menu title cannot be empty."
            return
        }
        
        guard menu == nil else {
            showAlert = true
            alertMessage = "Cannot save existing menu."
            return
        }
        
        let newMenu = Menu(context: context)
        newMenu.id = UUID()
        newMenu.menuName = menuTitle
        newMenu.dateCreated = Date()
        
        do {
            try context.save()
            menu = newMenu
            menuIsSaved = true
        } catch {
            showAlert = true
            alertMessage = "Failed to save menu: \(error.localizedDescription)"
        }
    }
}



struct AddEditMenuView_Previews: PreviewProvider {
    static var previews: some View {
        AddEditMenuView()
    }
}
