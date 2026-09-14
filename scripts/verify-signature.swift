import Foundation
import CryptoKit

// Built before release credentials are loaded. Only the public verification key is an argument.
guard CommandLine.arguments.count == 4,
      let keyData = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fputs("Usage: verify-signature PUBLIC_KEY SIGNATURE FILE\n", stderr); exit(2)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: data) else { fputs("Invalid Ed25519 archive signature\n", stderr); exit(1) }
    print("Archive signature matches the public key embedded in MacExplorer.app")
} catch { fputs("\(error)\n", stderr); exit(1) }
