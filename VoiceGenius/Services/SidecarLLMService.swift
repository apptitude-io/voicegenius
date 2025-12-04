import Foundation

/// LLM service that connects to the Python sidecar running on the host Mac
final class SidecarLLMService: LLMService, @unchecked Sendable {
    private let baseURL = URL(string: "http://127.0.0.1:8080")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func generate(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["prompt": prompt]
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw LLMError.invalidResponse
            }

            struct ChatResponse: Decodable {
                let response: String
            }

            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            return chatResponse.response
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.networkError(error)
        }
    }

    /// Check if the sidecar server is running
    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (_, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }
}
