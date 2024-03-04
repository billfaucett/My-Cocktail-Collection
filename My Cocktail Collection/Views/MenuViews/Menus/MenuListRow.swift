//
//  MenuListRow.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/4/24.
//

import SwiftUI
import CoreData

struct MenuListRow: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) var menuItems: FetchedResults<MenuItem>
    @State var deleteMenu = false
    var menu: Menu?
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "menucard")
                    .foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                    .padding()
                Text(menu?.menuName ?? "this is a menu name")
                    .padding()
                    .font(.headline)
                    .contextMenu {
                        Button(action: {
                            deleteMenu.toggle()
                            context.delete(menu!)
                            try? context.save()
                        }) {
                            Text("Delete")
                            Image(systemName: "trash")
                        }
                    }
                Spacer()
            }
            /*let menuItems = menuItems.filter({ $0.menu == menu })
            if !menuItems.isEmpty {
                List(menuItems) { item in
                    Text(item.drink?.drinkName ?? "drink")
                        .font(.caption)
                }
            }*/
        }
    }
}

struct MenuListRow_Preview: PreviewProvider {
    static var previews: some View {
        MenuListRow()
    }
}
