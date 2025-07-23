import Foundation
import Network
import Combine

/// NetworkConnectivityMonitor provides real-time network connectivity detection
/// and comprehensive NSURLError classification for robust error handling.
/// 
/// Key Features:
/// - Real-time connectivity monitoring with NWPathMonitor
/// - Network error classification (network vs server vs client errors)
/// - Circuit breaker pattern support with retry limits
/// - Connection type detection (WiFi, Ethernet, Cellular)
/// - Thread-safe monitoring with proper cleanup
class NetworkConnectivityMonitor: ObservableObject {
    static let shared = NetworkConnectivityMonitor()
    
    // MARK: - Published Properties
    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown
    @Published var hasRecentNetworkError: Bool = false
    
    // MARK: - Types
    enum ConnectionType: String, CaseIterable {
        case wifi = "WiFi"
        case ethernet = "Ethernet" 
        case cellular = "Cellular"
        case unknown = "Unknown"
    }
    
    enum NetworkErrorType {
        case networkUnavailable    // No internet connection
        case timeout              // Request timeout
        case serverUnavailable    // Server cannot be reached
        case dnsFailure          // Cannot resolve domain
        case clientError         // 4xx HTTP errors
        case serverError         // 5xx HTTP errors
        case otherError          // Non-network related errors
    }
    
    // MARK: - Private Properties
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "network.monitor", qos: .utility)
    private var isMonitoring = false
    private var networkErrorTimestamp: Date?
    private let networkErrorTimeout: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Initialization
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start real-time network monitoring
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateConnectivityStatus(path: path)
            }
        }
        
        pathMonitor.start(queue: monitorQueue)
        isMonitoring = true
    }
    
    /// Stop network monitoring and cleanup resources
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        pathMonitor.cancel()
        isMonitoring = false
    }
    
    /// Check if device has internet connectivity
    var hasInternetConnection: Bool {
        return isConnected && connectionType != .unknown
    }
    
    /// Check if a URL error represents a network connectivity issue
    func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Check for NSURLError codes that indicate network issues
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorTimedOut,
             NSURLErrorDNSLookupFailed,
             NSURLErrorResourceUnavailable:
            return true
        default:
            return false
        }
    }
    
    /// Classify the type of network error for appropriate handling
    func classifyError(_ error: Error) -> NetworkErrorType {
        let nsError = error as NSError
        
        // Network-level errors (no connectivity)
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            markNetworkError()
            return .networkUnavailable
            
        case NSURLErrorNetworkConnectionLost:
            markNetworkError()
            return .networkUnavailable
            
        case NSURLErrorTimedOut:
            return .timeout
            
        case NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed:
            return .dnsFailure
            
        case NSURLErrorCannotConnectToHost,
             NSURLErrorResourceUnavailable:
            return .serverUnavailable
            
        case NSURLErrorBadServerResponse:
            return .serverError
            
        case NSURLErrorUserCancelledAuthentication,
             NSURLErrorUserAuthenticationRequired:
            return .clientError
            
        default:
            return .otherError
        }
    }
    
    /// Check if we should attempt automatic retry for this error type
    func shouldRetryForError(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        
        switch errorType {
        case .networkUnavailable, .timeout, .dnsFailure:
            return hasInternetConnection // Only retry if we now have connectivity
        case .serverUnavailable:
            return true // Server might be temporarily down
        case .clientError, .serverError, .otherError:
            return false // Don't retry client errors or non-network issues
        }
    }
    
    /// Get user-friendly error message for display
    func getUserFriendlyErrorMessage(_ error: Error) -> String {
        let errorType = classifyError(error)
        
        switch errorType {
        case .networkUnavailable:
            return "No internet connection. Please check your network settings."
        case .timeout:
            return "Request timed out. Please try again."
        case .dnsFailure:
            return "Cannot find the website. Please check the URL."
        case .serverUnavailable:
            return "The website is currently unavailable. Please try again later."
        case .clientError:
            return "There was a problem with the request."
        case .serverError:
            return "The website encountered an error. Please try again later."
        case .otherError:
            return "An unexpected error occurred."
        }
    }
    
    /// Check if we've had recent network errors (for UI indicators)
    var hasRecentNetworkErrors: Bool {
        guard let timestamp = networkErrorTimestamp else { return false }
        return Date().timeIntervalSince(timestamp) < networkErrorTimeout
    }
    
    // MARK: - Private Methods
    
    private func updateConnectivityStatus(path: NWPath) {
        isConnected = path.status == .satisfied
        connectionType = determineConnectionType(path: path)
        
        // Clear network error flag if we're now connected
        if isConnected {
            hasRecentNetworkError = false
            networkErrorTimestamp = nil
        }
        
        // Log connectivity changes for debugging
        if !isConnected {
            NSLog("🔴 Network connectivity lost - Connection type: \(connectionType.rawValue)")
        } else {
            NSLog("🟢 Network connectivity restored - Connection type: \(connectionType.rawValue)")
        }
    }
    
    private func determineConnectionType(path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else {
            return .unknown
        }
    }
    
    private func markNetworkError() {
        hasRecentNetworkError = true
        networkErrorTimestamp = Date()
    }
}

// MARK: - Circuit Breaker Pattern Support

extension NetworkConnectivityMonitor {
    /// CircuitBreakerState tracks retry attempts and prevents infinite loops
    class CircuitBreakerState: ObservableObject {
        @Published var failureCount: Int = 0
        @Published var lastFailureTime: Date?
        @Published var isOpen: Bool = false
        
        private let maxFailures: Int
        private let timeoutInterval: TimeInterval
        private let backoffMultiplier: Double
        
        init(maxFailures: Int = 3, timeoutInterval: TimeInterval = 60.0, backoffMultiplier: Double = 2.0) {
            self.maxFailures = maxFailures
            self.timeoutInterval = timeoutInterval
            self.backoffMultiplier = backoffMultiplier
        }
        
        /// Record a failure and potentially open the circuit
        func recordFailure() {
            failureCount += 1
            lastFailureTime = Date()
            
            if failureCount >= maxFailures {
                isOpen = true
                NSLog("🚫 Circuit breaker opened after \(failureCount) failures")
            }
        }
        
        /// Record a success and reset the circuit
        func recordSuccess() {
            failureCount = 0
            lastFailureTime = nil
            isOpen = false
        }
        
        /// Check if we can attempt a request (circuit is closed or has cooled down)
        func canAttemptRequest() -> Bool {
            guard isOpen else { return true }
            
            guard let lastFailure = lastFailureTime else { return true }
            
            let timeSinceFailure = Date().timeIntervalSince(lastFailure)
            let requiredCooldown = timeoutInterval * pow(backoffMultiplier, Double(failureCount - maxFailures))
            
            if timeSinceFailure >= requiredCooldown {
                NSLog("🔄 Circuit breaker attempting half-open state after \(Int(timeSinceFailure))s cooldown")
                return true
            }
            
            return false
        }
        
        /// Get the next retry delay using exponential backoff
        func getNextRetryDelay() -> TimeInterval {
            guard lastFailureTime != nil else { return 0 }
            
            let baseDelay = min(pow(backoffMultiplier, Double(failureCount)), 60.0) // Max 60 seconds
            let jitter = Double.random(in: 0.8...1.2) // Add jitter to prevent thundering herd
            
            return baseDelay * jitter
        }
    }
}

// MARK: - Network Error Extensions

extension NSError {
    /// Check if this error represents a network connectivity issue
    var isNetworkConnectivityError: Bool {
        return NetworkConnectivityMonitor.shared.isNetworkError(self)
    }
    
    /// Get the classification of this network error
    var networkErrorType: NetworkConnectivityMonitor.NetworkErrorType {
        return NetworkConnectivityMonitor.shared.classifyError(self)
    }
    
    /// Get a user-friendly error message
    var userFriendlyMessage: String {
        return NetworkConnectivityMonitor.shared.getUserFriendlyErrorMessage(self)
    }
}