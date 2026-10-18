// Vérifie qu'une mise à jour est bien signée avec la clé dont la partie publique est inscrite dans Plume.
// Usage : xcrun swift verify-ed-signature.swift <clé publique base64> <signature base64> <fichier>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let publicKeyData = Data(base64Encoded: args[1]),
      let signature = Data(base64Encoded: args[2]) else {
    print("::error::Clé publique ou signature illisible.")
    exit(2)
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    if publicKey.isValidSignature(signature, for: data) {
        print("Signature de la mise à jour valide.")
        exit(0)
    }
    print("::error::Le secret SPARKLE_PRIVATE_KEY ne correspond pas à la clé publique inscrite dans Plume (SUPublicEDKey).")
    exit(1)
} catch {
    print("::error::Vérification impossible : \(error)")
    exit(1)
}
