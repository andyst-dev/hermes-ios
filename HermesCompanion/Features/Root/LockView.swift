import SwiftUI

/// Full-screen lock shown over the whole app when the Face ID toggle is on.
struct LockView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ZStack {
            HermesTheme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HermesTheme.primary)
                    .padding(.bottom, 4)
                Text("HERMES")
                    .font(HermesTheme.brandSerif(size: 34))
                    .tracking(1.2)
                    .foregroundStyle(HermesTheme.ink)
                Text("Companion")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HermesTheme.mutedForeground)
                Spacer()
                if let error = store.faceIDUnlockError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(HermesTheme.warm)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 10)
                }
                Button {
                    Task { await store.unlockWithFaceID() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Unlock")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 44)
            }
        }
    }
}
