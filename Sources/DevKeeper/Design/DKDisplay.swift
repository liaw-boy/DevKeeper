import AppKit
import DevKeeperCore
import SwiftUI

// MARK: - Surfaces

extension View {
    /// The one card style: surface, 1pt border, 10pt radius.
    func dkCard(padding: CGFloat = DK.Space.l) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                    .fill(DK.surface)
                    .shadow(color: DK.shadowSoft, radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                    .stroke(DK.border, lineWidth: 1)
            )
    }
}

struct DKDivider: View {
    var body: some View {
        Rectangle().fill(DK.border).frame(height: 1)
    }
}

// MARK: - Labels

struct DKTag: View {
    enum Tone { case neutral, warning, danger }
    let text: String
    var tone: Tone = .neutral
    
    init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
    
    var body: some View {
        Text(text)
            .font(DK.Font.micro)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, DK.Space.tight)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .stroke(DK.border, lineWidth: 1)
            )
    }
    
    private var color: Color {
        switch tone {
        case .neutral: return DK.textSecondary
        case .warning: return DK.warning
        case .danger: return DK.danger
        }
    }
}

/// Update status as plain text: grey when current, normal when an upgrade exists, amber for major versions.
struct DKStatusText: View {
    let status: UpdateStatus
    
    var body: some View {
        Text(title)
            .font(DK.Font.caption)
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
    }
    
    private var title: String {
        switch status {
        case .upToDate: return "最新"
        case .patch: return "修補版本"
        case .minor: return "次要版本"
        case .major: return "主要版本"
        case .updateAvailable: return "可更新"
        case .checking: return "檢查中"
        case .error: return "無法取得"
        }
    }
    
    private var color: Color {
        switch status {
        case .upToDate, .checking: return DK.textTertiary
        case .patch, .minor, .updateAvailable: return DK.textPrimary
        case .major: return DK.warning
        case .error: return DK.danger
        }
    }
}

// MARK: - Page structure

struct DKPageHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    var count: String?
    let actions: Actions
    
    init(_ title: String, subtitle: String? = nil, count: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.actions = actions()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: DK.Space.l) {
            VStack(alignment: .leading, spacing: DK.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: DK.Space.s) {
                    Text(title)
                        .font(DK.Font.title)
                        .foregroundColor(DK.textPrimary)
                        .lineLimit(1)
                    if let count {
                        Text(count)
                            .font(DK.Font.caption)
                            .foregroundColor(DK.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .dkTooltip(subtitle)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: DK.Space.l)
            HStack(spacing: DK.Space.s) {
                actions
            }
            .fixedSize()
        }
        .padding(.horizontal, DK.pagePadding)
        .padding(.top, DK.Space.xl)
        .padding(.bottom, DK.Space.l)
    }
}

extension DKPageHeader where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil, count: String? = nil) {
        self.init(title, subtitle: subtitle, count: count) { EmptyView() }
    }
}

struct DKSectionTitle: View {
    let title: String
    var trailing: String?
    
    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DK.Font.heading)
                .foregroundColor(DK.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textTertiary)
            }
        }
    }
}

/// Loading, never-checked, empty, all-current and error states share one layout.
struct DKEmptyState: View {
    enum Kind { case loading, idle, empty, allCurrent, error }
    let kind: Kind
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: DK.Space.s) {
            if kind == .loading {
                DKSpinner(size: 16)
                    .padding(.bottom, DK.Space.xs)
            }
            Text(title)
                .font(DK.Font.bodyMedium)
                .foregroundColor(kind == .error ? DK.danger : DK.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                DKButton(actionTitle, action: action)
                    .padding(.top, DK.Space.s)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DK.Space.xxl * 2)
    }
}

// MARK: - Command block

struct DKCommandBlock: View {
    let command: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    
    var body: some View {
        HStack(alignment: .center, spacing: DK.Space.s) {
            Text(command)
                .font(DK.Font.mono)
                .foregroundColor(DK.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            DKIconButton(copied ? "checkmark" : "doc.on.doc", help: copied ? "已複製" : "複製指令", compact: true) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                resetTask?.cancel()
                resetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    copied = false
                }
            }
        }
        .padding(.leading, DK.Space.m)
        .padding(.trailing, DK.Space.xs)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .fill(DK.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .stroke(DK.border, lineWidth: 1)
        )
    }
}

// MARK: - Modal panels

/// The one modal layout: title, scrollable body, button row. Used for confirmations, details and forms.
struct DKModalPanel<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    var width: CGFloat = 480
    let content: Content
    let footer: Footer
    @Environment(\.dkAvailableHeight) private var availableHeight
    @State private var contentHeight: CGFloat = 0
    
    init(_ title: String, subtitle: String? = nil, width: CGFloat = 480,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.content = content()
        self.footer = footer()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DK.Space.xs) {
                Text(title)
                    .font(DK.Font.heading)
                    .foregroundColor(DK.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DK.Space.xl)
            .padding(.top, DK.Space.xl)
            .padding(.bottom, DK.Space.l)
            
            // The body grows with its content and scrolls only when the panel would leave the window.
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DK.Space.xl)
                    .padding(.bottom, DK.Space.l)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: DKContentHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .frame(height: min(max(contentHeight, 1), max(availableHeight - 200, 120)))
            .onPreferenceChange(DKContentHeightKey.self) { contentHeight = $0 }
            
            DKDivider()
            HStack(spacing: DK.Space.s) {
                Spacer()
                footer
            }
            .padding(.horizontal, DK.Space.xl)
            .padding(.vertical, DK.Space.m)
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .fill(DK.surface)
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .stroke(DK.border, lineWidth: 1)
        )
    }
}

private struct DKContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Confirmation before anything that changes the system. Lists the exact commands that will run.
struct DKConfirmPanel: View {
    let title: String
    var message: String?
    var commands: [String] = []
    var confirmTitle: String
    var destructive = false
    let onConfirm: () -> Void
    @Environment(\.dkOverlay) private var overlay
    
    var body: some View {
        DKModalPanel(title, width: 460) {
            VStack(alignment: .leading, spacing: DK.Space.m) {
                if let message {
                    Text(message)
                        .font(DK.Font.body)
                        .foregroundColor(DK.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !commands.isEmpty {
                    VStack(alignment: .leading, spacing: DK.Space.xs) {
                        Text(commands.count == 1 ? "將執行的指令" : "將執行的指令（\(commands.count) 個）")
                            .font(DK.Font.micro)
                            .foregroundColor(DK.textTertiary)
                        ForEach(Array(commands.enumerated()), id: \.offset) { DKCommandBlock(command: $0.element) }
                    }
                }
            }
        } footer: {
            DKButton("取消") { overlay?.dismissModal() }
                .keyboardShortcut(.cancelAction)
            // Return only confirms non-destructive actions; removals must be clicked.
            if destructive {
                DKButton(confirmTitle, kind: .danger) {
                    overlay?.dismissModal()
                    onConfirm()
                }
            } else {
                DKButton(confirmTitle, kind: .primary) {
                    overlay?.dismissModal()
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

extension DKOverlayCenter {
    func confirm(_ title: String, message: String? = nil, commands: [String] = [], confirmTitle: String,
                 destructive: Bool = false, onConfirm: @escaping () -> Void) {
        present {
            DKConfirmPanel(title: title, message: message, commands: commands, confirmTitle: confirmTitle,
                           destructive: destructive, onConfirm: onConfirm)
        }
    }
}

// MARK: - Settings rows

struct DKSettingRow<Control: View>: View {
    let title: String
    var detail: String?
    let control: Control
    
    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: DK.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DK.Font.body)
                    .foregroundColor(DK.textPrimary)
                if let detail {
                    Text(detail)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
                .fixedSize()
        }
        .padding(.vertical, DK.Space.m)
    }
}

// MARK: - Visual accents

/// A monochrome SF Symbol on a neutral tile.
struct DKIconTile: View {
    let systemName: String
    var size: CGFloat = 28
    var tint: Color = DK.textSecondary
    
    init(_ systemName: String, size: CGFloat = 28, tint: Color = DK.textSecondary) {
        self.systemName = systemName
        self.size = size
        self.tint = tint
    }
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(DK.surfaceHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .stroke(DK.border, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Where a package comes from.
enum DKSource {
    case npm, python, homebrew, cask, ai, database
    
    init(_ type: PackageType) {
        switch type {
        case .npm: self = .npm
        case .python: self = .python
        case .brewFormula: self = .homebrew
        case .brewCask: self = .cask
        case .database: self = .database
        case .uvTool: self = .python
        }
    }
    
    var label: String {
        switch self {
        case .npm: return "npm"
        case .python: return "Py"
        case .homebrew: return "brew"
        case .cask: return "app"
        case .ai: return "AI"
        case .database: return "DB"
        }
    }
    
    var name: String {
        switch self {
        case .npm: return "npm"
        case .python: return "Python"
        case .homebrew: return "Homebrew"
        case .cask: return "Homebrew 應用程式"
        case .ai: return "AI 工具"
        case .database: return "資料庫"
        }
    }
    
    fileprivate var colors: (background: Color, text: Color) {
        switch self {
        case .npm: return DK.Brand.npm
        case .python: return DK.Brand.python
        case .homebrew: return DK.Brand.homebrew
        case .cask: return DK.Brand.cask
        case .ai: return DK.Brand.ai
        case .database: return DK.Brand.database
        }
    }
}

/// A brand-coloured monogram that identifies a package source (not the vendor's logo artwork).
struct DKSourceBadge: View {
    let source: DKSource
    var size: CGFloat = 28
    
    init(_ source: DKSource, size: CGFloat = 28) {
        self.source = source
        self.size = size
    }
    
    var body: some View {
        Image(systemName: source.symbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundColor(source.colors.text)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size >= 24 ? DK.Radius.control : DK.Radius.inner, style: .continuous)
                    .fill(source.colors.background)
            )
            .accessibilityLabel(source.name)
    }
}

extension DKSource {
    /// The glyph shown in badges and used as a package's fallback icon.
    var symbol: String {
        switch self {
        case .npm: return "cube"
        case .python: return "curlybraces"
        case .homebrew: return "mug"
        case .cask: return "macwindow"
        case .ai: return "sparkles"
        case .database: return "cylinder.split.1x2"
        }
    }
    
    /// The hue used for this source's badge and dot.
    var tint: Color { colors.text }
}

/// A package's own avatar: its first letter on a soft tint chosen from the name, so every package looks different
/// and stays the same between launches. A small dot at the corner marks the source.
struct DKPackageAvatar: View {
    let name: String
    let source: DKSource
    var size: CGFloat = 32
    
    /// First matching keyword wins, so list the specific ones first.
    private static let rules: [(keys: [String], symbol: String)] = [
        (["sql", "postgres", "mongo", "redis", "maria", "mysql", "duckdb", "sqlite"], "cylinder.split.1x2"),
        (["ssl", "openssl", "libressl", "tls", "crypt", "gpg", "gnupg", "openssh", "keychain", "cert", "pass"], "lock.shield"),
        (["git", "gh", "lazygit", "hub"], "arrow.triangle.branch"),
        (["docker", "podman", "kube", "helm", "colima", "container"], "shippingbox"),
        (["ffmpeg", "video", "vlc", "mpv", "x264", "x265", "handbrake"], "film"),
        (["image", "png", "jpeg", "jpg", "webp", "pillow", "vips", "magick", "svg", "cairo"], "photo"),
        (["audio", "sound", "lame", "flac", "opus", "sox", "music"], "waveform"),
        (["curl", "wget", "http", "request", "axios", "nghttp", "aiohttp", "urllib", "dns", "nmap", "ssh"], "network"),
        (["eslint", "prettier", "lint", "ruff", "black", "flake", "mypy", "pylint", "format", "stylelint"], "checkmark.seal"),
        (["test", "jest", "mocha", "vitest", "pytest", "playwright", "puppeteer", "cypress", "selenium"], "testtube.2"),
        (["typescript", "babel", "webpack", "vite", "rollup", "esbuild", "tsc", "swc", "parcel", "turbo", "build", "cmake", "make", "ninja", "gcc", "llvm"], "hammer"),
        (["numpy", "pandas", "scipy", "matplotlib", "torch", "tensor", "sklearn", "scikit", "jupyter", "notebook", "polars"], "chart.xyaxis.line"),
        (["openai", "anthropic", "claude", "gemini", "llm", "langchain", "ollama", "transformers", "codex", "copilot", "gpt"], "sparkles"),
        (["node", "deno", "bun", "python", "ruby", "go", "rust", "java", "php", "perl", "lua", "swift", "kotlin", "pyenv", "nvm", "fnm", "rbenv", "uv", "pip", "pipx", "pnpm", "yarn", "npm", "cargo"], "chevron.left.forwardslash.chevron.right"),
        (["vim", "nvim", "neovim", "emacs", "nano", "code", "editor", "studio", "zed"], "pencil.and.outline"),
        (["zsh", "bash", "fish", "tmux", "shell", "starship", "fzf", "ripgrep", "bat", "eza", "htop", "btop", "jq", "tree", "terminal", "iterm", "warp", "ghostty", "alacritty", "kitty"], "terminal"),
        (["zip", "tar", "gzip", "bzip", "xz", "zstd", "lz4", "7z", "unrar", "archive", "brotli"], "archivebox"),
        (["font"], "textformat"),
        (["browser", "chrome", "firefox", "brave", "safari", "arc", "edge"], "globe"),
        (["slack", "discord", "zoom", "telegram", "whatsapp", "signal", "mail", "teams", "chat"], "bubble.left.and.bubble.right"),
        (["cloud", "aws", "azure", "gcloud", "terraform", "ansible", "vercel", "netlify", "firebase", "supabase", "wrangler"], "cloud"),
        (["json", "yaml", "toml", "xml", "csv", "markdown", "pandoc", "protobuf"], "doc.text"),
        (["server", "nginx", "apache", "caddy", "express", "flask", "django", "fastapi", "uvicorn", "gunicorn"], "server.rack"),
    ]
    
    private var symbol: String {
        let key = name.lowercased()
        // Match whole words first so "go" does not light up "mongo" or "gopls".
        let words = Set(key.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        for rule in Self.rules where rule.keys.contains(where: { words.contains($0) }) { return rule.symbol }
        for rule in Self.rules where rule.keys.contains(where: { $0.count > 3 && key.contains($0) }) { return rule.symbol }
        return source.symbol
    }
    
    var body: some View {
        let colors = source.colors
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundColor(colors.text)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(colors.background)
            )
            .accessibilityLabel("\(name)，\(source.name)")
            .dkTooltip(source.name)
    }
}

/// Thin proportion bar, e.g. outdated / total.
struct DKBar: View {
    let value: Double
    var tint: Color = DK.accent
    var height: CGFloat = 4
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DK.border)
                Capsule()
                    .fill(tint)
                    .frame(width: value > 0 ? max(proxy.size.width * CGFloat(min(value, 1)), height) : 0)
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((min(max(value, 0), 1)) * 100))%")
    }
}

/// Stacked bar showing how a total splits into parts (e.g. vulnerabilities by severity).
struct DKSegmentBar: View {
    let segments: [(value: Double, color: Color)]
    var height: CGFloat = 6
    
    var body: some View {
        let total = segments.reduce(0) { $0 + $1.value }
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if total <= 0 {
                    Capsule().fill(DK.border)
                } else {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.value > 0 {
                            Capsule()
                                .fill(segment.color)
                                .frame(width: max((proxy.size.width - CGFloat(segments.count - 1) * 2) * CGFloat(segment.value / total), height))
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Large number with a label, an optional icon and an optional proportion bar.
struct DKMetricCard: View {
    let title: String
    let value: String
    var caption: String?
    var systemImage: String?
    var source: DKSource?
    var barValue: Double?
    var valueColor: Color = DK.textPrimary
    /// Puts the caption on its own line under the number, for narrow cards where it would be cut off.
    var captionBelow = false
    var action: (() -> Void)?
    @State private var isHovering = false
    
    var body: some View {
        let content = VStack(alignment: .leading, spacing: DK.Space.s) {
            HStack(spacing: DK.Space.m) {
                if let source {
                    DKSourceBadge(source, size: 28)
                } else if let systemImage {
                    DKIconTile(systemImage, size: 28)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: DK.Space.xs) {
                        Text(value)
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(valueColor)
                            .lineLimit(1)
                        if let caption, !captionBelow {
                            Text(caption)
                                .font(DK.Font.caption)
                                .foregroundColor(DK.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    if let caption, captionBelow {
                        Text(caption)
                            .font(DK.Font.caption)
                            .foregroundColor(DK.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if let barValue {
                DKBar(value: barValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .dkCard()
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .stroke(isHovering ? DK.textTertiary.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        
        if let action {
            Button(action: action) { content.contentShape(Rectangle()) }
                .buttonStyle(DKPressStyle())
                .onHover { isHovering = $0 }
        } else {
            content
        }
    }
}
