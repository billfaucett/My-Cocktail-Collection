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
            let menuName = menu?.menuName ?? "None"
            Text("Menu: \(menuName)")
            Text("Number of Cocktails: \(String(menuItems.count))")
                .font(.caption2)
            let myMenuItems = menuItems.filter({ $0.menu == menu })
            
            if myMenuItems.count > 1 {
                HStack{
                    Spacer()
                    Button ("Save") {
                        exportNotes(items: menuItems, menuName: menuName)
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
    
    func exportNotes(items: FetchedResults<MenuItem>, menuName: String) {
        var notes =  ""
        print(menuName)
        if #available(iOS 16.0, *) {
            print("Doc Dir: \(URL.documentsDirectory)")
        }
        
        for item in items {
            let name = item.drink?.drinkName
            let ingredientList = item.drink?.ingredients
            
            let output = ("\(name ?? "cocktail") - \(ingredientList ?? "")")
            notes.append(output)
            notes.append("\n\n")
        }
        
        let note_path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Menus", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: note_path.path) {
            do {
                try FileManager.default.createDirectory(at: note_path, withIntermediateDirectories: true, attributes: nil)
                print("Directory created successfully")
            } catch {
                print("Error creating Directory: \(error)")
            }
        }
        
        let escapedMenuName = menuName.replacingOccurrences(of: "/", with: "")
        let note_directory = note_path.appendingPathComponent(escapedMenuName + ".txt")
        
        print(note_directory.absoluteString)
        
        do {
            try notes.write(to: note_directory, atomically: true, encoding: .utf8)
            print("menu saved")
            let input = try String(contentsOf: note_directory)
            print(input)
            openFile(fileDir: note_directory)
        } catch {
            print("Error saving file \(error)")
        }
    }
    
    func openFile(fileDir: URL) {
        UIApplication.shared.open(fileDir)
    }
}

struct MenuItemListView_Previews: PreviewProvider {
    static var previews: some View {
        MenuItemListView()
    }
}
