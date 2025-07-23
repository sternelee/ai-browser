import Foundation

/// Thread-safe wrapper for mutable values in concurrent contexts
/// Used to safely share data between async tasks and avoid concurrency issues
class Box<T> {
    var value: T
    
    init(_ value: T) {
        self.value = value
    }
}