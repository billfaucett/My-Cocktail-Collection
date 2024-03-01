//
//  ImagePicker.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 2/29/24.
//

import Foundation
import SwiftUI
import CoreData

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedImage: UIImage?

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No need to implement anything here
    }
}

struct DeleteHelper {
    func deleteAllRowsFromEntity<T: NSManagedObject>(entity: T.Type, context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: entity))
        
        do {
            let objects = try context.fetch(fetchRequest)
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try context.execute(batchDeleteRequest)
            try context.save()
        } catch {
            print("Error deleting all rows from \(entity): \(error.localizedDescription)")
        }
    }}

