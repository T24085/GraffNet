import SwiftUI

struct ContentView: View {
  @State private var text: String = "Hello, StreetGraf!"
  @State private var lat: String = "37.7749"      // Default: SF
  @State private var lng: String = "-122.4194"
  @State private var status: String = ""
  @State private var tags: [Tag] = []

  private let service = TagService()

  var body: some View {
    VStack(spacing: 16) {
      Group {
        TextField("Tag text", text: $text)
          .textFieldStyle(.roundedBorder)
        HStack {
          TextField("Latitude", text: $lat).textFieldStyle(.roundedBorder)
          TextField("Longitude", text: $lng).textFieldStyle(.roundedBorder)
        }
      }

      HStack {
        Button("Create text tag") { create() }
        Button("Load nearby") { load() }
      }

      if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }

      List(tags) { tag in
        VStack(alignment: .leading, spacing: 4) {
          Text(tag.text ?? "(no text)")
          Text(String(format: "(%.4f, %.4f)", tag.lat, tag.lng))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding()
    .navigationTitle("GraffNet Demo")
  }

  private func create() {
    guard let la = Double(lat), let lo = Double(lng) else { status = "Invalid lat/lng"; return }
    do {
      try service.createTextTag(lat: la, lng: lo, text: text)
      status = "Created!"
    } catch {
      status = "Create failed: \(error.localizedDescription)"
    }
  }

  private func load() {
    guard let la = Double(lat), let lo = Double(lng) else { status = "Invalid lat/lng"; return }
    Task {
      do {
        let items = try await service.tagsNear(lat: la, lng: lo, delta: 0.02)
        await MainActor.run {
          self.tags = items
          self.status = "Loaded \(items.count) tags"
        }
      } catch {
        await MainActor.run { self.status = "Load failed: \(error.localizedDescription)" }
      }
    }
  }
}

#Preview {
  NavigationView { ContentView() }
}

