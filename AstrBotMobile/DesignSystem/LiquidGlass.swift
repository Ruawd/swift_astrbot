import SwiftUI

enum AstrBotPalette {
    static let blue = Color(red: 0.18, green: 0.53, blue: 0.78)
    static let cyan = Color(red: 0.12, green: 0.78, blue: 0.92)
    static let indigo = Color(red: 0.35, green: 0.38, blue: 0.93)
    static let darkBackground = Color(red: 0.025, green: 0.04, blue: 0.075)
}

struct LiquidBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            (colorScheme == .dark ? AstrBotPalette.darkBackground : Color(.systemGroupedBackground))
                .ignoresSafeArea()

            Circle()
                .fill(AstrBotPalette.blue.opacity(colorScheme == .dark ? 0.34 : 0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 80)
                .offset(x: animate && !reduceMotion ? 130 : 80, y: animate && !reduceMotion ? -290 : -240)

            Circle()
                .fill(AstrBotPalette.indigo.opacity(colorScheme == .dark ? 0.26 : 0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: animate && !reduceMotion ? -150 : -100, y: animate && !reduceMotion ? 330 : 270)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let interactive: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: radius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: radius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 0.7)
                }
        }
    }
}

extension View {
    func glassSurface(interactive: Bool = false, radius: CGFloat = 22) -> some View {
        modifier(GlassSurfaceModifier(interactive: interactive, radius: radius))
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: 22)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 134, alignment: .leading)
        .glassSurface(interactive: true, radius: 22)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(description))
            .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct LoadingOverlay: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface(radius: 18)
    }
}

struct ToastView: View {
    let message: ToastMessage

    private var icon: String {
        switch message.style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch message.style {
        case .success: return .green
        case .error: return .red
        case .info: return AstrBotPalette.blue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(message.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassSurface(radius: 18)
        .accessibilityElement(children: .combine)
    }
}
