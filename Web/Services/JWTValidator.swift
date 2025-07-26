import Foundation
import CryptoKit
import Security

/// JWTValidator: Comprehensive JWT validation with signature verification
///
/// This service provides production-ready JWT validation using Apple's CryptoKit framework.
/// It supports all major JWT signing algorithms and includes comprehensive security checks
/// to prevent common JWT attacks like algorithm confusion, signature bypass, and replay attacks.
///
/// Security Features:
/// - Native CryptoKit implementation (no third-party dependencies)
/// - Signature verification for HMAC, RSA, and ECDSA algorithms
/// - Comprehensive claims validation (exp, iat, nbf, iss, aud)
/// - Algorithm confusion attack prevention
/// - Replay attack protection through timestamp validation
/// - Secure key management and validation
class JWTValidator {
    static let shared = JWTValidator()
    
    // MARK: - JWT Models
    
    /// JWT Header containing algorithm and type information
    struct JWTHeader: Codable {
        let alg: String
        let typ: String?
        let kid: String? // Key ID for key lookup
        let cty: String? // Content type
        let crit: [String]? // Critical header parameters
        
        var algorithm: SigningAlgorithm? {
            return SigningAlgorithm(rawValue: alg)
        }
    }
    
    /// JWT Claims with standard and custom claims support
    struct JWTClaims: Codable {
        // Standard claims (RFC 7519)
        let iss: String? // Issuer
        let sub: String? // Subject
        let aud: AudienceClaim? // Audience
        let exp: TimeInterval? // Expiration time
        let nbf: TimeInterval? // Not before
        let iat: TimeInterval? // Issued at
        let jti: String? // JWT ID
        
        // Custom claims stored as additional properties
        private var customClaims: [String: AnyCodable] = [:]
        
        // Custom subscript for additional claims
        subscript(claim: String) -> Any? {
            get { customClaims[claim]?.value }
            set { customClaims[claim] = newValue.map(AnyCodable.init) }
        }
        
        // MARK: - Validation Properties
        
        var isExpired: Bool {
            guard let exp = exp else { return false }
            return Date().timeIntervalSince1970 >= exp
        }
        
        var isNotYetValid: Bool {
            guard let nbf = nbf else { return false }
            return Date().timeIntervalSince1970 < nbf
        }
        
        var age: TimeInterval? {
            guard let iat = iat else { return nil }
            return Date().timeIntervalSince1970 - iat
        }
        
        // MARK: - Codable Implementation
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            
            // Decode standard claims
            iss = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("iss"))
            sub = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("sub"))
            aud = try container.decodeIfPresent(AudienceClaim.self, forKey: AnyCodingKey("aud"))
            exp = try container.decodeIfPresent(TimeInterval.self, forKey: AnyCodingKey("exp"))
            nbf = try container.decodeIfPresent(TimeInterval.self, forKey: AnyCodingKey("nbf"))
            iat = try container.decodeIfPresent(TimeInterval.self, forKey: AnyCodingKey("iat"))
            jti = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("jti"))
            
            // Decode custom claims
            let allKeys = container.allKeys
            let standardKeys: Set<String> = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"]
            
            for key in allKeys {
                if !standardKeys.contains(key.stringValue) {
                    if let value = try? container.decode(AnyCodable.self, forKey: key) {
                        customClaims[key.stringValue] = value
                    }
                }
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            
            // Encode standard claims
            try container.encodeIfPresent(iss, forKey: AnyCodingKey("iss"))
            try container.encodeIfPresent(sub, forKey: AnyCodingKey("sub"))
            try container.encodeIfPresent(aud, forKey: AnyCodingKey("aud"))
            try container.encodeIfPresent(exp, forKey: AnyCodingKey("exp"))
            try container.encodeIfPresent(nbf, forKey: AnyCodingKey("nbf"))
            try container.encodeIfPresent(iat, forKey: AnyCodingKey("iat"))
            try container.encodeIfPresent(jti, forKey: AnyCodingKey("jti"))
            
            // Encode custom claims
            for (key, value) in customClaims {
                let codingKey = AnyCodingKey(key)
                try container.encode(value, forKey: codingKey)
            }
        }
        
        private enum CodingKeys: String, CodingKey {
            case iss, sub, aud, exp, nbf, iat, jti
        }
    }
    
    /// Audience claim that can be string or array of strings
    enum AudienceClaim: Codable, Equatable {
        case single(String)
        case multiple([String])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let single = try? container.decode(String.self) {
                self = .single(single)
            } else if let multiple = try? container.decode([String].self) {
                self = .multiple(multiple)
            } else {
                throw DecodingError.typeMismatch(AudienceClaim.self, 
                    DecodingError.Context(codingPath: decoder.codingPath, 
                                        debugDescription: "Audience must be string or array of strings"))
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            switch self {
            case .single(let audience):
                try container.encode(audience)
            case .multiple(let audiences):
                try container.encode(audiences)
            }
        }
        
        func contains(_ audience: String) -> Bool {
            switch self {
            case .single(let aud):
                return aud == audience
            case .multiple(let auds):
                return auds.contains(audience)
            }
        }
    }
    
    /// Supported JWT signing algorithms
    enum SigningAlgorithm: String, CaseIterable {
        case hs256 = "HS256" // HMAC SHA-256
        case hs384 = "HS384" // HMAC SHA-384
        case hs512 = "HS512" // HMAC SHA-512
        case rs256 = "RS256" // RSA SHA-256
        case rs384 = "RS384" // RSA SHA-384
        case rs512 = "RS512" // RSA SHA-512
        case es256 = "ES256" // ECDSA SHA-256
        case es384 = "ES384" // ECDSA SHA-384
        case es512 = "ES512" // ECDSA SHA-512
        case none = "none"   // No signature (dangerous - explicit validation required)
        
        var isSymmetric: Bool {
            switch self {
            case .hs256, .hs384, .hs512:
                return true
            default:
                return false
            }
        }
        
        var isAsymmetric: Bool {
            switch self {
            case .rs256, .rs384, .rs512, .es256, .es384, .es512:
                return true
            default:
                return false
            }
        }
        
        var hashFunction: any HashFunction.Type {
            switch self {
            case .hs256, .rs256, .es256:
                return SHA256.self
            case .hs384, .rs384, .es384:
                return SHA384.self
            case .hs512, .rs512, .es512:
                return SHA512.self
            case .none:
                fatalError("None algorithm has no hash function")
            }
        }
    }
    
    /// JWT validation configuration
    struct ValidationOptions {
        let validateExpiration: Bool
        let validateNotBefore: Bool
        let validateIssuedAt: Bool
        let validateIssuer: String?
        let validateAudience: String?
        let clockSkewAllowance: TimeInterval // Allowance for clock skew in seconds
        let maxAge: TimeInterval? // Maximum token age in seconds
        let allowNoneAlgorithm: Bool // Dangerous - should be false in production
        
        static let `default` = ValidationOptions(
            validateExpiration: true,
            validateNotBefore: true,
            validateIssuedAt: true,
            validateIssuer: nil,
            validateAudience: nil,
            clockSkewAllowance: 60, // 1 minute
            maxAge: 3600, // 1 hour
            allowNoneAlgorithm: false
        )
        
        static let strict = ValidationOptions(
            validateExpiration: true,
            validateNotBefore: true,
            validateIssuedAt: true,
            validateIssuer: nil,
            validateAudience: nil,
            clockSkewAllowance: 30, // 30 seconds
            maxAge: 1800, // 30 minutes
            allowNoneAlgorithm: false
        )
    }
    
    /// JWT validation result
    enum ValidationResult {
        case valid(header: JWTHeader, claims: JWTClaims)
        case invalid(error: ValidationError)
        
        var isValid: Bool {
            switch self {
            case .valid:
                return true
            case .invalid:
                return false
            }
        }
    }
    
    /// JWT validation errors
    enum ValidationError: LocalizedError {
        case invalidFormat
        case invalidHeader
        case invalidClaims
        case invalidSignature
        case algorithmMismatch
        case algorithmNotAllowed(String)
        case tokenExpired
        case tokenNotYetValid
        case tokenTooOld
        case invalidIssuer(expected: String, actual: String?)
        case invalidAudience(expected: String, actual: AudienceClaim?)
        case missingRequiredClaim(String)
        case invalidTimestamp
        case signatureVerificationFailed
        case keyNotFound
        case unsupportedAlgorithm(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "JWT has invalid format"
            case .invalidHeader:
                return "JWT header is invalid"
            case .invalidClaims:
                return "JWT claims are invalid"
            case .invalidSignature:
                return "JWT signature is invalid"
            case .algorithmMismatch:
                return "JWT algorithm does not match expected algorithm"
            case .algorithmNotAllowed(let alg):
                return "JWT algorithm '\(alg)' is not allowed"
            case .tokenExpired:
                return "JWT token has expired"
            case .tokenNotYetValid:
                return "JWT token is not yet valid"
            case .tokenTooOld:
                return "JWT token is too old"
            case .invalidIssuer(let expected, let actual):
                return "Invalid issuer: expected '\(expected)', got '\(actual ?? "nil")'"
            case .invalidAudience(let expected, let actual):
                return "Invalid audience: expected '\(expected)', got '\(actual?.debugDescription ?? "nil")'"
            case .missingRequiredClaim(let claim):
                return "Missing required claim: '\(claim)'"
            case .invalidTimestamp:
                return "JWT contains invalid timestamp"
            case .signatureVerificationFailed:
                return "JWT signature verification failed"
            case .keyNotFound:
                return "Signing key not found"
            case .unsupportedAlgorithm(let alg):
                return "Unsupported algorithm: '\(alg)'"
            }
        }
    }
    
    // MARK: - Private Properties
    
    private init() {}
    
    // MARK: - JWT Validation
    
    /// Validates a JWT token with comprehensive security checks
    func validate(
        jwt: String,
        key: Any, // SymmetricKey, SecKey, or Data
        algorithm: SigningAlgorithm,
        options: ValidationOptions = .default
    ) -> ValidationResult {
        
        do {
            // Step 1: Parse JWT structure
            let parts = jwt.components(separatedBy: ".")
            guard parts.count == 3 else {
                return .invalid(error: .invalidFormat)
            }
            
            let headerData = parts[0]
            let claimsData = parts[1]
            let signatureData = parts[2]
            
            // Step 2: Decode and validate header
            guard let header = try decodeHeader(from: headerData) else {
                return .invalid(error: .invalidHeader)
            }
            
            // Step 3: Algorithm validation (prevent algorithm confusion attacks)
            guard let headerAlgorithm = header.algorithm else {
                return .invalid(error: .unsupportedAlgorithm(header.alg))
            }
            
            guard headerAlgorithm == algorithm else {
                return .invalid(error: .algorithmMismatch)
            }
            
            // Step 4: Check if algorithm is allowed
            if headerAlgorithm == .none && !options.allowNoneAlgorithm {
                return .invalid(error: .algorithmNotAllowed("none"))
            }
            
            // Step 5: Decode claims
            guard let claims = try decodeClaims(from: claimsData) else {
                return .invalid(error: .invalidClaims)
            }
            
            // Step 6: Validate claims
            if let claimsError = validateClaims(claims, options: options) {
                return .invalid(error: claimsError)
            }
            
            // Step 7: Verify signature (skip for 'none' algorithm)
            if headerAlgorithm != .none {
                let signatureValid = try verifySignature(
                    header: headerData,
                    claims: claimsData,
                    signature: signatureData,
                    key: key,
                    algorithm: algorithm
                )
                
                if !signatureValid {
                    return .invalid(error: .invalidSignature)
                }
            }
            
            return .valid(header: header, claims: claims)
            
        } catch let error as ValidationError {
            return .invalid(error: error)
        } catch {
            return .invalid(error: .signatureVerificationFailed)
        }
    }
    
    // MARK: - JWT Parsing
    
    private func decodeHeader(from data: String) throws -> JWTHeader? {
        guard let decodedData = base64URLDecode(data) else {
            throw ValidationError.invalidHeader
        }
        
        return try JSONDecoder().decode(JWTHeader.self, from: decodedData)
    }
    
    private func decodeClaims(from data: String) throws -> JWTClaims? {
        guard let decodedData = base64URLDecode(data) else {
            throw ValidationError.invalidClaims
        }
        
        return try JSONDecoder().decode(JWTClaims.self, from: decodedData)
    }
    
    // MARK: - Claims Validation
    
    private func validateClaims(_ claims: JWTClaims, options: ValidationOptions) -> ValidationError? {
        let now = Date().timeIntervalSince1970
        
        // Validate expiration
        if options.validateExpiration, let exp = claims.exp {
            if now >= (exp + options.clockSkewAllowance) {
                return .tokenExpired
            }
        }
        
        // Validate not before
        if options.validateNotBefore, let nbf = claims.nbf {
            if now < (nbf - options.clockSkewAllowance) {
                return .tokenNotYetValid
            }
        }
        
        // Validate issued at
        if options.validateIssuedAt, let iat = claims.iat {
            // Check if token is from the future (with clock skew allowance)
            if iat > (now + options.clockSkewAllowance) {
                return .invalidTimestamp
            }
            
            // Check maximum age
            if let maxAge = options.maxAge {
                if (now - iat) > maxAge {
                    return .tokenTooOld
                }
            }
        }
        
        // Validate issuer
        if let expectedIssuer = options.validateIssuer {
            if claims.iss != expectedIssuer {
                return .invalidIssuer(expected: expectedIssuer, actual: claims.iss)
            }
        }
        
        // Validate audience
        if let expectedAudience = options.validateAudience {
            guard let audience = claims.aud else {
                return .invalidAudience(expected: expectedAudience, actual: nil)
            }
            
            if !audience.contains(expectedAudience) {
                return .invalidAudience(expected: expectedAudience, actual: audience)
            }
        }
        
        return nil
    }
    
    // MARK: - Signature Verification
    
    private func verifySignature(
        header: String,
        claims: String,
        signature: String,
        key: Any,
        algorithm: SigningAlgorithm
    ) throws -> Bool {
        
        let signingInput = "\(header).\(claims)"
        let signingData = Data(signingInput.utf8)
        
        guard let signatureData = base64URLDecode(signature) else {
            throw ValidationError.invalidSignature
        }
        
        switch algorithm {
        case .hs256, .hs384, .hs512:
            return try verifyHMACSignature(
                data: signingData,
                signature: signatureData,
                key: key,
                algorithm: algorithm
            )
            
        case .rs256, .rs384, .rs512:
            return try verifyRSASignature(
                data: signingData,
                signature: signatureData,
                key: key,
                algorithm: algorithm
            )
            
        case .es256, .es384, .es512:
            return try verifyECDSASignature(
                data: signingData,
                signature: signatureData,
                key: key,
                algorithm: algorithm
            )
            
        case .none:
            // For 'none' algorithm, signature should be empty
            return signatureData.isEmpty
        }
    }
    
    private func verifyHMACSignature(
        data: Data,
        signature: Data,
        key: Any,
        algorithm: SigningAlgorithm
    ) throws -> Bool {
        
        let secretKey: SymmetricKey
        
        if let symmetricKey = key as? SymmetricKey {
            secretKey = symmetricKey
        } else if let keyData = key as? Data {
            secretKey = SymmetricKey(data: keyData)
        } else if let keyString = key as? String {
            secretKey = SymmetricKey(data: Data(keyString.utf8))
        } else {
            throw ValidationError.keyNotFound
        }
        
        let computedSignature: Data
        
        switch algorithm {
        case .hs256:
            computedSignature = Data(HMAC<SHA256>.authenticationCode(for: data, using: secretKey))
        case .hs384:
            computedSignature = Data(HMAC<SHA384>.authenticationCode(for: data, using: secretKey))
        case .hs512:
            computedSignature = Data(HMAC<SHA512>.authenticationCode(for: data, using: secretKey))
        default:
            throw ValidationError.unsupportedAlgorithm(algorithm.rawValue)
        }
        
        // Constant-time comparison to prevent timing attacks
        return constantTimeCompare(computedSignature, signature)
    }
    
    private func verifyRSASignature(
        data: Data,
        signature: Data,
        key: Any,
        algorithm: SigningAlgorithm
    ) throws -> Bool {
        
        guard CFGetTypeID(key as CFTypeRef) == SecKeyGetTypeID() else {
            throw ValidationError.keyNotFound
        }
        
        let publicKey = key as! SecKey
        
        let signatureAlgorithm: SecKeyAlgorithm
        
        switch algorithm {
        case .rs256:
            signatureAlgorithm = .rsaSignatureMessagePKCS1v15SHA256
        case .rs384:
            signatureAlgorithm = .rsaSignatureMessagePKCS1v15SHA384
        case .rs512:
            signatureAlgorithm = .rsaSignatureMessagePKCS1v15SHA512
        default:
            throw ValidationError.unsupportedAlgorithm(algorithm.rawValue)
        }
        
        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            signatureAlgorithm,
            data as CFData,
            signature as CFData,
            &error
        )
        
        if let error = error {
            let errorDescription = CFErrorCopyDescription(error.takeRetainedValue())
            print("RSA signature verification failed: \(errorDescription ?? "Unknown error" as CFString)")
        }
        
        return isValid
    }
    
    private func verifyECDSASignature(
        data: Data,
        signature: Data,
        key: Any,
        algorithm: SigningAlgorithm
    ) throws -> Bool {
        
        guard CFGetTypeID(key as CFTypeRef) == SecKeyGetTypeID() else {
            throw ValidationError.keyNotFound
        }
        
        let publicKey = key as! SecKey
        
        let signatureAlgorithm: SecKeyAlgorithm
        
        switch algorithm {
        case .es256:
            signatureAlgorithm = .ecdsaSignatureMessageX962SHA256
        case .es384:
            signatureAlgorithm = .ecdsaSignatureMessageX962SHA384
        case .es512:
            signatureAlgorithm = .ecdsaSignatureMessageX962SHA512
        default:
            throw ValidationError.unsupportedAlgorithm(algorithm.rawValue)
        }
        
        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            signatureAlgorithm,
            data as CFData,
            signature as CFData,
            &error
        )
        
        if let error = error {
            let errorDescription = CFErrorCopyDescription(error.takeRetainedValue())
            print("ECDSA signature verification failed: \(errorDescription ?? "Unknown error" as CFString)")
        }
        
        return isValid
    }
    
    // MARK: - Utility Functions
    
    /// Base64URL decoding (RFC 4648)
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        
        return Data(base64Encoded: base64)
    }
    
    /// Constant-time comparison to prevent timing attacks
    private func constantTimeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        var result: UInt8 = 0
        for i in 0..<lhs.count {
            result |= lhs[i] ^ rhs[i]
        }
        
        return result == 0
    }
}

// MARK: - Supporting Types

/// Type-erased wrapper for codable values
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}

/// Dynamic coding key for custom claims
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
    
    init(_ string: String) {
        self.stringValue = string
    }
}

// MARK: - Extensions

extension JWTValidator.AudienceClaim: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .single(let audience):
            return audience
        case .multiple(let audiences):
            return audiences.joined(separator: ", ")
        }
    }
}