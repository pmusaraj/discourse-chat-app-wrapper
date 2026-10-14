// Verify against the public key shipped in the app, independently of the
// private key selected by generate_appcast. Also catches signing-key mixups.
import CryptoKit
import Foundation

if CommandLine.arguments.count != 4 {
    fputs("Usage: verify-update public-key signature archive\n", stderr)
    exit(1)
}
do {
    guard let publicKey = Data(base64Encoded: CommandLine.arguments[1]),
          let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
        throw NSError(domain: "Invalid base64", code: 1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "Update signature does not match the app's public key", code: 1)
    }
    print("Update signature verified against the app's public key.")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
