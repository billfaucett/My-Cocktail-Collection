//
//  CocktailMenuDetailView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/1/24.
//

import SwiftUI

struct MenuDetailView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @State var addNewDrink = false
    var menu: Menu?
    
    var body: some View {
        Section {
            VStack {
                VStack {
                    HStack {
                        Button("Close"){
                            dismiss()
                        }
                        .padding(.horizontal)
                        Spacer()
                    }
                }
                Text("Menu Details")
                    .font(.title)
                    .padding()
                Spacer()
                HStack {
                    Text(menu?.menuName ?? "Not Found")
                    let date = menu?.dateCreated?.formatted()
                    Text(date ?? "no date")
                }
                Spacer()
                Divider()
                Button("Add Cocktail") {
                    addNewDrink = true
                }
                .sheet(isPresented: $addNewDrink){
                    AddMenuItemView(menu: menu)
                }
                Divider()
                MenuItemListView(menu: menu)
                Spacer()
                Divider()
            }
        }
    }
}

struct CocktailMenuDetailView_Preview: PreviewProvider {
    static var previews: some View {
        MenuDetailView()
    }
}
