import Foundation
import CoreGraphics

/// Utility functions for safe numeric conversions to prevent runtime crashes
enum SafeNumericConversions {
    
    /// Safely converts a Double to Int, clamping to valid range
    static func safeDoubleToInt(_ value: Double) -> Int {
        guard value.isFinite && !value.isNaN else { return 0 }
        
        if value > Double(Int.max) {
            return Int.max
        } else if value < Double(Int.min) {
            return Int.min
        } else {
            return Int(value)
        }
    }
    
    /// Safely converts a Double to CGFloat, ensuring finite values
    static func safeDoubleToCGFloat(_ value: Double) -> CGFloat {
        guard value.isFinite && !value.isNaN else { return 0.0 }
        return CGFloat(value)
    }
    
    /// Safely clamps a progress value to 0.0-1.0 range
    static func safeProgress(_ value: Double) -> Double {
        guard value.isFinite && !value.isNaN else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }
    
    /// Safely converts CGFloat to Int for UI calculations
    static func safeCGFloatToInt(_ value: CGFloat) -> Int {
        return safeDoubleToInt(Double(value))
    }
    
    /// Validates that a CGRect has safe, finite dimensions
    static func validateSafeRect(_ rect: CGRect) -> CGRect {
        let safeWidth = max(0, min(rect.width.isFinite ? rect.width : 0, CGFloat(Int.max)))
        let safeHeight = max(0, min(rect.height.isFinite ? rect.height : 0, CGFloat(Int.max)))
        let safeX = rect.origin.x.isFinite ? rect.origin.x : 0
        let safeY = rect.origin.y.isFinite ? rect.origin.y : 0
        
        return CGRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
    }
    
    /// Validates that a CGSize has safe, finite dimensions
    static func validateSafeSize(_ size: CGSize) -> CGSize {
        let safeWidth = max(0, min(size.width.isFinite ? size.width : 0, CGFloat(Int.max)))
        let safeHeight = max(0, min(size.height.isFinite ? size.height : 0, CGFloat(Int.max)))
        
        return CGSize(width: safeWidth, height: safeHeight)
    }
}