import SwiftUI

struct AstrBotLogo: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AstrBotPalette.cyan, AstrBotPalette.blue, AstrBotPalette.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AstrBotPalette.blue.opacity(0.3), radius: 22, y: 10)
        .accessibilityLabel("AstrBot")
    }
}
