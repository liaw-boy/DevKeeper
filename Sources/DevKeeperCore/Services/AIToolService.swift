import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class AIToolService: @unchecked Sendable {
    public static let shared = AIToolService()
    
    private let urlSession: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        self.urlSession = URLSession(configuration: config)
    }
    
    public func defaultAITools() -> [AIToolItem] {
        return [
            AIToolItem(
                name: "Claude Code",
                command: "claude",
                vendor: "Anthropic",
                summary: "次世代終端機 Agentic 智慧程式開發助理，支援自動編程、專案理解與即時測試",
                iconSymbol: "sparkles",
                updateCommand: "claude update",
                installCommand: "npm install -g @anthropic-ai/claude-code",
                websiteUrl: "https://docs.anthropic.com/en/docs/agents-and-tools/claude-code"
            ),
            AIToolItem(
                name: "Antigravity CLI (AGY)",
                command: "agy",
                vendor: "Google DeepMind",
                summary: "次世代多代理人協同程式開發 CLI，支援雙向即時工作區、子代理人與自動除錯",
                iconSymbol: "network",
                updateCommand: "agy update",
                installCommand: "curl -fsSL https://antigravity.google/install.sh | bash",
                websiteUrl: "https://antigravity.google"
            ),
            AIToolItem(
                name: "Aider",
                command: "aider",
                vendor: "Paul Gauthier",
                summary: "終端機 AI 協同結對編程工具 (AI Pair Programming)，具備自動 Git Commit 語意分析",
                iconSymbol: "person.2.badge.gearshape",
                updateCommand: "pipx upgrade aider-chat || uv tool upgrade aider-chat",
                installCommand: "pipx install aider-chat",
                websiteUrl: "https://aider.chat"
            ),
            AIToolItem(
                name: "Ollama",
                command: "ollama",
                vendor: "Ollama Inc.",
                summary: "本機大語言模型執行環境，支援離線執行 Llama 3、DeepSeek、Qwen 等開源模型",
                iconSymbol: "cpu",
                updateCommand: "brew upgrade ollama",
                installCommand: "brew install ollama",
                websiteUrl: "https://ollama.com"
            ),
            AIToolItem(
                name: "OpenAI Codex",
                command: "codex",
                vendor: "OpenAI",
                summary: "OpenAI 程式碼智慧補全與生成指令列工具，支援終端機代碼自動生成、解釋與重構",
                iconSymbol: "chevron.left.forwardslash.chevron.right",
                updateCommand: "npm install -g @openai/codex@latest",
                installCommand: "npm install -g @openai/codex",
                websiteUrl: "https://github.com/openai/codex"
            ),
            AIToolItem(
                name: "LLM CLI (Simon Willison)",
                command: "llm",
                vendor: "Simon Willison",
                summary: "可擴充式終端機 AI 模型呼叫工具，支援 OpenAI、Anthropic 與外掛生態",
                iconSymbol: "terminal.fill",
                updateCommand: "pip install -U llm",
                installCommand: "pip install llm",
                websiteUrl: "https://llm.datasette.io"
            ),
            AIToolItem(
                name: "Cursor CLI",
                command: "cursor",
                vendor: "Anysphere",
                summary: "AI 原生程式編輯器 Cursor 的終端機整合指令列工具",
                iconSymbol: "macwindow",
                updateCommand: "brew upgrade --cask cursor",
                installCommand: "brew install --cask cursor",
                websiteUrl: "https://cursor.com"
            ),
            AIToolItem(
                name: "GitHub Copilot CLI",
                command: "gh-copilot",
                vendor: "GitHub",
                summary: "GitHub 官方終端機 AI 助理擴充套件，解讀並生成 Shell 與 Git 指令",
                iconSymbol: "terminal",
                updateCommand: "gh extension upgrade gh-copilot",
                installCommand: "gh extension install github/gh-copilot",
                websiteUrl: "https://github.com/github/gh-copilot"
            )
        ]
    }
    
    /// Inspect local tool status (installed path and version)
    public func detectLocalTool(item: AIToolItem) async -> (isInstalled: Bool, version: String, binaryPath: String?) {
        let cmd = item.command
        
        // Handle special case for gh-copilot
        if cmd == "gh-copilot" {
            if let output = try? await ShellExecutor.shared.run(command: "gh extension list | grep gh-copilot"), !output.isEmpty {
                let ver = extractVersion(from: output)
                return (true, ver.isEmpty ? "已安裝" : ver, "gh extension")
            }
            return (false, "未安裝", nil)
        }
        
        // General CLI detection via `which <command>`
        do {
            let pathOutput = try await ShellExecutor.shared.run(command: "which \(cmd)")
            let path = pathOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && !path.contains("not found") {
                // Try getting version
                let quoted = InputValidator.shellQuoted(path)
                let verOutput = try? await ShellExecutor.shared.run(command: "\(quoted) --version 2>&1 || \(quoted) -v 2>&1")
                // A shim that exists on PATH but cannot find the real tool is not an installation.
                if verOutput?.lowercased().contains("not found") == true {
                    return (false, "未安裝", nil)
                }
                let ver = extractVersion(from: verOutput ?? "")
                return (true, ver.isEmpty ? "已安裝" : ver, path)
            }
        } catch {}
        
        // Also check if app exists in /Applications for GUI tools like Cursor
        if cmd == "cursor" {
            let appExists = FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
            if appExists {
                return (true, "已安裝 (GUI)", "/Applications/Cursor.app")
            }
        }
        
        return (false, "未安裝", nil)
    }
    
    /// Query latest version online
    public func fetchLatestVersion(for command: String) async -> String? {
        switch command {
        case "claude":
            return await npmLatestVersion(of: "@anthropic-ai/claude-code")
            
        case "codex":
            return await npmLatestVersion(of: "@openai/codex")
            
        case "aider":
            // PyPI
            guard let url = URL(string: "https://pypi.org/pypi/aider-chat/json") else { return nil }
            guard let (data, res) = try? await urlSession.devkeeperData(from: url),
                  let http = res as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = json["info"] as? [String: Any],
                  let version = info["version"] as? String else { return nil }
            return version
            
        case "ollama":
            // GitHub releases
            guard let url = URL(string: "https://api.github.com/repos/ollama/ollama/releases/latest") else { return nil }
            var req = URLRequest(url: url)
            req.setValue("DevKeeper-MacApp", forHTTPHeaderField: "User-Agent")
            guard let (data, res) = try? await urlSession.devkeeperData(for: req),
                  let http = res as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return nil }
            return tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            
        case "llm":
            // PyPI
            guard let url = URL(string: "https://pypi.org/pypi/llm/json") else { return nil }
            guard let (data, res) = try? await urlSession.devkeeperData(from: url),
                  let http = res as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = json["info"] as? [String: Any],
                  let version = info["version"] as? String else { return nil }
            return version
            
        default:
            return nil
        }
    }
    
    private func npmLatestVersion(of package: String) async -> String? {
        guard let url = URL(string: "https://registry.npmjs.org/\(package)/latest"),
              let (data, res) = try? await urlSession.devkeeperData(from: url),
              let http = res as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }
    
    /// Stream the upgrade command
    public func upgradeTool(item: AIToolItem) -> AsyncStream<String> {
        return ShellExecutor.shared.stream(command: item.updateCommand)
    }
    
    /// Stream the install command
    public func installTool(item: AIToolItem) -> AsyncStream<String> {
        return ShellExecutor.shared.stream(command: item.installCommand)
    }
    
    private func extractVersion(from raw: String) -> String {
        // Find pattern like 2.1.309 or 1.4.5 or 0.86.2
        let pattern = #"\b([0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = raw as NSString
            if let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range)
            }
        }
        return ""
    }
}
