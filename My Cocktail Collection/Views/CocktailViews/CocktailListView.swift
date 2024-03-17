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
    @State var showAlert = false
    @State private var selectedSortOption = SortingOption.name
    var isPreview = false
    
    var body: some View {
        NavigationView{
            VStack {
                VStack {
                    HStack {
                        VStack{
                            Text("Filter by Base Spirit")
                                .font(.caption)
                            Picker ("Selected Base Spirit", selection: $selectedBaseSpirit) {
                                Text("Show All").tag(nil as Spirit?)
                                ForEach(spirits) { spirit in
                                    Text(spirit.spiritName ?? "")
                                        .tag(spirit as Spirit?)
                                }
                            }
                        }
                        .padding(.horizontal)
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
                HStack {
                    Spacer()
                    Text("Sort By")
                        .font(.caption)
                        .padding(.horizontal)
                    Picker("Sort Cocktails", selection: $selectedSortOption) {
                        ForEach(SortingOption.allCases, id: \.self) { option in
                            Text(option.rawValue)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                }
                .frame(height: 25)
                Divider()
                List(filteredDrinks().sorted(by: sortingComparator)) { drink in
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
                                    Button("Delete") {
                                        showAlert = true
                                    }
                                    .tint(.red)
                                }
                                .alert(isPresented: $showAlert) {
                                    Alert (
                                        title: Text("Confrim Delete"),
                                        message: Text("Are you sure you want to delete this cocktail?"),
                                        primaryButton: .destructive(Text("Delete")) {
                                            context.delete(drink)
                                            try? context.save()
                                        },
                                        secondaryButton: .cancel()
                                    )
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
    
    private func sortingComparator(_ drink1: Drink, _ drink2: Drink) -> Bool {
        switch selectedSortOption {
        case .name:
            return drink1.drinkName ?? "" < drink2.drinkName ?? ""
        case .rating:
            return drink1.rating > drink2.rating
        }
    }
}

enum SortingOption: String, CaseIterable {
    case name = "Name"
    case rating = "Rating"
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
