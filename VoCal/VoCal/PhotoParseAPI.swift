//
//  PhotoParseAPI.swift
//  VoCal
//
//  Backend client for POST /api/photo/parse. Resizes + JPEG-encodes the
//  image to keep upload size around 1.5 MB, base64-encodes it, and sends
//  with an optional voice context string. Returns the same
//  `VoiceParseResponse` shape the voice flow uses, so call sites can
//  reuse the existing meal-confirm UI.
//

import Foundation
import UIKit

enum PhotoParseAPI {
    enum Error: Swift.Error, LocalizedError {
        case encodeFailed
        case server(Int, String)
        case malformed
        var errorDescription: String? {
            switch self {
            case .encodeFailed:        "Couldn't compress the photo."
            case .server(let s, let m): "Server \(s): \(m)"
            case .malformed:           "Unexpected response from the vision model."
            }
        }
    }

    private struct Payload: Codable {
        let image_base64: String
        let voice_context: String?
        /// Sent alongside `voice_context` when the user is answering the
        /// backend's clarifying question. The current backend ignores
        /// unknown fields, but we also fold the answer into `voice_context`
        /// (see below) so the model still sees it on a server that hasn't
        /// learned the dedicated field yet.
        let follow_up_answer: String?
    }

    /// Parse a photo (with optional spoken context) into a `VoiceParseResponse`.
    /// Throws on network/server errors so the caller can show a fallback.
    ///
    /// `followUpAnswer` is the user's reply to a previous `follow_up_question`
    /// in the same photo-parse round. Backward compatible — defaults to nil
    /// for the first pass.
    static func parse(
        image: UIImage,
        voiceContext: String?,
        followUpAnswer: String? = nil
    ) async throws -> VoiceParseResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/photo/parse") else {
            throw Error.malformed
        }
        // Upload size cap (≈1.5 MB after base64). 768px on the longest edge
        // is plenty for the vision model to identify food and stays well
        // under the cap. 0.7 JPEG quality for the same reason.
        guard let jpeg = downscaledJPEG(image: image, longestEdge: 768, quality: 0.7) else {
            throw Error.encodeFailed
        }
        let b64 = jpeg.base64EncodedString()

        // Defensive fold: if the caller passed a follow-up answer, splice
        // it onto the voice context so a backend that doesn't read the
        // dedicated field still sees the clarification. Newer backends
        // can prefer the explicit `follow_up_answer` field.
        let mergedContext: String? = {
            let trimmedAnswer = (followUpAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAnswer.isEmpty else { return voiceContext }
            let base = (voiceContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return base.isEmpty
                ? "Clarification: \(trimmedAnswer)"
                : "\(base) — Clarification: \(trimmedAnswer)"
        }()

        let body = try JSONEncoder().encode(Payload(
            image_base64: b64,
            voice_context: mergedContext,
            follow_up_answer: followUpAnswer
        ))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Vision LLMs can take 5-15s on a busy plate; give them headroom.
        req.timeoutInterval = 30
        req.httpBody = body
        await AuthSession.shared.authorize(&req)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.malformed }
        if !(200..<300).contains(http.statusCode) {
            let errBody = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            throw Error.server(http.statusCode, errBody["error"] ?? "")
        }
        let parsed = try JSONDecoder().decode(VoiceParseResponse.self, from: data)
        return parsed
    }

    /// Aspect-fit resize + JPEG. Returns nil on encoding failure.
    private static func downscaledJPEG(image: UIImage, longestEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(longestEdge / max(size.width, size.height), 1)
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: target, format: {
            let f = UIGraphicsImageRendererFormat.default()
            f.scale = 1
            f.opaque = true
            return f
        }())
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
