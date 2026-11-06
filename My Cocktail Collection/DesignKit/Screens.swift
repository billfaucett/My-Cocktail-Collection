//
//  Screens.swift
//  My Cocktail Collection
//
//  Screen wrappers that give every form and list the same layout and behaviour.
//

import SwiftUI

// MARK: - Form screen

/// Wraps an add/edit form: navigation bar, title, Cancel and Save buttons,
/// and a "Couldn't Save" alert. Present it as a sheet.
///
///     FormScreen("Edit Cocktail", canSave: canSave, onSave: save) {
///         Section("Cocktail") { TextField("Name", text: $name) }
///     }
///
/// `onSave` should throw if saving fails. The screen closes when it succeeds and
/// shows the error's message when it doesn't.
struct FormScreen<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private let title: String
    private let saveTitle: String
    private let canSave: Bool
    private let onSave: () throws -> Void
    private let content: Content

    init(
        _ title: String,
        saveTitle: String = "Save",
        canSave: Bool = true,
        onSave: @escaping () throws -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.saveTitle = saveTitle
        self.canSave = canSave
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Couldn't Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            try onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A simple error with a message to show the user, for use in `FormScreen` save actions.
struct FormError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

// MARK: - List screen

/// What a list shows when it has nothing in it.
struct EmptyState {
    let title: String
    let systemImage: String
    let message: String
    /// Title of the button that calls the list's add action. Leave nil for no button.
    var actionTitle: String? = nil
}

/// Wraps a list: title, an optional Show Favorites button, "…" menu and + button, and an empty state.
/// Place it inside a `NavigationStack` (root screens) or push it onto one.
///
///     ListScreen("Spirits", isEmpty: spirits.isEmpty, emptyState: empty, onAdd: { showAdd = true }) {
///         ForEach(spirits) { … }
///     } moreMenu: {
///         Button("Something Else") { … }
///     }
///
/// Pass `favoritesOnly` for lists whose items can be favorites. The screen adds a heart button that
/// turns the filter on and off, and a "No Favorites" state with a Show All button. The list itself
/// filters its items using the same binding.
struct ListScreen<Content: View, MoreItems: View>: View {
    private let title: String
    private let isEmpty: Bool
    private let emptyState: EmptyState
    private let addLabel: String
    private let onAdd: (() -> Void)?
    private let favoritesOnly: Binding<Bool>?
    private let content: Content
    private let moreItems: MoreItems

    init(
        _ title: String,
        isEmpty: Bool,
        emptyState: EmptyState,
        addLabel: String = "Add",
        onAdd: (() -> Void)? = nil,
        favoritesOnly: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder moreMenu: () -> MoreItems
    ) {
        self.title = title
        self.isEmpty = isEmpty
        self.emptyState = emptyState
        self.addLabel = addLabel
        self.onAdd = onAdd
        self.favoritesOnly = favoritesOnly
        self.content = content()
        self.moreItems = moreMenu()
    }

    private var isShowingFavoritesOnly: Bool { favoritesOnly?.wrappedValue ?? false }

    var body: some View {
        Group {
            if isEmpty && isShowingFavoritesOnly {
                ContentUnavailableView {
                    Label("No Favorites", systemImage: "heart")
                } description: {
                    Text("Nothing here is a favorite yet, or no favorites match. Swipe right on an item to make it a favorite.")
                } actions: {
                    Button("Show All") {
                        if let favoritesOnly {
                            favoritesOnly.wrappedValue = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isEmpty {
                ContentUnavailableView {
                    Label(emptyState.title, systemImage: emptyState.systemImage)
                } description: {
                    Text(emptyState.message)
                } actions: {
                    if let onAdd, let actionTitle = emptyState.actionTitle {
                        Button(actionTitle, action: onAdd)
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    content
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let favoritesOnly {
                    Button {
                        favoritesOnly.wrappedValue = !favoritesOnly.wrappedValue
                    } label: {
                        Label(favoritesOnly.wrappedValue ? "Show All" : "Show Favorites",
                              systemImage: favoritesOnly.wrappedValue ? "heart.fill" : "heart")
                    }
                    .tint(favoritesOnly.wrappedValue ? Theme.favorite : nil)
                }
                if MoreItems.self != EmptyView.self {
                    // "SwiftUI." is needed because the app's Core Data entity is also named Menu.
                    SwiftUI.Menu {
                        moreItems
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
                if let onAdd {
                    Button(action: onAdd) {
                        Label(addLabel, systemImage: "plus")
                    }
                }
            }
        }
    }
}

extension ListScreen where MoreItems == EmptyView {
    /// A list screen without a "…" menu.
    init(
        _ title: String,
        isEmpty: Bool,
        emptyState: EmptyState,
        addLabel: String = "Add",
        onAdd: (() -> Void)? = nil,
        favoritesOnly: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, isEmpty: isEmpty, emptyState: emptyState, addLabel: addLabel, onAdd: onAdd,
                  favoritesOnly: favoritesOnly, content: content, moreMenu: { EmptyView() })
    }
}

// MARK: - Delete helpers

extension View {
    /// A red "Delete" swipe action for a list row. Use with `confirmDelete` to ask first.
    func deleteSwipeAction(_ action: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: action) {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// A heart swipe action on the leading edge (swipe right) to favorite or unfavorite a row.
    func favoriteSwipeAction(isFavorite: Bool, _ action: @escaping () -> Void) -> some View {
        swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: action) {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            .tint(Theme.favorite)
        }
    }

    /// Asks before deleting. Shows an alert whenever `item` is set, and clears it afterwards.
    func confirmDelete<Item>(
        _ item: Binding<Item?>,
        title: String = "Confirm Delete",
        message: @escaping (Item) -> String,
        onDelete: @escaping (Item) -> Void
    ) -> some View {
        alert(title, isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        ), presenting: item.wrappedValue) { value in
            Button("Delete", role: .destructive) {
                onDelete(value)
                item.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) {
                item.wrappedValue = nil
            }
        } message: { value in
            Text(message(value))
        }
    }
}
