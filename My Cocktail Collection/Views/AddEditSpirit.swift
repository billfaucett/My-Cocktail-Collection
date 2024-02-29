//
//  AddEditSpirit.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/26/24.
//

import SwiftUI

struct AddEditSpirit: View {
    @Environment(\.managedObjectContext) var context
    @Environment(\.dismiss) private var dismiss
    @State var spiritName: String = ""
    @State var spiritType: SpiritType?
    @State private var showingAlert = false
    
    var spirit: Spirit?
    
    var body: some View {
        NavigationView {
            VStack{
                HStack {
                    Spacer()
                    Button("Save") {
                        saveSpirit()
                    }
                    .padding()
                    .padding()
                }
                HStack{
                    TextField("Spirit Name", text: $spiritName)
                        .padding()
                        .onAppear {
                            if let spirit = spirit {
                                spiritName = spirit.spiritName ?? ""
                            }
                        }
                    Picker("Spirit Type", selection: $spiritType) {
                        ForEach(SpiritType.allCases, id: \.self) { spiritType in
                            Text(spiritType.description)
                                .tag(spiritType as SpiritType?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding()
                    .onAppear {
                        if let spirit = spirit {
                            spiritType = SpiritType(rawValue: spirit.type)
                        }
                    }
                }
                Spacer()
            }
            .navigationTitle(spirit == nil ? "Add New Spirit" : "Edit Spirit")
        }
    }
    
    func saveSpirit() {
        guard let spirit = spirit else {
            let spirit = Spirit(context: context)
            spirit.id = UUID()
            spirit.spiritName = spiritName
            spirit.type = spiritType!.rawValue
            try? context.save()
            dismiss()
            return
        }
        
        spirit.spiritName = spiritName
        spirit.type = spiritType!.rawValue
        try? context.save()
        dismiss()
        return
    }
}

struct AddEditSpirit_Previews: PreviewProvider {
    static var previews: some View {
        let context = DataController.init().container.viewContext
        let newSpirit = Spirit(context: context)
        newSpirit.spiritName = "Whiskey"
        newSpirit.type = SpiritType.liquor.rawValue
        return AddEditSpirit(spirit: newSpirit)
            .environment(\.managedObjectContext, context)
    }
}


/*Button("Delete") {
    showingAlert = true
}
.padding()
.foregroundColor(.red)
.alert(isPresented: $showingAlert) {
    Alert(title: Text("Confirm Deletion"), message: Text("Are you sure you want to delete this drink?"), primaryButton: .destructive(Text("Delete")) {
        context.delete(spirit!)
        do {
            try context.save()
            dismiss()
        } catch {
            print("Error deleting drink: \(error)")
        }
    }, secondaryButton: .cancel())
}*/
