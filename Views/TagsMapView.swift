import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore

struct TagsMapView: View {
  @StateObject private var location = LocationManager()
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
  )
  @State private var tags: [Tag] = []
  @State private var status: String = ""
  @State private var liveUpdates = true
  @State private var listener: ListenerRegistration?
  @State private var didCenterOnUser = false

  private let service = TagService()

  var body: some View {
    VStack(spacing: 8) {
      Map(coordinateRegion: $region, annotationItems: tags) { tag in
        MapMarker(
          coordinate: CLLocationCoordinate2D(latitude: tag.lat, longitude: tag.lng),
          tint: .blue
        )
      }
      .onAppear {
        // Start location and live updates immediately
        location.requestWhenInUse()
        if let loc = location.lastLocation { region.center = loc.coordinate }
        if liveUpdates { startLive() } else { loadHere() }
      }
      .onDisappear { stopLive() }
      .frame(minHeight: 350)

      HStack {
        Button("My location") { centerOnMe() }
        Spacer()
        Button("Load tags here") { loadHere() }
        Spacer()
        Button("Drop tag here") { createHere() }
      }
      .padding(.horizontal)

      Toggle("Live updates", isOn: $liveUpdates)
        .padding(.horizontal)
        .onChange(of: liveUpdates) { _, newValue in
          newValue ? startLive() : stopLive()
        }

      if !status.isEmpty {
        Text(status).font(.caption).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Map")
    .padding(.bottom)
  }

  private func centerOnMe() {
    if let loc = location.lastLocation {
      withAnimation { region.center = loc.coordinate }
      status = "Centered on you"
    } else {
      status = "Requesting location…"
    }
  }

  // When we first get a GPS fix, center once and optionally restart live listener
  init() {
    // Observe location changes via NotificationCenter would be overkill; we'll use a small delay loop
    // Not used in previews
  }

  private func loadHere() {
    let c = region.center
    Task {
      do {
        let found = try await service.tagsNear(lat: c.latitude, lng: c.longitude, delta: 0.03)
        await MainActor.run { self.tags = found; self.status = "Loaded \(found.count) tags" }
      } catch {
        await MainActor.run { self.status = "Load failed: \(error.localizedDescription)" }
      }
    }
  }

  private func createHere() {
    do {
      try service.createTextTag(lat: region.center.latitude, lng: region.center.longitude, text: "New tag")
      status = "Created at center"
      loadHere()
    } catch { status = "Create failed: \(error.localizedDescription)" }
  }

  private func startLive() {
    stopLive()
    let c = region.center
    listener = service.listenTagsNear(lat: c.latitude, lng: c.longitude, delta: 0.03) { items in
      DispatchQueue.main.async {
        self.tags = items
        self.status = "Live: \(items.count) tags"
      }
    }
  }

  private func stopLive() {
    listener?.remove()
    listener = nil
  }
}

#Preview {
  NavigationView { TagsMapView() }
}
