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
    @State var menuNotesText: String = "This will hold the menu items for notes"
    var menu: Menu?
    
    var body: some View {
        VStack {
            Text("Menu: \(menu?.menuName ?? "None")")
            Text("Number of Cocktails: \(String(menuItems.count))")
                .font(.caption2)
            let myMenuItems = menuItems.filter({ $0.menu == menu })
            
            if myMenuItems.count > 1 {
                HStack{
                    Spacer()
                    Button ("Export") {
                        exportNotes(items: menuItems)
                    }
                    .padding(.horizontal)
                }
            }
        
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
    
    func exportNotes(items: FetchedResults<MenuItem>) {
        var notes =  ""
        for item in items {
            let name = item.drink?.drinkName
            let ing = item.drink?.ingredients
            
            let output = ("\(String(describing: name))/n\(ing ?? "")")
            notes.append(output)
            notes.append("\n\n")
        }
        
        if let notesURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("menu_items.txt") {
            do {
                try notes.write(to: notesURL, atomically: true, encoding: .utf8)
                print(notes)
                let interactController = UIDocumentInteractionController(url: notesURL)
                interactController.presentOptionsMenu(from: CGRect.zero, in: UIApplication.shared.keyWindow!.rootViewController!.view, animated: true)

            } catch {
                print("Failed: \(error)")
            }
        } else {
            print("Failed to get directory URL")
        }
    }
}

struct MenuItemListView_Previews: PreviewProvider {
    static var previews: some View {
        MenuItemListView()
    }
}
