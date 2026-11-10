//
//  LabelScanSection.swift
//  My Cocktail Collection
//
//  Label scanning, step 2: the camera, and the "Scan Label" section at the top of Add Bottle.
//

import SwiftUI
import PhotosUI
import UIKit

/// Where a label scan has got to, for the message under the Scan Label buttons.
enum LabelScanState: Equatable {
    case idle
    case reading
    case filled(LabelSuggestion)
    case unreadable
}

/// Buttons to scan a label with the camera or from a photo, and what the scan found.
struct LabelScanSection: View {
    let state: LabelScanState
    @Binding var libraryItem: PhotosPickerItem?
    /// The brand in the form now, to highlight the matching choice.
    var currentBrand: String = ""
    let onUseCamera: () -> Void
    /// Called with the brand picked from the label's other lines.
    var onPickBrand: (String) -> Void = { _ in }

    var body: some View {
        Section {
            if CameraPicker.isAvailable {
                Button(action: onUseCamera) {
                    Label("Scan Label with Camera", systemImage: "camera.viewfinder")
                }
                .disabled(state == .reading)
            }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Label("Scan a Label from Photos", systemImage: "photo.on.rectangle")
            }
            .disabled(state == .reading)
            if case .filled(let suggestion) = state, !suggestion.brandAlternatives.isEmpty {
                brandChoices(suggestion)
            }
            if state == .reading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the label…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Scan Label")
        } footer: {
            footer
        }
    }

    /// The scanned brand and the other lines it could be, as buttons, for when the guess is wrong.
    private func brandChoices(_ suggestion: LabelSuggestion) -> some View {
        let options = ([suggestion.brand].compactMap { $0 } + suggestion.brandAlternatives)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Wrong brand? Tap the right one:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        Button(option) { onPickBrand(option) }
                            .buttonStyle(.bordered)
                            .tint(option == currentBrand ? .accentColor : .secondary)
                            .accessibilityAddTraits(option == currentBrand ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var footer: some View {
        switch state {
        case .idle, .reading:
            Text("Take a photo of the front label to fill in the brand, type and notes. The photo becomes the bottle's picture.")
        case .filled(let suggestion):
            if suggestion.styleName == nil, let family = suggestion.family {
                Label("Filled in from the label. It looks like \(family.displayName); pick the exact type below.",
                      systemImage: "text.viewfinder")
            } else if suggestion.styleName == nil {
                Label("Filled in from the label. The type wasn't on it, so pick one below.", systemImage: "text.viewfinder")
            } else {
                Label("Filled in from the label. Check the brand and type before saving.", systemImage: "text.viewfinder")
            }
        case .unreadable:
            Label("Couldn't read this label. Fill it in yourself, or try another photo with the label straight on and well lit.",
                  systemImage: "exclamationmark.triangle")
        }
    }
}

/// The iPhone camera, for taking a label photo. Not available in the Simulator.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
