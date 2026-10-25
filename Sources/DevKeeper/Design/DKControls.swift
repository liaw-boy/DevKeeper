import SwiftUI

// MARK: - Press feedback

/// The single press style: slight fade, no scaling or springs.
struct DKPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Button

struct DKButton: View {
    enum Kind { case primary, secondary, danger, ghost }
    
    let title: String
    var kind: Kind = .secondary
    var isLoading = false
    /// Shown as a tooltip when the button is disabled, so it is clear why nothing happens.
    var disabledReason: String?
    let action: () -> Void
    
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    
    init(_ title: String, kind: Kind = .secondary, isLoading: Bool = false, disabledReason: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.isLoading = isLoading
        self.disabledReason = disabledReason
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DK.Space.tight) {
                if isLoading {
                    DKSpinner(size: 12, color: foreground)
                }
                Text(title)
                    .font(DK.Font.bodyMedium)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, DK.Space.m)
            .frame(height: DK.controlHeight)
            .foregroundColor(foreground)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .disabled(isLoading)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 && isEnabled }
        .dkTooltip(isEnabled ? nil : disabledReason)
    }
    
    private var foreground: Color {
        switch kind {
        case .primary: return DK.inverseText
        case .secondary, .ghost: return DK.textPrimary
        case .danger: return DK.danger
        }
    }
    
    private var background: Color {
        switch kind {
        case .primary: return DK.inverseBackground.opacity(isHovering ? 0.88 : 1)
        case .secondary, .danger: return isHovering ? DK.surfaceHover : DK.surface
        case .ghost: return isHovering ? DK.surfaceHover : .clear
        }
    }
    
    private var borderColor: Color {
        switch kind {
        case .primary, .ghost: return .clear
        case .secondary, .danger: return DK.border
        }
    }
}

// MARK: - Icon button

struct DKIconButton: View {
    let systemName: String
    let help: String
    var compact = false
    let action: () -> Void
    
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    
    init(_ systemName: String, help: String, compact: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.compact = compact
        self.action = action
    }
    
    var body: some View {
        let side = compact ? DK.compactControlHeight : DK.controlHeight
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: DK.Icon.regular))
                .foregroundColor(DK.textSecondary)
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                        .fill(isHovering ? DK.surfaceHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 && isEnabled }
        .dkTooltip(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Activity

struct DKSpinner: View {
    var size: CGFloat = 14
    var color: Color = DK.textSecondary
    @State private var rotating = false
    
    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = true }
            .accessibilityLabel("處理中")
    }
}

/// Determinate when `value` is set; otherwise an indeterminate moving segment.
struct DKProgressBar: View {
    var value: Double?
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(DK.border)
                if let value {
                    Rectangle()
                        .fill(DK.textPrimary)
                        .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
                } else {
                    DKIndeterminateSegment(trackWidth: proxy.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        }
        .frame(height: 2)
    }
}

/// Has its own state so the animation starts fresh every time it appears.
private struct DKIndeterminateSegment: View {
    let trackWidth: CGFloat
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(DK.textPrimary)
            .frame(width: trackWidth * 0.3)
            .offset(x: trackWidth * 1.3 * phase - trackWidth * 0.3)
            .onAppear {
                phase = 0
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

// MARK: - Switch

struct DKSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isOn ? DK.inverseBackground : DK.controlTrack)
                    .frame(width: 32, height: 18)
                Circle()
                    .fill(isOn ? DK.inverseText : DK.controlKnob)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(DKPressStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "開啟" : "關閉")
    }
}

// MARK: - Segmented

struct DKSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(DK.Font.caption.weight(selected ? .medium : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundColor(selected ? DK.textPrimary : DK.textSecondary)
                        .padding(.horizontal, DK.Space.snug)
                        .frame(height: DK.controlHeight - 6)
                        .background(
                            RoundedRectangle(cornerRadius: DK.Radius.inner, style: .continuous)
                                .fill(selected ? DK.surfaceHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(DKPressStyle())
            }
        }
        .padding(2)
        .frame(height: DK.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .fill(DK.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .stroke(DK.border, lineWidth: 1)
        )
    }
}

// MARK: - Dropdown

struct DKDropdown<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    /// Optional label shown before the selected value, e.g. "排序".
    var label: String?
    
    @Environment(\.dkOverlay) private var overlay
    @Environment(\.isEnabled) private var isEnabled
    @State private var frame: CGRect = .zero
    @State private var isHovering = false
    @State private var panelOwner = UUID()
    
    var body: some View {
        Button {
            overlay?.showPanel(anchor: frame, width: max(frame.width, 160), owner: panelOwner) {
                DKDropdownPanel(options: options, selection: $selection)
            }
        } label: {
            HStack(spacing: DK.Space.tight) {
                if let label {
                    Text(label).foregroundColor(DK.textSecondary)
                }
                Text(options.first { $0.value == selection }?.title ?? "")
                    .foregroundColor(DK.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: DK.Icon.tiny, weight: .semibold))
                    .foregroundColor(DK.textTertiary)
            }
            .font(DK.Font.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, DK.Space.snug)
            .frame(height: DK.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(isHovering ? DK.surfaceHover : DK.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .stroke(DK.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 && isEnabled }
        .dkTrackFrame($frame)
        .onDisappear { overlay?.dismissPanel(owner: panelOwner) }
    }
}

struct DKDropdownPanel<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.dkOverlay) private var overlay
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.value) { option in
                DKMenuRow(title: option.title, checked: option.value == selection) {
                    selection = option.value
                    overlay?.dismissPanel()
                }
            }
        }
        .padding(DK.Space.xs)
    }
}

/// A row inside a floating panel (dropdowns and action menus).
struct DKMenuRow: View {
    let title: String
    var checked = false
    var destructive = false
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DK.Space.s) {
                Text(title)
                    .font(DK.Font.body)
                    .foregroundColor(destructive ? DK.danger : DK.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DK.Space.l)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: DK.Icon.small, weight: .semibold))
                        .foregroundColor(DK.textSecondary)
                }
            }
            .padding(.horizontal, DK.Space.s)
            .frame(height: DK.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.inner, style: .continuous)
                    .fill(isHovering ? DK.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .onHover { isHovering = $0 }
    }
}

/// An icon button that opens a list of actions.
struct DKActionMenu: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        var destructive = false
        let action: () -> Void
    }
    
    let help: String
    var systemName = "ellipsis"
    let items: [Item]
    @Environment(\.dkOverlay) private var overlay
    @State private var frame: CGRect = .zero
    @State private var panelOwner = UUID()
    
    var body: some View {
        DKIconButton(systemName, help: help) {
            overlay?.showPanel(anchor: frame, width: 220, owner: panelOwner) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        DKMenuRow(title: item.title, destructive: item.destructive) {
                            overlay?.dismissPanel()
                            item.action()
                        }
                    }
                }
                .padding(DK.Space.xs)
            }
        }
        .dkTrackFrame($frame)
        .onDisappear { overlay?.dismissPanel(owner: panelOwner) }
    }
}

// MARK: - Text input

struct DKTextField: View {
    let placeholder: String
    @Binding var text: String
    var systemImage: String?
    var monospaced = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    
    var body: some View {
        HStack(spacing: DK.Space.tight) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: DK.Icon.small))
                    .foregroundColor(DK.textTertiary)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(DK.textTertiary))
                .textFieldStyle(.plain)
                .font(monospaced ? DK.Font.mono : DK.Font.body)
                .foregroundColor(DK.textPrimary)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: DK.Icon.tiny, weight: .semibold))
                        .foregroundColor(DK.textTertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DKPressStyle())
                .accessibilityLabel("清除")
            }
        }
        .padding(.horizontal, DK.Space.snug)
        .frame(height: DK.controlHeight)
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .fill(DK.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                .stroke(focused ? DK.textSecondary : DK.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

struct DKSearchField: View {
    var placeholder = "搜尋"
    @Binding var text: String
    
    var body: some View {
        DKTextField(placeholder: placeholder, text: $text, systemImage: "magnifyingglass")
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 280)
    }
}

extension String {
    /// Search text as typed by the user, without surrounding whitespace, lowercased.
    var dkSearchKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
