import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    /// `data(for:)` is missing from FoundationNetworking before Swift 6, so use a task-based version everywhere.
    func devkeeperData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            task.resume()
        }
    }
    
    func devkeeperData(from url: URL) async throws -> (Data, URLResponse) {
        try await devkeeperData(for: URLRequest(url: url))
    }
}
