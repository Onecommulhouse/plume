import Foundation
import WhisperKit

enum TranscriberError: LocalizedError {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady: return "Le modèle de transcription n'est pas encore prêt."
        }
    }
}

/// Transcription 100 % locale avec WhisperKit (Whisper optimisé pour les puces Apple).
/// L'audio ne quitte jamais le Mac.
@MainActor
final class Transcriber: ObservableObject {
    enum Status: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private var pipe: WhisperKit?
    private var loadedModel: String?
    private var isPreparing = false

    private var modelsBase: URL {
        let url = AppPaths.support.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func savedFolderKey(_ model: String) -> String { "modelFolder.\(model)" }

    /// Télécharge le modèle la première fois (≈ 630 Mo), puis le charge en mémoire.
    func prepare(model: String) async {
        guard !isPreparing else { return }
        if loadedModel == model, pipe != nil { return }
        isPreparing = true
        defer { isPreparing = false }
        pipe = nil

        do {
            let folder: URL
            if let saved = UserDefaults.standard.string(forKey: savedFolderKey(model)),
               FileManager.default.fileExists(atPath: saved),
               let contents = try? FileManager.default.contentsOfDirectory(atPath: saved),
               contents.contains(where: { $0.hasSuffix(".mlmodelc") }) {
                folder = URL(fileURLWithPath: saved)
            } else {
                status = .downloading(0)
                folder = try await WhisperKit.download(
                    variant: model,
                    downloadBase: modelsBase,
                    progressCallback: { [weak self] progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            self?.status = .downloading(fraction)
                        }
                    }
                )
                UserDefaults.standard.set(folder.path, forKey: savedFolderKey(model))
            }

            status = .loading
            let config = WhisperKitConfig(
                model: model,
                downloadBase: modelsBase,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: false
            )
            pipe = try await WhisperKit(config)
            loadedModel = model
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// - Parameter preview: transcription rapide d'un extrait, pour le texte affiché en direct pendant la dictée.
    func transcribe(_ samples: [Float], language: String?, vocabulary: [String], preview: Bool = false) async throws -> String {
        guard let pipe else { throw TranscriberError.notReady }

        var options = DecodingOptions(
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )
        if preview {
            // Extrait court (≤ 20 s) : pas de découpage ni de nouvel essai, on privilégie la vitesse.
            options.chunkingStrategy = nil
            options.temperatureFallbackCount = 0
        }
        if !vocabulary.isEmpty, let tokenizer = pipe.tokenizer {
            let prompt = " " + vocabulary.joined(separator: ", ") + "."
            options.promptTokens = tokenizer.encode(text: prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Phrases que Whisper « invente » parfois sur un silence (héritées des sous-titres de vidéos).
enum Hallucinations {
    private static let patterns = [
        "sous-titrage",
        "sous-titres réalisés",
        "merci d'avoir regardé",
        "amara.org",
        "abonnez-vous",
        "thanks for watching",
    ]

    static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if patterns.contains(where: { lower.contains($0) }) && trimmed.wordCount <= 8 {
            return ""
        }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return "" }
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { return "" }
        return trimmed
    }
}
