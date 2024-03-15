//
//  MenuItemListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import SwiftUI
import UIKit

struct MenuItemListView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: []) var menuItems: FetchedResults<MenuItem>
    @State private var isSaved = false
    @State private var dismissView = false
    @State private var filePath = "Files/Cocktail Collection/Menus"
    
    var menu: Menu?
    
    var body: some View {
        VStack {
            let menuName = menu?.menuName ?? "None"
            Text("Menu: \(menuName)")
            Text("Number of Cocktails: \(String(menuItems.count))")
                .font(.caption2)
            var myMenuItems = menuItems.filter({ $0.menu == menu })
            
            if myMenuItems.count > 1 {
                HStack{
                    Spacer()
                    Button ("Save To Files") {
                        exportNotes(items: menuItems, menuName: menuName)
                    }
                    .padding(.horizontal)
                    .alert(isPresented: $isSaved) {
                        Alert(title: Text("Menu Saved"),
                        message: Text("Your Menu was saved to \(filePath)."),
                        dismissButton: .default(Text("OK")))
                    }
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
                        .swipeActions {
                            Button("Delete") {
                                context.delete(item)
                                try? context.save()
                            }
                            .tint(.red)
                        }
                }
            }
        }
    }
    
    func exportNotes(items: FetchedResults<MenuItem>, menuName: String) {
        var notes =  ""
        print(menuName)
        if #available(iOS 16.0, *) {
            print("Doc Dir: \(URL.documentsDirectory.absoluteString)")
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
            isSaved = true
        } catch {
            print("Error saving file \(error)")
        }
    }
}

struct MenuItemListView_Previews: PreviewProvider {
    static var previews: some View {
        MenuItemListView()
    }
}
