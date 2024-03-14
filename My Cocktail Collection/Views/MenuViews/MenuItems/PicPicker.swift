//
//  PicPicker.swift
//  My Cocktail Collection
//
//  Created by William Faucett on 3/14/24.
//

import PhotosUI
import SwiftUI

struct PicPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PHPickerViewController {
        return PHPickerViewController(configuration: PHPickerConfiguration())
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        //not implemented
    }
}

struct DocPicker : UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.text])
        controller.directoryURL = url
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        //not implemented
    }
}
    
