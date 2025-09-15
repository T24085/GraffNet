import SwiftUI
import CoreLocation

struct ContentView: View {
  @State private var text: String = "Hello, StreetGraf!"
  @State private var lat: String = "37.7749"      // Default: SF
  @State private var lng: String = "-122.4194"
  @State private var status: String = ""
  @State private var tags: [Tag] = []

  private let service = TagService()
  @StateObject private var location = LocationManager()

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

      HStack {
        Button("Use my location") { useMyLocation() }
        Button("Create at my location") { createAtMyLocation() }
      }

      if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }

      List(tags) { tag in
        VStack(alignment: .leading, spacing: 6) {
          Text(tag.text ?? "(no text)")
          HStack(spacing: 12) {
            Text(String(format: "(%.4f, %.4f)", tag.lat, tag.lng))
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("👍 \(tag.upvotes)") { vote(tag: tag, up: true) }
              .buttonStyle(.borderless)
            Button("👎 \(tag.downvotes)") { vote(tag: tag, up: false) }
              .buttonStyle(.borderless)
          }
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

  private func useMyLocation() {
    // Request permission and update fields when a location arrives
    location.requestWhenInUse()
    if let loc = location.lastLocation {
      lat = String(format: "%.6f", loc.coordinate.latitude)
      lng = String(format: "%.6f", loc.coordinate.longitude)
    } else {
      status = "Requesting location…"
      // Poll once after a short delay to copy coordinates into fields
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        if let loc = location.lastLocation {
          lat = String(format: "%.6f", loc.coordinate.latitude)
          lng = String(format: "%.6f", loc.coordinate.longitude)
          status = "Got location"
        }
      }
    }
  }

  private func createAtMyLocation() {
    if let loc = location.lastLocation {
      do {
        try service.createTextTag(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, text: text)
        status = "Created at my location!"
      } catch { status = "Create failed: \(error.localizedDescription)" }
    } else {
      status = "No location yet; tap 'Use my location'"
    }
  }

  private func vote(tag: Tag, up: Bool) {
    guard let id = tag.id else { return }
    Task { try? await service.vote(tagId: id, up: up); await loadAfterVote() }
  }

  @MainActor private func loadAfterVote() async { load() }
}

#Preview {
  NavigationView { ContentView() }
}
