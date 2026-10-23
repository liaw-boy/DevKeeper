import Foundation

public struct ExecutionLog: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let command: String
    public var output: String
    public var isCompleted: Bool
    public var isSuccess: Bool
    
    public init(command: String, output: String = "", isCompleted: Bool = false, isSuccess: Bool = true) {
        self.timestamp = Date()
        self.command = command
        self.output = output
        self.isCompleted = isCompleted
        self.isSuccess = isSuccess
    }
}
