import SwiftUI

public struct StatusBadge: View {
    public let status: UpdateStatus
    
    public init(status: UpdateStatus) {
        self.status = status
    }
    
    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.sfSymbol)
                .font(.system(size: 9.5, weight: .semibold))
            Text(status.localizedTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .foregroundColor(badgeColor)
        .background(badgeColor.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(badgeColor.opacity(0.28), lineWidth: 0.8)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private var badgeColor: Color {
        switch status {
        case .upToDate:
            return Theme.successGreen
        case .patch:
            return Theme.infoCyan
        case .minor:
            return Theme.primaryIndigo
        case .major:
            return Theme.warningAmber
        case .updateAvailable:
            return Theme.primaryIndigo
        case .checking:
            return Color.secondary
        case .error:
            return Theme.dangerRed
        }
    }
}
