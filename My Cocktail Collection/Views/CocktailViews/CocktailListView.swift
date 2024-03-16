//
//  CocktailListView.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/24/24.
//

import SwiftUI
import UIKit

struct CocktailListView: View {
    @Environment(\.managedObjectContext) var context
    @FetchRequest(sortDescriptors: []) var drinks: FetchedResults<Drink>
    @FetchRequest(sortDescriptors: []) var spirits: FetchedResults<Spirit>
    @State private var selectedBaseSpirit: Spirit?
    @State private var searchText = ""
    @State private var isSearching = false
    @State var addDrink = false
    @State var sendMessage = false
    var isPreview = false
    
    var body: some View {
        NavigationView{
            VStack {
                Text("Filter by Base Spirit")
                    .font(.caption)
                Picker ("Selected Base Spirit", selection: $selectedBaseSpirit) {
                    Text("Show All").tag(nil as Spirit?)
                    ForEach(spirits) { spirit in
                        Text(spirit.spiritName ?? "")
                            .tag(spirit as Spirit?)
                    }
                }
                
            Divider()
                VStack {
                    HStack {
                        VStack {
                            TextField("Search Cocktails", text: $searchText)
                                .padding(.horizontal)
                        }
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        Spacer()
                        HStack {
                            Button ("Search") {
                                selectedBaseSpirit = nil
                                isSearching = true
                            }
                            if isSearching && !searchText.isEmpty {
                                Button ("Clear") {
                                    searchText = ""
                                    isSearching = false
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                HStack{
                    Text("Add new cocktail")
                        .padding()
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "plus")
                        .foregroundColor(/*@START_MENU_TOKEN@*/.blue/*@END_MENU_TOKEN@*/)
                        .padding()
                        .onTapGesture {
                            addDrink = true
                        }
                        .sheet(isPresented: $addDrink) {
                            AddEditCocktailRecipeView()
                        }
                }
                .frame(height: 25)
                Divider()
                List(filteredDrinks()) { drink in
                    NavigationLink(destination: CocktailDetailView(drinkID: drink.objectID)) {
                        HStack {
                            if let image = drink.image, let uiImage = UIImage(data: image) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                            } else {
                                Image("martini", bundle: Bundle.main)
                                    .resizable()
                                    .scaledToFit()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                            }
                            Text(drink.drinkName ?? "Unknown")
                                .font(.headline)
                                .swipeActions {
                                    /*Button("Share") {
                                        sendMessage = true
                                    }
                                    .sheet(isPresented: $sendMessage) {
                                        MessageComposer(isShowing: $sendMessage, cocktailName: drink.drinkName!, ingredients: drink.ingredients!, method: drink.method!)
                                    }
                                    .tint(.blue)*/
                                    Button("Delete") {
                                        context.delete(drink)
                                        try? context.save()
                                    }
                                    .tint(.red)
                                }
                            if drink.rating > 0 {
                                let rate = String(drink.rating)
                                Text("Rating: \(rate)")
                                    .font(.caption)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("My Cocktail Collection")
        }
    }
        
    private func filteredDrinks() -> [Drink] {
        if let baseSpirit = selectedBaseSpirit {
            return drinks.filter { $0.baseSpirit == baseSpirit.id }
        }
        
        if isSearching && !searchText.isEmpty {
            return drinks.filter { $0.drinkName?.localizedCaseInsensitiveContains(searchText) ?? false }
        }
        
        else {
            return Array(drinks)
        }
    }
}

struct CocktailListView_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        
        let spirit1 = Spirit(context: context)
        spirit1.id = UUID()
        spirit1.spiritName = "Rum"
        let spirit2 = Spirit(context: context)
        spirit2.id = UUID()
        spirit2.spiritName = "Vodka"
        
        let drink1 = Drink(context: context)
        drink1.drinkName = "Mojito"
        drink1.baseSpirit = spirit1.id
        drink1.rating = 10
        let drink2 = Drink(context: context)
        drink2.drinkName = "Cosmopolitan"
        drink2.baseSpirit = spirit2.id
        drink2.rating = 5
        
        try? context.save()
        
        return CocktailListView(isPreview: true)
            .environment(\.managedObjectContext, context)
    }
}
