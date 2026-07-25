import Foundation

/// Reads Claude Code OAuth credentials from ~/.claude/.credentials.json
/// and handles token refresh when expired.
enum ClaudeCodeAuthHelper {
    private static var credentialsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")
    }

    struct Credentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let subscriptionType: String
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: credentialsPath.path)
    }

    static func loadCredentials() -> Credentials? {
        guard let data = try? Data(contentsOf: credentialsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String,
              let expiresAtMs = oauth["expiresAt"] as? Double
        else { return nil }

        return Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1000),
            subscriptionType: oauth["subscriptionType"] as? String ?? "unknown"
        )
    }

    static func getValidToken() async -> String? {
        guard let creds = loadCredentials() else { return nil }

        if creds.expiresAt.timeIntervalSinceNow < 300 {
            if let refreshed = await refreshToken(creds.refreshToken) {
                return refreshed
            }
            if creds.expiresAt.timeIntervalSinceNow > 0 {
                return creds.accessToken
            }
            return nil
        }

        return creds.accessToken
    }

    private static func refreshToken(_ refreshToken: String) async -> String? {
        let url = URL(string: Constants.oauthTokenURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Constants.oauthClientId,
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                NSLog("[Companion] Token refresh failed: HTTP %d", (response as? HTTPURLResponse)?.statusCode ?? 0)
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String,
                  let newRefreshToken = json["refresh_token"] as? String,
                  let expiresIn = json["expires_in"] as? Double
            else { return nil }

            let expiresAtMs = (Date().timeIntervalSince1970 + expiresIn) * 1000
            let updatedOauth: [String: Any] = [
                "accessToken": newAccessToken,
                "refreshToken": newRefreshToken,
                "expiresAt": expiresAtMs,
                "scopes": ["user:inference", "user:mcp_servers", "user:profile", "user:sessions:claude_code"],
                "subscriptionType": loadCredentials()?.subscriptionType ?? "unknown",
            ]

            let updatedCreds: [String: Any] = ["claudeAiOauth": updatedOauth]
            do {
                let saveData = try JSONSerialization.data(withJSONObject: updatedCreds)
                try saveData.write(to: credentialsPath, options: .atomic)
            } catch {
                NSLog("[Companion] Failed to save refreshed credentials: %@", error.localizedDescription)
            }

            NSLog("[Companion] Claude Code token refreshed")
            return newAccessToken
        } catch {
            NSLog("[Companion] Token refresh error: %@", error.localizedDescription)
            return nil
        }
    }
}
