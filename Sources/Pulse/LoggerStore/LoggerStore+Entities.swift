// The MIT License (MIT)
//
// Copyright (c) 2020–2022 Alexander Grebenyuk (github.com/kean).

import CoreData

public final class LoggerMessageEntity: NSManagedObject {
    @NSManaged public var createdAt: Date
    @NSManaged public var isPinned: Bool
    @NSManaged public var session: UUID
    @NSManaged public var level: Int16
    @NSManaged public var text: String
    @NSManaged public var file: String
    @NSManaged public var function: String
    @NSManaged public var line: Int32 // Doubles as request state storage to save space
    @NSManaged public var label: LoggerLabelEntity
    @NSManaged public var metadata: Set<LoggerMetadataEntity>
    @NSManaged public var task: NetworkTaskEntity?
}

public final class LoggerLabelEntity: NSManagedObject {
    @NSManaged public var name: String
    @NSManaged public var count: Int64
}

public final class LoggerMetadataEntity: NSManagedObject {
    @NSManaged public var key: String
    @NSManaged public var value: String
}

public final class NetworkTaskEntity: NSManagedObject {
    // Primary
    @NSManaged public var createdAt: Date
    @NSManaged public var isPinned: Bool
    @NSManaged public var session: UUID
    @NSManaged public var taskId: UUID

    /// Returns task type
    public var type: NetworkLogger.TaskType? {
        NetworkLogger.TaskType(rawValue: taskType)
    }
    @NSManaged public var taskType: Int16

    // MARK: Request

    @NSManaged public var url: String?
    @NSManaged public var host: NetworkDomainEntity?
    @NSManaged public var httpMethod: String?

    // MARK: Response

    @NSManaged public var statusCode: Int32
    @NSManaged public var rawErrorDomain: Int16
    @NSManaged public var errorCode: Int32
    /// Response content-type.
    @NSManaged public var responseContentType: String?
    /// Returns `true` if the response was returned from the local cache.
    @NSManaged public var isFromCache: Bool

    // MARK: State

    /// Contains ``State-swift.enum`` raw value.
    @NSManaged public var requestState: Int16
    /// Request progress.
    ///
    /// - note: The entity is created lazily when the first progress report
    /// is delivered. If no progress updates are delivered, it's never created.
    @NSManaged public var progress: NetworkTaskProgressEntity?

    /// Total request duration end date.
    @NSManaged public var duration: Double

    // MARK: Details

    @NSManaged public var originalRequest: NetworkRequestEntity
    @NSManaged public var currentRequest: NetworkRequestEntity?
    @NSManaged public var response: NetworkResponseEntity?
    @NSManaged public var error: NetworkErrorEntity?
    @NSManaged public var metrics: NetworkMetricsEntity?
    @NSManaged var rawMetadata: LoggerInlineDataEntity?

    /// The request body handle.
    @NSManaged public var requestBody: LoggerBlobHandleEntity?
    /// The response body handle.
    @NSManaged public var responseBody: LoggerBlobHandleEntity?
    /// The size of the request body.
    @NSManaged public var requestBodySize: Int64
    /// The size of the response body.
    @NSManaged public var responseBodySize: Int64
    /// Associated (technical) message.
    @NSManaged public var message: LoggerMessageEntity?

    // MARK: Helpers

    public var metadata: [String: String] {
        rawMetadata.flatMap { try? JSONDecoder().decode([String: String].self, from: $0.data) } ?? [:]
    }

    public var errorDomain: ErrorDomain? {
        get { ErrorDomain(rawValue: rawErrorDomain) }
        set { rawErrorDomain = newValue?.rawValue ?? 0 }
    }

    /// Returns request state.
    public var state: State {
        State(rawValue: requestState) ?? .pending
    }

    public enum State: Int16 {
        case pending = 1, success, failure = 3
    }

    public enum ErrorDomain: Int16 {
        case urlError = 1, decoding
    }
}

public final class NetworkDomainEntity: NSManagedObject {
    @NSManaged public var value: String
    @NSManaged public var count: Int64
}

/// Indicates current download or upload progress.
public final class NetworkTaskProgressEntity: NSManagedObject {
    /// Indicates current download or upload progress.
    @NSManaged public var completedUnitCount: Int64
    /// Indicates current download or upload progress.
    @NSManaged public var totalUnitCount: Int64
}

public final class NetworkMetricsEntity: NSManagedObject {
    @NSManaged public var startDate: Date
    @NSManaged public var duration: Double
    @NSManaged public var redirectCount: Int16
    @NSManaged public var transactions: Set<NetworkTransactionMetricsEntity>

    public var orderedTransactions: [NetworkTransactionMetricsEntity] {
        transactions.sorted { $0.index < $1.index }
    }

    public var taskInterval: DateInterval {
        DateInterval(start: startDate, duration: duration)
    }

    public var totalTransferSize: NetworkLogger.TransferSizeInfo {
        var size = NetworkLogger.TransferSizeInfo()
        for transaction in transactions {
            size = size.merging(transaction.transferSize)
        }
        return size
    }
}

public final class NetworkErrorEntity: NSManagedObject {
    @NSManaged public var code: Int
    @NSManaged public var domain: String
    @NSManaged public var errorDebugDescription: String
    /// JSON-encoded underlying error
    @NSManaged public var underlyingError: Data?

    public lazy var error: Error? = {
        guard let data = underlyingError else { return nil }
        let error = try? JSONDecoder().decode(NetworkLogger.ResponseError.UnderlyingError.self, from: data)
        return error?.error
    }()
}

public final class NetworkTransactionMetricsEntity: NSManagedObject {
    @NSManaged public var index: Int16
    @NSManaged public var rawFetchType: Int16
    @NSManaged public var request: NetworkRequestEntity
    @NSManaged public var response: NetworkResponseEntity?
    @NSManaged public var networkProtocol: String?
    @NSManaged public var localAddress: String?
    @NSManaged public var remoteAddress: String?
    @NSManaged public var localPort: Int32
    @NSManaged public var remotePort: Int32
    @NSManaged public var isProxyConnection: Bool
    @NSManaged public var isReusedConnection: Bool
    @NSManaged public var isCellular: Bool
    @NSManaged public var isExpensive: Bool
    @NSManaged public var isConstrained: Bool
    @NSManaged public var isMultipath: Bool
    @NSManaged public var rawNegotiatedTLSProtocolVersion: Int16
    @NSManaged public var rawNegotiatedTLSCipherSuite: Int16
    @NSManaged public var fetchStartDate: Date?
    @NSManaged public var domainLookupStartDate: Date?
    @NSManaged public var domainLookupEndDate: Date?
    @NSManaged public var connectStartDate: Date?
    @NSManaged public var secureConnectionStartDate: Date?
    @NSManaged public var secureConnectionEndDate: Date?
    @NSManaged public var connectEndDate: Date?
    @NSManaged public var requestStartDate: Date?
    @NSManaged public var requestEndDate: Date?
    @NSManaged public var responseStartDate: Date?
    @NSManaged public var responseEndDate: Date?
    @NSManaged public var requestHeaderBytesSent: Int64
    @NSManaged public var requestBodyBytesBeforeEncoding: Int64
    @NSManaged public var requestBodyBytesSent: Int64
    @NSManaged public var responseHeaderBytesReceived: Int64
    @NSManaged public var responseBodyBytesAfterDecoding: Int64
    @NSManaged public var responseBodyBytesReceived: Int64

    public var fetchType: URLSessionTaskMetrics.ResourceFetchType {
        URLSessionTaskMetrics.ResourceFetchType(rawValue: Int(rawFetchType)) ?? .networkLoad
    }

    public var negotiatedTLSProtocolVersion: tls_protocol_version_t? {
        tls_protocol_version_t(rawValue: UInt16(rawNegotiatedTLSProtocolVersion))
    }

    public var negotiatedTLSCipherSuite: tls_ciphersuite_t? {
        tls_ciphersuite_t(rawValue: UInt16(rawNegotiatedTLSCipherSuite))
    }

    public var transferSize: NetworkLogger.TransferSizeInfo {
        var value = NetworkLogger.TransferSizeInfo()
        value.requestHeaderBytesSent = requestHeaderBytesSent
        value.requestBodyBytesBeforeEncoding = requestBodyBytesBeforeEncoding
        value.requestBodyBytesSent = requestBodyBytesSent
        value.responseHeaderBytesReceived = responseHeaderBytesReceived
        value.responseBodyBytesAfterDecoding = responseBodyBytesAfterDecoding
        value.responseBodyBytesReceived = responseBodyBytesReceived
        return value
    }

    public var timing: NetworkLogger.TransactionTimingInfo {
        var value = NetworkLogger.TransactionTimingInfo()
        value.fetchStartDate = fetchStartDate
        value.domainLookupStartDate = domainLookupStartDate
        value.domainLookupEndDate = domainLookupEndDate
        value.connectStartDate = connectStartDate
        value.secureConnectionStartDate = secureConnectionStartDate
        value.secureConnectionEndDate = secureConnectionEndDate
        value.connectEndDate = connectEndDate
        value.requestStartDate = requestStartDate
        value.requestEndDate = requestEndDate
        value.responseStartDate = responseStartDate
        value.responseEndDate = responseEndDate
        return value
    }
}

public final class NetworkRequestEntity: NSManagedObject {
    // MARK: Details

    @NSManaged public var url: String?
    @NSManaged public var httpMethod: String?
    @NSManaged public var httpHeaders: String

    // MARK: Options

    @NSManaged public var allowsCellularAccess: Bool
    @NSManaged public var allowsExpensiveNetworkAccess: Bool
    @NSManaged public var allowsConstrainedNetworkAccess: Bool
    @NSManaged public var httpShouldHandleCookies: Bool
    @NSManaged public var httpShouldUsePipelining: Bool
    @NSManaged public var timeoutInterval: Int32
    @NSManaged public var rawCachePolicy: UInt16

    public var cachePolicy: URLRequest.CachePolicy {
        URLRequest.CachePolicy(rawValue: UInt(rawCachePolicy)) ?? .useProtocolCachePolicy
    }

    public var contentType: NetworkLogger.ContentType? {
        headers["Content-Type"].flatMap(NetworkLogger.ContentType.init)
    }

    public lazy var headers: [String: String] = NetworkRequestEntity.decodeHeaders(httpHeaders)
}

extension NetworkRequestEntity {
    static func encodeHeaders(_ headers: [String: String]?) -> String {
        var output = ""
        let sorted = (headers ?? [:]).sorted { $0.key < $1.key }
        for (name, value) in sorted {
            if !output.isEmpty { output.append("\n")}
            output.append("\(name): \(value)")
        }
        return output
    }

    static func decodeHeaders(_ string: String) -> [String: String] {
        let pairs = string.components(separatedBy: "\n")
        var headers: [String: String] = [:]
        for pair in pairs {
            if let separatorIndex = pair.firstIndex(of: ":") {
                let valueStartIndex = pair.index(separatorIndex, offsetBy: 2)
                if pair.indices.contains(valueStartIndex) {
                    headers[String(pair[..<separatorIndex])] = String(pair[valueStartIndex...])
                }
            }
        }
        return headers
    }
}

public final class NetworkResponseEntity: NSManagedObject {
    @NSManaged public var statusCode: Int16
    @NSManaged public var httpHeaders: String

    public var contentType: NetworkLogger.ContentType? {
        headers["Content-Type"].flatMap(NetworkLogger.ContentType.init)
    }

    public var expectedContentLength: Int64? {
        headers["Content-Length"].flatMap { Int64($0) }
    }

    public lazy var headers: [String: String] = NetworkRequestEntity.decodeHeaders(httpHeaders)
}

/// Doesn't contain any data, just the key and some additional payload.
public final class LoggerBlobHandleEntity: NSManagedObject {
    /// A blob hash (sha1, stored in a binary format).
    @NSManaged public var key: Data

    /// A blob size.
    @NSManaged public var size: Int32

    /// A decompressed blob size.
    @NSManaged public var decompressedSize: Int32

    /// A number of requests referencing it.
    @NSManaged var linkCount: Int16

    /// The logger inlines small blobs in a separate table in the database which
    /// significantly [reduces](https://www.sqlite.org/intern-v-extern-blob.html)
    /// the total allocated size for these files and improves the overall performance.
    ///
    /// The larger blobs are stored in an file system. And when you export a Pulse
    /// document, the larger blobs are read from the created archive on-demand,
    /// significantly reducing the speed with this the documents are opened and
    /// reducing space usage.
    ///
    /// To access data, use the convenience ``data`` property.
    @NSManaged var inlineData: LoggerInlineDataEntity?

    /// Returns the associated data.
    ///
    /// - important: This property only works with `NSManagedObjectContext` instances
    /// created by the ``LoggerStore``. If you are reading the database manually,
    /// you'll need to access the files directly by using the associated ``key``
    /// that matches the name o the file in the `/blobs` directly in the store
    /// directory.
    public var data: Data? {
        guard let store = managedObjectContext?.userInfo[WeakLoggerStore.loggerStoreKey] as? WeakLoggerStore else {
            return nil // Should never happen unless the object was created outside of the LoggerStore moc
        }
        return store.store?.getDecompressedData(for: self)
    }
}

final class LoggerInlineDataEntity: NSManagedObject {
    @NSManaged var data: Data
}
