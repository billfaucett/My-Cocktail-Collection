//
//  MenusListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI

struct MenusListView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) var menus: FetchedResults<Menu>
    @State var addMenu = false
    @State var deleteMenu = false
    
    var body: some View {
        NavigationView{
            VStack {
                VStack {
                    HStack {
                        Button("Close") {
                            dismiss()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        Spacer()
                    }
                    HStack {
                        Text("Create a Menu")
                            .padding()
                        Spacer()
                        Image(systemName: "plus")
                            .padding(.horizontal)
                            .foregroundColor(.blue)
                            .onTapGesture {
                                addMenu = true
                            }
                            .sheet(isPresented: $addMenu) {
                                AddEditMenuView()
                            }
                    }
                    Divider()
                }
                if menus.count > 0 {
                    List(menus) { menu in
                        NavigationLink(destination: MenuDetailView(menu: menu)){
                            HStack{
                                MenuListRow(menu: menu)
                            }
                        }
                    }
                } else {
                    Text("No Menus Found...")
                }
            }
        }.navigationTitle("Your Cocktail Menus")
    }
    
    func deleteMenuItems() {
        DeleteHelper().deleteAllRowsFromEntity(entity: MenuItem.self, context: context)
    }
}

struct MenusListView_Preview: PreviewProvider {
    static var previews: some View {
        MenusListView()
    }
}
