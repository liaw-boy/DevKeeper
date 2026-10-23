import SwiftUI

/// Settings card: detect Python interpreters, choose which one DevKeeper uses, upgrade or install versions.
struct PythonEnvironmentCard: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showUVConfirm = false
    @State private var uvConfirmIsForUpgrade = false
    
    private var needsUV: Bool {
        !viewModel.isScanningPython && !viewModel.availableManagers.contains(.uv)
    }
    
    var body: some View {
        content
            .confirmationDialog(
                "要執行遠端下載的安裝腳本嗎？",
                isPresented: $showUVConfirm,
                titleVisibility: .visible
            ) {
                Button("確認並執行", role: .destructive) {
                    let forUpgrade = uvConfirmIsForUpgrade
                    Task {
                        if forUpgrade {
                            await viewModel.upgradeToRecommendedPython(confirmedRemoteScript: true)
                        } else {
                            await viewModel.installUV(confirmedRemoteScript: true)
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("沒有偵測到 Homebrew，將執行 uv 官方安裝腳本，並直接交給 shell 執行：\n\ncurl -LsSf https://astral.sh/uv/install.sh | sh\n\n請確認你信任該來源。")
            }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DevKeeper 掃描與修復 pip 套件時使用的 Python。系統內建的 Python 屬於 macOS，無法升級；建議使用仍在支援期內的版本（目前建議 3.13）。")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if !viewModel.endOfLifePythons.isEmpty { endOfLifeBanner }
            
            VStack(spacing: 6) {
                autoRow
                ForEach(viewModel.pythonInterpreters) { interpreter in
                    interpreterRow(interpreter)
                }
            }
            
            if viewModel.pythonInterpreters.isEmpty {
                Text(viewModel.isScanningPython ? "偵測中..." : "沒有偵測到可用的 Python。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
            
            if needsUV { uvBanner }
            
            installSection
            
            HStack(spacing: 10) {
                if let label = viewModel.pythonActionLabel {
                    ProgressView().controlSize(.small)
                    Text("\(label)中，詳細輸出請見「執行日誌」")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                } else if viewModel.isScanningPython {
                    ProgressView().controlSize(.small)
                    Text("正在偵測 Python...")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                pillButton("重新偵測", icon: "arrow.clockwise") {
                    Task { await viewModel.scanPythonInterpreters() }
                }
                .disabled(viewModel.isScanningPython || viewModel.isActionRunning)
            }
        }
    }
    
    // MARK: - Rows
    
    private var autoRow: some View {
        let isSelected = viewModel.isPythonAutoSelected
        let current = viewModel.selectedPythonPath.flatMap { path in
            viewModel.pythonInterpreters.first { $0.path == path }
        }
        return Button {
            Task { await viewModel.selectPython(nil) }
        } label: {
            HStack(spacing: 10) {
                radio(isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text("自動選擇（建議）")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(current.map { "目前選用 Python \($0.version)（\($0.source.rawValue)）" } ?? "尚無可用的 Python")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .rowBackground(selected: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isActionRunning)
    }
    
    private func interpreterRow(_ interpreter: PythonInterpreter) -> some View {
        let isSelected = !viewModel.isPythonAutoSelected && viewModel.selectedPythonPath == interpreter.path
        let isInUse = viewModel.selectedPythonPath == interpreter.path
        let target = viewModel.upgradeTarget(for: interpreter)
        return HStack(spacing: 10) {
            Button {
                Task { await viewModel.selectPython(interpreter) }
            } label: {
                HStack(spacing: 10) {
                    radio(isSelected)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Python \(interpreter.version)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(.primary)
                            badge(interpreter.source.rawValue, tint: Theme.infoCyan)
                            if interpreter.isExternallyManaged {
                                badge("受管理 (PEP 668)", tint: Theme.warningAmber)
                                    .help("此 Python 禁止直接用 pip 修改套件，只能讀取與掃描。")
                            }
                            lifecycleBadge(interpreter)
                            if isInUse {
                                badge("使用中", tint: Theme.successGreen)
                            }
                            if !interpreter.hasPip {
                                badge("無 pip", tint: Theme.dangerRed)
                            }
                        }
                        Text(interpreter.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isActionRunning || !interpreter.hasPip)
            
            if let target {
                pillButton("升級至 \(target)", icon: "arrow.up.circle", prominent: true) {
                    Task { await viewModel.upgradePython(interpreter) }
                }
                .disabled(viewModel.isActionRunning)
            } else if !interpreter.canUpgrade {
                Text("系統內建，無法升級")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            } else {
                Text("已是最新")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .rowBackground(selected: isSelected)
    }
    
    // MARK: - Lifecycle
    
    @ViewBuilder
    private func lifecycleBadge(_ interpreter: PythonInterpreter) -> some View {
        switch interpreter.lifecycle {
        case .endOfLife(let date):
            badge("已終止支援 \(date)", tint: Theme.dangerRed)
                .help("Python \(interpreter.minorVersion) 已不再收到安全修補。")
        case .endingSoon(let date):
            badge("支援至 \(date)", tint: Theme.warningAmber)
        case .supported(let date):
            badge("支援至 \(date)", tint: .secondary)
        }
    }
    
    private var endOfLifeBanner: some View {
        let eol = viewModel.endOfLifePythons
        let list = eol.map { "\($0.version)（\($0.source.rawValue)）" }.joined(separator: "、")
        let needsInstall = viewModel.needsRecommendedPython
        let viaBrew = viewModel.availableManagers.contains(.homebrew)
        let uvReady = viewModel.availableManagers.contains(.uv)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundColor(Theme.dangerRed)
            VStack(alignment: .leading, spacing: 3) {
                Text("有 Python 版本已終止支援：\(list)")
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(needsInstall
                     ? "終止支援的版本不再收到安全修補，套件也不再發布相容的新版本。建議升級到 Python \(PythonLifecycle.recommendedMinor)。"
                     : "已安裝 Python \(PythonLifecycle.recommendedMinor)。請到「安全弱點稽核」，用卡片上的「搬到獨立環境」或「移除套件」清理舊環境裡的套件。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if needsInstall {
                pillButton("一鍵升級到 \(PythonLifecycle.recommendedMinor)", icon: "arrow.up.circle", prominent: true) {
                    if uvReady || viaBrew {
                        Task { await viewModel.upgradeToRecommendedPython() }
                    } else {
                        uvConfirmIsForUpgrade = true
                        showUVConfirm = true
                    }
                }
                .disabled(viewModel.isActionRunning)
            } else {
                pillButton("前往安全稽核", icon: "shield.checkered") {
                    viewModel.selectedTab = .security
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.dangerRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.dangerRed.opacity(0.35), lineWidth: 1)
        )
    }
    
    // MARK: - uv
    
    private var uvBanner: some View {
        let viaBrew = viewModel.availableManagers.contains(.homebrew)
        return HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundColor(Theme.primaryIndigo)
            VStack(alignment: .leading, spacing: 2) {
                Text("尚未安裝 uv（建議）")
                    .font(.system(size: 12, weight: .semibold))
                Text("uv 不需要 Homebrew 就能安裝新版 Python，並把命令列工具放進各自獨立的環境，用來修復舊 Python 無法升級的套件。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            pillButton(viaBrew ? "用 Homebrew 安裝 uv" : "安裝 uv", icon: "arrow.down.circle", prominent: true) {
                if viaBrew {
                    Task { await viewModel.installUV() }
                } else {
                    uvConfirmIsForUpgrade = false
                    showUVConfirm = true
                }
            }
            .disabled(viewModel.isActionRunning)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.primaryIndigo.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.primaryIndigo.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Install
    
    @ViewBuilder
    private var installSection: some View {
        if !viewModel.installablePythons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("安裝新版本")
                    .font(.system(size: 12, weight: .semibold))
                FlowChips(items: viewModel.installablePythons) { release in
                    pillButton("\(release.source.rawValue) \(release.version)", icon: "plus") {
                        Task { await viewModel.installPython(release) }
                    }
                    .disabled(viewModel.isActionRunning)
                }
            }
        }
    }
    
    // MARK: - Pieces
    
    private func radio(_ selected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(selected ? Theme.primaryIndigo : Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 15, height: 15)
            if selected {
                Circle().fill(Theme.primaryIndigo).frame(width: 7.5, height: 7.5)
            }
        }
    }
    
    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }
    
    private func pillButton(_ title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(prominent ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(prominent ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.bouncy)
    }
}

private extension View {
    func rowBackground(selected: Bool) -> some View {
        self
            .background(selected ? Theme.primaryIndigo.opacity(0.08) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Theme.primaryIndigo.opacity(0.45) : Theme.subtleBorder, lineWidth: 1)
            )
    }
}

/// Simple wrapping layout for chips.
private struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { item in content(item) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
