import SwiftUI

struct AppBackground: View {
  var body: some View {
    ZStack {
      Image("GraffNetBanner")
        .resizable()
        .scaledToFill()
        .overlay(Color.black.opacity(0.25))
      LinearGradient(
        colors: [Color.black.opacity(0.15), Color.clear, Color.black.opacity(0.25)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }
}

#Preview {
  AppBackground()
}

