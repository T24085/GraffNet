import SwiftUI
import MapKit
import CoreLocation

struct TagsMapView: View {
  @StateObject private var location = LocationManager()
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
  )
  @State private var tags: [Tag] = []
  @State private var status: String = ""

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
        // Center on current location if available
        location.requestWhenInUse()
        if let loc = location.lastLocation {
          region.center = loc.coordinate
        }
      }
      .frame(minHeight: 350)

      HStack {
        Button("My location") { centerOnMe() }
        Spacer()
        Button("Load tags here") { loadHere() }
        Spacer()
        Button("Drop tag here") { createHere() }
      }
      .padding(.horizontal)

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
}

#Preview {
  NavigationView { TagsMapView() }
}

