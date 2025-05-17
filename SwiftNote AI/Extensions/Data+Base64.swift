import Foundation

// MARK: - Data Base64 Extension
extension Data {
    /// Convert Data to Base64 encoded string
    /// - Returns: Base64 encoded string
    func toBase64String() -> String {
        return self.base64EncodedString()
    }

    /// Get the size of the data in bytes
    /// - Returns: Size in bytes
    var sizeInBytes: Double {
        return Double(self.count)
    }

    /// Get the size of the data in KB
    /// - Returns: Size in KB
    func sizeInKB() -> Double {
        return Double(self.count) / 1024.0
    }

    /// Get the size of the data in MB
    /// - Returns: Size in MB
    func sizeInMB() -> Double {
        return self.sizeInKB() / 1024.0
    }
}

// MARK: - String Base64 Extension
extension String {
    /// Convert Base64 encoded string to Data
    /// - Returns: Decoded Data or nil if decoding fails
    func fromBase64() -> Data? {
        return Data(base64Encoded: self)
    }

    /// Check if string is a valid Base64 encoded string
    /// - Returns: True if valid Base64
    func isValidBase64() -> Bool {
        return self.fromBase64() != nil
    }
}
