// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(macOS) || os(watchOS) || os(visionOS)

import SwiftUI
import CoreData
import Pulse
import Combine

@MainActor final class ShareStoreViewModel: ObservableObject {
    // Sharing options
    @Published var sessions: Set<UUID> = []
    @Published var logLevels = Set(LoggerStore.Level.allCases)
    @Published var output: ShareStoreOutput

    @Published private(set) var isPreparingForSharing = false
    @Published private(set) var errorMessage: String?
    @Published var shareItems: ShareItems?

    var store: LoggerStore?

    init() {
        output = UserSettings.shared.sharingOutput
    }

    func buttonSharedTapped() {
        guard !isPreparingForSharing else { return }
        isPreparingForSharing = true
        saveSharingOptions()
        prepareForSharing()
    }

    private func saveSharingOptions() {
        UserSettings.shared.sharingOutput = output
    }

    func prepareForSharing() {
        guard let store = store else { return }

        isPreparingForSharing = true
        shareItems = nil
        errorMessage = nil

        Task {
            do {
                let options = LoggerStore.ExportOptions(predicate: predicate, sessions: sessions)
                self.shareItems = try await ShareService.prepareForSharing(
                    store: store,
                    output: output,
                    options: options
                )
            } catch {
                guard !(error is CancellationError) else { return }
                self.errorMessage = error.localizedDescription
            }
            self.isPreparingForSharing = false
        }
    }

    var selectedLevelsTitle: String {
        if logLevels.count == 1 {
            return logLevels.first!.name.capitalized
        } else if logLevels.count == 0 {
            return "–"
        } else if logLevels == [.error, .critical] {
            return "Errors"
        } else if logLevels == [.warning, .error, .critical] {
            return "Warnings & Errors"
        } else if logLevels.count == LoggerStore.Level.allCases.count {
            return "All"
        } else {
            return "\(logLevels.count)"
        }
    }

    private var predicate: NSPredicate? {
        var predicates: [NSPredicate] = []
        if logLevels != Set(LoggerStore.Level.allCases) {
            predicates.append(.init(format: "level IN %@", logLevels.map(\.rawValue)))
        }
        if !sessions.isEmpty {
            predicates.append(.init(format: "session IN %@", sessions))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

#endif
