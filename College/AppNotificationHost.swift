import SwiftUI

struct AppNotificationHost: View {
    @EnvironmentObject private var notificationCenter: AppNotificationCenter

    // Match the screenshot: stacked cards, subtle shadow, close button.
    private let maxVisible: Int = 3

    var body: some View {
        GeometryReader { proxy in
            VStack {
                HStack {
                    Spacer()

                    VStack(alignment: .trailing, spacing: 12) {
                        ForEach(notificationCenter.notifications.prefix(maxVisible)) { n in
                            AppNotificationToast(notification: n)
                                .environmentObject(notificationCenter)
                        }
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 22)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(!notificationCenter.notifications.isEmpty)
    }
}

private struct AppNotificationToast: View {
    @EnvironmentObject private var notificationCenter: AppNotificationCenter

    let notification: AppNotificationCenter.AppNotification

    private var accent: Color { notification.kind.accentColor }

    private var percentText: String? {
        guard let p = notification.progress else { return nil }
        return "\(Int((p * 100).rounded()))%"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: notification.kind.iconSystemName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(DesignSystem.Fonts.main(size: 15, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textMain)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let percentText {
                        Text(percentText)
                            .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                            .foregroundColor(accent)
                    }

                    if notification.isDismissible {
                        Button(action: { notificationCenter.dismiss(id: notification.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.textLight)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(notification.message)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textLight)
                    .fixedSize(horizontal: false, vertical: true)

                if let p = notification.progress {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(DesignSystem.Colors.textLight.opacity(0.14))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 999)
                            .fill(accent.opacity(0.95))
                            .frame(width: max(0, min(1, p)) * 260, height: 8)
                    }
                    .frame(width: 260, height: 8)
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DesignSystem.Colors.textLight.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 8)
    }
}
