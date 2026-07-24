import SwiftUI

struct UnsupportedView: View {
    var body: some View {
        ContentUnavailableView(
            "AR Not Supported",
            systemImage: "arkit",
            description: Text(
                "Dav's Firmament needs a device with ARKit world tracking to draw the lattice over the sky."
            )
        )
    }
}
