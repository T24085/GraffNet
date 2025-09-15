import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore
import FirebaseAuth

struct TagsMapView: View {
  @StateObject private var location = LocationManager()
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
  )
  @State private var tags: [Tag] = []
  @State private var status: String = ""
  @AppStorage("liveUpdatesEnabled") private var liveUpdates = true
  @AppStorage("lastCenterLat") private var storedCenterLat: Double = 37.7749
  @AppStorage("lastCenterLng") private var storedCenterLng: Double = -122.4194
  @AppStorage("lastSpanLat") private var storedSpanLat: Double = 0.02
  @AppStorage("lastSpanLng") private var storedSpanLng: Double = 0.02
  @State private var listener: ListenerRegistration?
  @State private var didCenterOnUser = false
  @State private var lastLiveCenter: CLLocationCoordinate2D?
  @State private var debounceWorkItem: DispatchWorkItem?
  @State private var selectedTag: Tag?
  @State private var tracking: MapUserTrackingMode = .none
  @State private var showCreateSheet = false
  @State private var newTagText: String = ""
  @State private var pendingCoordinate: CLLocationCoordinate2D?
  @State private var lastTouchPoint: CGPoint?
  @State private var lastCreateAt: Date?
  @State private var showActionsDialog = false

  private let service = TagService()

  var body: some View {
    VStack(spacing: 8) {
      if #available(iOS 17.0, *) {
        MapReader { proxy in
          Map(
            coordinateRegion: $region,
            showsUserLocation: true,
            userTrackingMode: $tracking,
            annotationItems: displayItems
          ) { tag in
            MapAnnotation(
              coordinate: tag.coordinate
            ) {
              if let inner = tag.tag { // real tag
                Button { selectedTag = inner } label: {
                  Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .shadow(radius: 2)
                }
                .buttonStyle(.plain)
              } else {
                // cluster
                Button { zoomIn(on: tag.coordinate) } label: {
                  ZStack {
                    Circle().fill(Color.orange.opacity(0.9))
                      .frame(width: 30, height: 30)
                    Text("\(tag.count)")
                      .font(.footnote).bold()
                      .foregroundColor(.white)
                  }
                  .shadow(radius: 2)
                }
                .buttonStyle(.plain)
              }
            }
          }
          // Capture touch location to create at press location
          .simultaneousGesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in lastTouchPoint = value.location }
          )
          .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
              .onEnded { _ in
                if let p = lastTouchPoint, let coord = proxy.convert(p, from: .local) {
                  pendingCoordinate = coord
                  showCreateSheet = true
                }
              }
          )
          // Inline callout over the selected tag
          .overlay(alignment: .topLeading) {
            if let t = selectedTag,
               let p = proxy.convert(CLLocationCoordinate2D(latitude: t.lat, longitude: t.lng), to: .local) {
              TagCallout(
                tag: t,
                isOwner: t.authorId == (Auth.auth().currentUser?.uid ?? ""),
                onUpvote: { vote(tag: t, up: true) },
                onDownvote: { vote(tag: t, up: false) },
                onDelete: { delete(tag: t) },
                onClose: { selectedTag = nil }
              )
              .position(p)
              .offset(y: -28)
            }
          }
        }
      } else {
        Map(
          coordinateRegion: $region,
          showsUserLocation: true,
          userTrackingMode: $tracking,
          annotationItems: displayItems
        ) { tag in
          MapAnnotation(coordinate: tag.coordinate) {
            if let inner = tag.tag {
              Button {
                selectedTag = inner
                showActionsDialog = true
              } label: {
                Image(systemName: "mappin.circle.fill")
                  .font(.title2)
                  .foregroundColor(.blue)
                  .shadow(radius: 2)
              }
              .buttonStyle(.plain)
            } else {
              Button { zoomIn(on: tag.coordinate) } label: {
                ZStack {
                  Circle().fill(Color.orange.opacity(0.9))
                    .frame(width: 30, height: 30)
                  Text("\(tag.count)")
                    .font(.footnote).bold()
                    .foregroundColor(.white)
                }
                .shadow(radius: 2)
              }
              .buttonStyle(.plain)
            }
          }
        }
        // Long press fallback: open sheet to create at map center
        .simultaneousGesture(
          LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in pendingCoordinate = nil; showCreateSheet = true }
        )
      }
      .onAppear {
        // Start location and live updates immediately
        location.requestWhenInUse()
        // Restore last viewed region
        region.center = CLLocationCoordinate2D(latitude: storedCenterLat, longitude: storedCenterLng)
        region.span = MKCoordinateSpan(latitudeDelta: storedSpanLat, longitudeDelta: storedSpanLng)
        if let loc = location.lastLocation, !didCenterOnUser {
          // If GPS is ready at launch, prefer centering on user once
          region.center = loc.coordinate
        }
        if liveUpdates { startLive() } else { loadHere() }
      }
      .onDisappear { stopLive() }
      .onChange(of: region.center.latitude) { _ in
        // Debounce region changes to avoid spamming Firestore
        scheduleRegionChanged()
        persistRegion()
      }
      .onChange(of: region.center.longitude) { _ in
        // Debounce region changes to avoid spamming Firestore
        scheduleRegionChanged()
        persistRegion()
      }
      .onChange(of: region.span.latitudeDelta) { _ in persistRegion() }
      .onChange(of: region.span.longitudeDelta) { _ in persistRegion() }
      .onChange(of: location.lastLocation) { loc in
        // Auto-center once when we first receive a GPS fix
        guard !didCenterOnUser, let loc = loc else { return }
        withAnimation { region.center = loc.coordinate }
        didCenterOnUser = true
        // Refresh data for the new center
        if liveUpdates { startLive() } else { loadHere() }
      }
      .frame(minHeight: 350)
      .overlay(alignment: .topTrailing) {
        Button(action: { centerOnMe() }) {
          Image(systemName: "location.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.blue)
            .padding(10)
            .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.trailing, 12)
        .padding(.top, 12)
        .shadow(radius: 2)
      }

      HStack {
        Button("Load tags here") { loadHere() }
        Spacer()
        Button("Drop tag here") { pendingCoordinate = nil; showCreateSheet = true }
      }
      .padding(.horizontal)

      Toggle("Live updates", isOn: $liveUpdates)
        .padding(.horizontal)
        .onChange(of: liveUpdates) { newValue in
          newValue ? startLive() : stopLive()
        }

      if !status.isEmpty {
        Text(status).font(.caption).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Map")
    .padding(.bottom)
    .sheet(isPresented: $showCreateSheet) {
      NavigationView {
        VStack(spacing: 16) {
          Text("Create tag at map center")
            .font(.headline)
      TextField("Enter text", text: $newTagText)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal)
      if let c = pendingCoordinate {
        Text(String(format: "At %.5f, %.5f", c.latitude, c.longitude))
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("At map center")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
          HStack {
            Button("Cancel", role: .cancel) {
              showCreateSheet = false
              newTagText = ""
            }
            Spacer()
            Button("Create") { createHere(text: newTagText) }
              .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .disabled(!canCreateNow)
          }
          .padding(.horizontal)
          if !canCreateNow {
            Text("Please wait a few seconds between creations")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(.top)
        .navigationTitle("New Tag")
        .navigationBarTitleDisplayMode(.inline)
      }
      .maybePresentationDetentsMedium()
    }
    // Fallback actions dialog for iOS 15/16
    .confirmationDialog(dialogTitle, isPresented: $showActionsDialog) {
      if let tag = selectedTag {
        Button("Upvote") { vote(tag: tag, up: true) }
        Button("Downvote") { vote(tag: tag, up: false) }
        if tag.authorId == (Auth.auth().currentUser?.uid ?? "") {
          Button("Delete", role: .destructive) { delete(tag: tag) }
        }
        Button("Cancel", role: .cancel) { }
      }
    }
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
    let d = currentQueryDelta()
    let limit = currentQueryLimit()
    Task {
      do {
        let found = try await service.tagsNear(lat: c.latitude, lng: c.longitude, delta: d, limit: limit)
        await MainActor.run {
          self.tags = found
          if found.count >= limit {
            self.status = "Showing up to \(limit). Zoom in for more."
          } else {
            self.status = "Loaded \(found.count) tags"
          }
        }
      } catch {
        await MainActor.run { self.status = "Load failed: \(error.localizedDescription)" }
      }
    }
  }

  private var canCreateNow: Bool {
    guard let t = lastCreateAt else { return true }
    return Date().timeIntervalSince(t) > 5
  }

  private func createHere(text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { status = "Please enter text"; return }
    guard canCreateNow else { status = "Slow down a bit ✋"; return }
    do {
      let target = pendingCoordinate ?? region.center
      try service.createTextTag(lat: target.latitude, lng: target.longitude, text: trimmed)
      status = "Created at center"
      showCreateSheet = false
      newTagText = ""
      pendingCoordinate = nil
      lastCreateAt = Date()
      loadHere()
    } catch { status = "Create failed: \(error.localizedDescription)" }
  }

  private func startLive() {
    stopLive()
    let c = region.center
    let d = currentQueryDelta()
    let limit = currentQueryLimit()
    listener = service.listenTagsNear(lat: c.latitude, lng: c.longitude, delta: d, limit: limit) { items in
      DispatchQueue.main.async {
        self.tags = items
        if items.count >= limit {
          self.status = "Live: showing up to \(limit). Zoom in for more."
        } else {
          self.status = "Live: \(items.count) tags"
        }
      }
    }
    lastLiveCenter = c
  }

  private func stopLive() {
    listener?.remove()
    listener = nil
  }

  // MARK: - Region change handling
  private func scheduleRegionChanged() {
    debounceWorkItem?.cancel()
    let item = DispatchWorkItem {
      handleRegionChanged()
    }
    debounceWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
  }

  private func handleRegionChanged() {
    let c = region.center
    if liveUpdates {
      // Only restart the live listener if moved significantly
      if let last = lastLiveCenter, distanceMeters(from: last, to: c) < 150 {
        return
      }
      startLive()
    } else {
      loadHere()
    }
  }

  private func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
    let la = CLLocation(latitude: a.latitude, longitude: a.longitude)
    let lb = CLLocation(latitude: b.latitude, longitude: b.longitude)
    return la.distance(from: lb)
  }

  private func persistRegion() {
    storedCenterLat = region.center.latitude
    storedCenterLng = region.center.longitude
    storedSpanLat = region.span.latitudeDelta
    storedSpanLng = region.span.longitudeDelta
  }

  private func currentQueryDelta() -> Double {
    // Use the current zoom to set query area; clamp to sane bounds
    let latDelta = region.span.latitudeDelta
    let lngDelta = region.span.longitudeDelta
    let base = max(latDelta, lngDelta)
    return min(max(base, 0.005), 0.2)
  }

  private func vote(tag: Tag, up: Bool) {
    guard let id = tag.id else { status = "No ID on tag"; return }
    Task {
      do {
        try await service.vote(tagId: id, up: up)
        await MainActor.run {
          status = up ? "Upvoted" : "Downvoted"
          if !liveUpdates { loadHere() }
        }
      } catch {
        await MainActor.run { status = "Vote failed: \(error.localizedDescription)" }
      }
    }
  }

  private func delete(tag: Tag) {
    guard let id = tag.id else { return }
    Task {
      do {
        try await service.delete(tagId: id)
        await MainActor.run {
          status = "Deleted"
          selectedTag = nil
          if !liveUpdates { loadHere() }
        }
      } catch {
        await MainActor.run { status = "Delete failed: \(error.localizedDescription)" }
      }
    }
  }

  private func zoomIn(on coordinate: CLLocationCoordinate2D) {
    var new = region
    new.center = coordinate
    new.span = MKCoordinateSpan(latitudeDelta: max(region.span.latitudeDelta * 0.5, 0.0025),
                                longitudeDelta: max(region.span.longitudeDelta * 0.5, 0.0025))
    withAnimation { region = new }
  }

  // MARK: - Clustering helpers
  private var displayItems: [DisplayItem] {
    let grid = max(region.span.latitudeDelta, region.span.longitudeDelta)
    // If fairly zoomed in, show raw tags
    if grid < 0.01 { return tags.map { DisplayItem(tag: $0) } }

    let cell = grid / 12.0 // number of cells across view
    var buckets: [String: [Tag]] = [:]
    for t in tags {
      let kLat = Int((t.lat / cell).rounded(.toNearestOrEven))
      let kLng = Int((t.lng / cell).rounded(.toNearestOrEven))
      let key = "\(kLat):\(kLng)"
      buckets[key, default: []].append(t)
    }

    var items: [DisplayItem] = []
    for group in buckets.values {
      if group.count == 1, let only = group.first {
        items.append(DisplayItem(tag: only))
      } else {
        let avgLat = group.map { $0.lat }.reduce(0,+) / Double(group.count)
        let avgLng = group.map { $0.lng }.reduce(0,+) / Double(group.count)
        items.append(DisplayItem(coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng), count: group.count))
      }
    }
    return items
  }

  private func currentQueryLimit() -> Int {
    // Scale limit with zoom; fewer results when zoomed out
    let base = max(region.span.latitudeDelta, region.span.longitudeDelta)
    if base > 0.1 { return 60 }
    if base > 0.05 { return 90 }
    if base > 0.02 { return 120 }
    return 160
  }
}

// Conditionally apply presentationDetents on iOS 16+
private extension View {
  @ViewBuilder
  func maybePresentationDetentsMedium() -> some View {
    if #available(iOS 16.0, *) {
      self.presentationDetents([.medium])
    } else {
      self
    }
  }
}

// Lightweight display model for annotations (tag or cluster)
private struct DisplayItem: Identifiable {
  let id: String
  let coordinate: CLLocationCoordinate2D
  let tag: Tag?
  let count: Int

  init(tag: Tag) {
    self.id = tag.id ?? UUID().uuidString
    self.coordinate = CLLocationCoordinate2D(latitude: tag.lat, longitude: tag.lng)
    self.tag = tag
    self.count = 1
  }

  init(coordinate: CLLocationCoordinate2D, count: Int) {
    self.id = "cluster-\(coordinate.latitude)-\(coordinate.longitude)-\(count)"
    self.coordinate = coordinate
    self.tag = nil
    self.count = count
  }
}

// MARK: - Inline callout view
private struct TagCallout: View {
  let tag: Tag
  let isOwner: Bool
  let onUpvote: () -> Void
  let onDownvote: () -> Void
  let onDelete: () -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Text(displayText)
          .font(.subheadline)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
        Spacer(minLength: 8)
        Button(action: onClose) {
          Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
      HStack(spacing: 12) {
        Label("\(tag.upvotes)", systemImage: "hand.thumbsup")
          .labelStyle(.iconOnly)
          .foregroundColor(.green)
        Label("\(tag.downvotes)", systemImage: "hand.thumbsdown")
          .labelStyle(.iconOnly)
          .foregroundColor(.red)
        Spacer()
        Button("Upvote", action: onUpvote)
        Button("Downvote", action: onDownvote)
        if isOwner {
          Button(role: .destructive, action: onDelete) { Text("Delete") }
        }
      }
    }
    .padding(10)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .shadow(radius: 3)
  }

  private var displayText: String {
    if let t = tag.text, !t.isEmpty { return t }
    return String(format: "(%.4f, %.4f)", tag.lat, tag.lng)
  }
}

#Preview {
  NavigationView { TagsMapView() }
}



