import CommonCrypto
import Foundation
import Security

public struct ParentPIN: Codable {
    private let salt: Data
    private let verifier: Data

    public enum Failure: Error { case invalidPIN, secureRandom, derivation }

    public static let length = 4

    public static func isValid(_ pin: String) -> Bool {
        pin.utf8.count == length && pin.utf8.allSatisfy { (48...57).contains($0) }
    }

    public init(_ pin: String) throws {
        guard Self.isValid(pin) else { throw Failure.invalidPIN }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.secureRandom }
        self.salt = salt
        verifier = try Self.derive(pin, salt: salt)
    }

    public func matches(_ pin: String) throws -> Bool {
        guard Self.isValid(pin) else { return false }
        let candidate = try Self.derive(pin, salt: salt)
        guard candidate.count == verifier.count else { return false }
        return zip(candidate, verifier).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func derive(_ pin: String, salt: Data) throws -> Data {
        guard salt.count == 16 else { throw Failure.derivation }
        var result = Data(count: 32)
        let status = result.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), pin, pin.utf8.count,
                    salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000,
                    output.bindMemory(to: UInt8.self).baseAddress, output.count
                )
            }
        }
        guard status == kCCSuccess else { throw Failure.derivation }
        return result
    }
}
