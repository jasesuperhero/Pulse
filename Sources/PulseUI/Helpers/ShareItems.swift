// The MIT License (MIT)
//
// Copyright (c) 2020-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Pulse
import CoreData

public enum ShareStoreOutput: String, RawRepresentable {
    case store, package, text, html, har

    var fileExtension: String {
        switch self {
        case .store, .package: return "pulse"
        case .text: return "txt"
        case .html: return "html"
        case .har: return "har"
        }
    }
}

public struct ShareItems: Identifiable {
    public let id = UUID()
    public let items: [Any]
    public let size: Int64?
    public let cleanup: () -> Void

    init(_ items: [Any], size: Int64? = nil, cleanup: @escaping () -> Void = { }) {
        self.items = items
        self.size = size
        self.cleanup = cleanup
    }
}

public enum ShareService {
    private static var task: ShareStoreTask?

    public static func prepareForSharing(
        store: LoggerStore,
        output: ShareStoreOutput,
        options: LoggerStore.ExportOptions
    ) async throws -> ShareItems {
        switch output {
        case .store:
            return try await prepareStoreForSharing(
                store: store,
                as: .archive,
                output: output,
                options: options
            )
        case .package:
            return try await prepareStoreForSharing(
                store: store,
                as: .package,
                output: output,
                options: options
            )
        case .text, .html:
            let output: ShareOutput = output == .text ? .plainText : .html
            return try await _prepareForSharing(store: store, output: output, options: options)
        case .har:
            return try await _prepareForSharing(store: store, output: .har, options: options)
        }
    }

    private static func prepareStoreForSharing(
        store: LoggerStore,
        as docType: LoggerStore.DocumentType,
        output: ShareStoreOutput,
        options: LoggerStore.ExportOptions
    ) async throws -> ShareItems {
        let directory = TemporaryDirectory()

        let logsURL = directory.url.appendingPathComponent("logs-\(makeCurrentDate()).\(output.fileExtension)")
        try await store.export(to: logsURL, as: docType, options: options)
        return ShareItems([logsURL], cleanup: directory.remove)
    }

    private static func _prepareForSharing(
        store: LoggerStore,
        output: ShareOutput,
        options: LoggerStore.ExportOptions
    ) async throws -> ShareItems {
        let entities = try await withUnsafeThrowingContinuation { continuation in
            store.backgroundContext.perform {
                let request = NSFetchRequest<LoggerMessageEntity>(entityName: "\(LoggerMessageEntity.self)")
                request.predicate = options.predicate // important: contains sessions
                let result = Result(catching: { try store.backgroundContext.fetch(request) })
                continuation.resume(with: result)
            }
        }
        return try await share(entities, store: store, as: output)
    }

    public static func share(
        _ entities: [NSManagedObject],
        store: LoggerStore,
        as output: ShareOutput
    ) async throws -> ShareItems {
        try await withUnsafeThrowingContinuation { continuation in
            ShareStoreTask(entities: entities, store: store, output: output) {
                if let value = $0 {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }.start()
        }
    }

    static func share(_ message: LoggerMessageEntity, as output: ShareOutput) -> ShareItems {
        let string = TextRenderer(options: .sharing).make { $0.render(message) }
        return share(string, as: output)
    }

    static func share(_ task: NetworkTaskEntity, as output: ShareOutput, store: LoggerStore) -> ShareItems {
        let string = TextRenderer(options: .sharing).make { $0.render(task, content: .sharing, store: store) }
        return share(string, as: output)
    }

    static func share(_ string: NSAttributedString, as output: ShareOutput) -> ShareItems {
        let string = sanitized(string, as: output)
        switch output {
        case .plainText:
            let string = TextUtilities.plainText(from: string)
            return ShareItems([string])
        case .html:
            let html = (try? TextUtilities.html(from: string)) ?? Data()
            let directory = TemporaryDirectory()
            let fileURL = directory.write(data: html, extension: "html")
            return ShareItems([fileURL], size: Int64(html.count), cleanup: directory.remove)
        case .pdf:
#if os(iOS) || os(visionOS)
            let pdf = (try? TextUtilities.pdf(from: string)) ?? Data()
            let directory = TemporaryDirectory()
            let fileURL = directory.write(data: pdf, extension: "pdf")
            return ShareItems([fileURL], size: Int64(pdf.count), cleanup: directory.remove)
#else
            return ShareItems(["Sharing as PDF is not supported on this platform"])
#endif
        case .har:
            let har = TextUtilities.har(from: string)
            let directory = TemporaryDirectory()
            let fileURL = directory.write(data: har, extension: "har")
            return ShareItems([fileURL], size: Int64(har.count), cleanup: directory.remove)
        }
    }

    static func sanitized(_ string: NSAttributedString, as shareOutput: ShareOutput) -> NSAttributedString {
        var ranges: [NSRange] = []
        string.enumerateAttribute(.isTechnical, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            if (value as? Bool) == true {
                ranges.append(range)
            }
        }
        let output = NSMutableAttributedString(attributedString: string)
        for range in ranges.reversed() {
            output.deleteCharacters(in: range)
        }
        if shareOutput == .plainText {
            var ranges: [NSRange] = []
            string.enumerateAttribute(.subheadline, in: NSRange(location: 0, length: string.length)) { value, range, _ in
                if (value as? Bool) == true {
                    ranges.append(range)
                }
            }
            for range in ranges.reversed() {
                output.insert(NSAttributedString(string: "–––––––––––––––––––––––––––––––––––––––\n"), at: range.upperBound)
                output.insert(NSAttributedString(string: ""), at: range.location)
            }
        }
        return output
    }
}

public enum ShareOutput {
    case plainText
    case html
    case pdf
    case har

    var title: String {
        switch self {
        case .plainText: return "Text"
        case .html: return "HTML"
        case .pdf: return "PDF"
        case .har: return "HAR"
        }
    }
}

struct TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.github.kean.logger", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

extension TemporaryDirectory {
    func write(data: Data, extension fileExtension: String) -> URL {
        let date = makeCurrentDate()
        let fileURL = url.appendingPathComponent("logs-\(date).\(fileExtension)", isDirectory: false)
        try? data.write(to: fileURL)
        return fileURL
    }
}

func makeCurrentDate() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.dateFormat = "yyyy-MM-dd-HH-mm"
    return formatter.string(from: Date())
}
