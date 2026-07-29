// CosmoOS/UI/SwipeFile/Shared/SwipeGenreMenu.swift
// "File Under" — the context-menu submenu that corrects a swipe's genre.
//
// Capture never asks what a swipe is (ONE VERB law); the router seeds, the
// analyzer decides, and THIS menu is where a wrong guess gets fixed. A hand
// filing is terminal: it writes `genreLockedByUser`, and every later analyzer
// pass keeps its hands off (the transcriptEditedByUser pattern).

import SwiftUI

struct SwipeGenreMenu: View {
    let swipeUUID: String
    /// The swipe's current space — the checkmark row.
    let currentGenre: SwipeGenre
    /// Surface toast hook ("Filed under Newsletters"); nil stays quiet.
    var onFiled: ((SwipeGenre) -> Void)?

    var body: some View {
        Menu("File Under") {
            ForEach(SwipeGenre.allCases, id: \.rawValue) { genre in
                Button {
                    file(as: genre)
                } label: {
                    if genre == currentGenre {
                        Label(genre.pluralName, systemImage: "checkmark")
                    } else {
                        Label(genre.pluralName, systemImage: genre.iconName)
                    }
                }
            }
        }
    }

    private func file(as genre: SwipeGenre) {
        guard genre != currentGenre else { return }
        let uuid = swipeUUID
        Task { @MainActor in
            guard let atom = try? await AtomRepository.shared.fetch(uuid: uuid) else { return }
            let updated = atom.withSwipeGenre(genre, lockedByUser: true)
            guard (try? await AtomRepository.shared.update(updated)) != nil else { return }
            NotificationCenter.default.post(name: CosmoNotification.SwipeFile.libraryDidChange, object: nil)
            onFiled?(genre)
        }
    }
}
