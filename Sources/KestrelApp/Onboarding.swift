import SwiftUI
import AppKit
import KestrelCore

/// A one-time welcome shown on first launch: what Kestrel is, the safety model, and the
/// two optional setup steps (Full Disk Access, the opt-in AI key).
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "bird.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(LinearGradient(colors: [Palette.kestrel, Palette.kestrel.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                               in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(L("Welcome to Kestrel")).font(.title.weight(.bold))
                Text(L("A fast, honest Mac cleaner. Nothing is deleted outright — everything moves to a vault you can undo, and nothing ever leaves this Mac."))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                step(icon: "checkmark.shield", tint: Palette.good,
                     title: L("Safe by design"), detail: L("Dry-run by default, vault + undo, honest reports — no scare tactics."))
                step(icon: "lock.shield", tint: Palette.warn,
                     title: L("Full Disk Access (optional)"), detail: L("Lets Kestrel see the Trash, Mail and some caches. Grant it in System Settings, then relaunch."),
                     action: (L("Open settings"), { if let url = URL(string: FullDiskAccess.settingsURL) { NSWorkspace.shared.open(url) } }))
                step(icon: "sparkles", tint: Palette.violet,
                     title: L("AI assistant (optional, off)"), detail: L("Add a Gemini key to enable it. It only ever sends metadata — never file contents."))
            }

            Button { model.finishOnboarding() } label: {
                Text(L("Get started")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.kestrel(.prominent))
        }
        .padding(28)
        .frame(width: 460)
    }

    private func step(icon: String, tint: Color, title: String, detail: String, action: (String, () -> Void)? = nil) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let action {
                        Button(action.0, action: action.1).buttonStyle(.kestrel(.secondary, size: .small)).padding(.top, 3)
                    }
                }
                Spacer()
            }
        }
    }
}
