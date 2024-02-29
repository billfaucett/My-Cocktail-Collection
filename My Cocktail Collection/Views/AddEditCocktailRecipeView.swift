//
//  AddCocktailRecipe.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI

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
    @State private var showImagePicker = false
    var drink: Drink?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    HStack {
                        Spacer()
                        Button("Save") {
                            saveRecipe()
                        }
                        .padding()
                        .disabled(isSaved)
                    }
                    .padding()
                    
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
                            TextField("Drink Name", text: $drinkName)
                                .padding(.horizontal)
                                .onAppear {
                                    if let drink = drink {
                                        drinkName = drink.drinkName!
                                    }
                                }
                        }
                        HStack {
                            Text("Base Spirit")
                                .font(.caption)
                            Spacer()
                            Picker(selection: $selectedBaseSpirit, label: Text("Base Spirit")) {
                                ForEach(spirits) { spirit in
                                    Text("Select a Base Spirit").tag(nil as Spirit?)
                                    Text(spirit.spiritName ?? "")
                                        .tag(spirit as Spirit?)
                                }
                            }
                        }.padding()
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
                                .onAppear {
                                    if let drink = drink {
                                        method = drink.method!
                                    }
                                }
                        }
                    }
                    Section {
                        VStack {
                            HStack {
                                Text("Add an Image")
                                    .font(.caption)
                                    .padding()
                                Spacer()
                                Button("Select Image") {
                                    showImagePicker.toggle()
                                }
                                .padding()
                            }
                            if let image = selectedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200, alignment: .center)
                                    .padding()
                            } else {
                                Text("No Image Selected")
                                    .font(.caption)
                            }
                        }
                        .sheet(isPresented: $showImagePicker) {
                            ImagePicker(selectedImage: $selectedImage)
                        }
                    }
                }
            }
            .navigationTitle(drink == nil ? "Add a New Cocktail" : "Edit Cocktail")
        }
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
            if let image = selectedImage {
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
        if let image = selectedImage {
            drink.image = image.pngData()
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

