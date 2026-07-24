import SwiftUI

struct StatusHUD: View {
    let fix: GeoFix?
    let isDenied: Bool

    var body: some View {
        if let statusText {
            Text(statusText)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
        }
    }

    /// Only surfaces states the user must act on; the normal running view
    /// shows no HUD at all.
    private var statusText: String? {
        if isDenied {
            return "Location access denied — enable it in Settings to see the lattice"
        }
        if fix == nil {
            return "Waiting for GPS fix…"
        }
        return nil
    }
}
