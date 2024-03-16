//
//  AddCocktailRecipe.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import CoreData
import UIKit

struct AddEditCocktailRecipeView: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Spirit.spiritName, ascending: true)]) var spirits: FetchedResults<Spirit>
    @State private var selectedSource: Int = 0
    @State private var selectedBaseSpirit: Spirit?
    @State private var selectedBaseSpiritId: UUID?
    @State private var drinkName: String = ""
    @State private var ingredients: String = ""
    @State private var method: String = ""
    @State private var isSaved = false
    @State private var selectedImage: UIImage?
    @State private var displayImage: UIImage?
    @State private var showImagePicker = false
    @State private var addSpirit = false
    @State var ratingValue: Int16 = 0
    
    var drink: Drink?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    HStack {
                        Button("Dismiss") {
                            dismiss()
                        }
                        .padding()
                        Spacer()
                        LinearGradient(gradient: Gradient(colors: [Color.white, Color.mint]), startPoint: /*@START_MENU_TOKEN@*/.leading/*@END_MENU_TOKEN@*/, endPoint: /*@START_MENU_TOKEN@*/.trailing/*@END_MENU_TOKEN@*/)
                            .frame(height: 20)
                        Button("Save") {
                            saveRecipe()
                        }
                        .padding()
                        .disabled(isSaved)
                    }
                    Section {
                        VStack {
                            HStack{
                                Text("Source")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            
                            Picker(selection: $selectedSource, label: Text("Source")) {
                                Text("Classic").tag(0)
                                Text("Website").tag(1)
                                Text("Menu").tag(2)
                                Text("Original").tag(3)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onAppear {
                                if let drink = drink {
                                    selectedSource = Int(drink.source)
                                }
                                if let spritId = drink?.baseSpirit {
                                    selectedBaseSpirit = spirits.first(where: { $0.id == spritId })
                                }
                            }
                        }
                        .padding()
                    }
                    Spacer()
                    Section {
                        VStack{
                            HStack{
                                Text("Drink Name")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            HStack {
                                TextField("Drink Name", text: $drinkName)
                                    .padding(.horizontal)
                                    .onTapGesture {
                                        hideKeyboard()
                                    }
                                    .onAppear {
                                        if let drink = drink {
                                            drinkName = drink.drinkName!
                                        }
                                    }
                                VStack {
                                    var img = setDisplayImage()
                                    Button(action: {
                                        showImagePicker.toggle()
                                        img = selectedImage ?? UIImage()
                                    }){
                                        if let image = selectedImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 50, height: 50)
                                                .padding(.horizontal)
                                        } else {
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .scaledToFit()
                                                .frame(width: 50, height: 50)
                                                .padding(.horizontal)
                                        }
                                    }
                                    Text("Touch to Change")
                                    .font(.caption2)
                                    .padding(.horizontal)
                                }
                            }
                            Spacer()
                        }
                        HStack {
                            Text("Base Spirit")
                                .font(.caption)
                            Spacer()
                            Picker(selection: $selectedBaseSpirit, label: Text("Base Spirit")) {
                                Text("Select a Base Spirit")
                                    .tag(nil as Spirit?)
                                ForEach(spirits) { spirit in
                                    Text(spirit.spiritName ?? "")
                                        .tag(spirit as Spirit?)
                                }
                            }
                            Button("Add Spirit") {
                                addSpirit = true
                            }
                            .sheet(isPresented: $addSpirit, onDismiss: refreshSpirits) {
                                AddEditSpirit()
                            }
                        }.padding()
                        HStack {
                            Text("Cocktail Rating")
                                .font(.caption)
                                .padding(.horizontal)
                            Spacer()
                            let ratingOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
                            Picker(selection: $ratingValue, label: Text("Add Rating")) {
                                Text("Add Rating")
                                    .tag(nil as Int16?)
                                ForEach(ratingOptions.indices, id: \.self) { index in
                                    Text(String(ratingOptions[index])) .tag(Int16(ratingOptions[index]) as Int16)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    Spacer()
                    Section {
                        VStack{
                            HStack{
                                Text("Ingredients")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            TextEditor(text: $ingredients)
                                .border(Color.gray, width: 1)
                                .frame(height: 200)
                                .padding(.horizontal)
                                .onTapGesture {
                                    hideKeyboard()
                                }
                                .onAppear {
                                    if let drink = drink {
                                        ingredients = drink.ingredients!
                                    }
                                }
                        }
                    }
                    Spacer()
                    Section {
                        VStack{
                            HStack{
                                Text("How to Make")
                                    .font(.caption)
                                Spacer()
                            } .padding(.horizontal)
                            TextEditor(text: $method)
                                .border(Color.gray, width: 1)
                                .frame(height: 200)
                                .padding(.horizontal)
                                .onTapGesture {
                                    hideKeyboard()
                                }
                                .onAppear {
                                    if let drink = drink {
                                        method = drink.method!
                                    }
                                }
                        }
                    }
                    .sheet(isPresented: $showImagePicker) {
                        ImagePicker(selectedImage: $selectedImage)
                    }
                }
                .onTapGesture {
                    hideKeyboard()
                }
            }
            .navigationTitle(drink == nil ? "Add a New Cocktail" : "Edit Cocktail")
        }
    }
    
    func setDisplayImage() -> UIImage {
        if let drink = drink, let uiImage = UIImage(data: drink.image ?? Data()) {
            return uiImage
        } else {
            let image = UIImage(imageLiteralResourceName: "martini")
            return image
        }
    }
    
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func refreshSpirits() {
        context.refreshAllObjects()
    }
    
    func saveRecipe() {
        guard let drink = drink else {
            let drink = Drink(context: context)
            drink.id = UUID()
            drink.baseSpirit = selectedBaseSpirit?.id
            drink.drinkName = drinkName
            drink.source = Int16(selectedSource)
            drink.ingredients = ingredients
            drink.method = method
            drink.rating = ratingValue
            if let image = selectedImage {
                _ = image.resized(to: CGSize(width: 300, height: 300))
                drink.image = image.pngData()
            }
            try? context.save()
            dismiss()
            isSaved = true
            return
        }
        
        drink.drinkName = drinkName
        drink.source = Int16(selectedSource)
        drink.baseSpirit = selectedBaseSpirit?.id
        drink.ingredients = ingredients
        drink.method = method
        drink.rating = ratingValue
        if let image = selectedImage {
            let resized = image.resized(to: CGSize(width: 300, height: 300))
            drink.image = resized.pngData()
        }
        try? context.save()
        dismiss()
        isSaved = true
    }
}

struct AddCocktailRecipeView_Previews: PreviewProvider {
    static var previews: some View {
        AddEditCocktailRecipeView()
    }
}

extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
