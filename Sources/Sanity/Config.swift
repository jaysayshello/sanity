import Foundation

/// Optional local config, read from ~/.config/sanity/config.json.
/// Used to seed AI defaults so no gateway URL, model, or key is hardcoded in
/// source (the repo can be public; this file stays on the machine).
///
/// In-app Settings changes are saved to UserDefaults and take precedence over
/// this file. Example:
///
///     {
///       "aiBaseURL": "https://your-openai-compatible-gateway/v1",
///       "aiModel": "your-model-name",
///       "aiToken": "sk-..."
///     }
struct AppConfig {
    var aiBaseURL: String?
    var aiModel: String?
    var aiToken: String?

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sanity/config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AppConfig()
        }
        return AppConfig(
            aiBaseURL: obj["aiBaseURL"] as? String,
            aiModel: obj["aiModel"] as? String,
            aiToken: obj["aiToken"] as? String
        )
    }
}
