import SwiftUI

/// The two skins. Classic is the app as it always was; Now makes the countdown
/// the home screen and demotes Plan / Day to setup tabs. Same data, same
/// engine, same armed snapshot — flipping mid-countdown loses nothing.
enum Skin {
    static let storageKey = "backplan.skin"
    static let classic = "classic"
    static let now = "now"
}

private struct NowSkinKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside the Now skin. The reused Plan / Day screens read it to drop
    /// their arm bar — starting and stopping lives on the Now screen there.
    var nowSkin: Bool {
        get { self[NowSkinKey.self] }
        set { self[NowSkinKey.self] = newValue }
    }
}

/// The one small control that moves between skins. In Classic it is the only
/// trace of the Now skin; in Now it is the way back.
struct SkinSwitchButton: View {
    @AppStorage(Skin.storageKey) private var skin = Skin.classic

    var body: some View {
        let inNow = skin == Skin.now
        Button {
            skin = inNow ? Skin.classic : Skin.now
        } label: {
            Text(inNow ? "Classic layout" : "Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.bpPurpleElectric)
        }
        .accessibilityLabel(inNow ? "Switch to the classic layout" : "Switch to the Now layout")
    }
}
