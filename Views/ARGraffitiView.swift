import SwiftUI
import ARKit
import SceneKit
import UIKit


struct ARGraffitiView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selectedColorIndex = 0
  @State private var brushSize: CGFloat = 0.02
  @State private var clearTrigger = 0

  private let palette = GraffitiPalette.default

  static var isSupported: Bool { ARGraffitiScene.isSupported }

  var body: some View {
    Group {
      if ARGraffitiScene.isSupported {
        ZStack {
          ARGraffitiScene(
            selectedColorIndex: $selectedColorIndex,
            brushSize: $brushSize,
            clearTrigger: $clearTrigger,
            palette: palette
          )
          .ignoresSafeArea()

          VStack {
            topBar
            Spacer()
            controls
          }
        }
      } else {
        unsupportedView
      }
    }
  }

  private var topBar: some View {
    HStack(spacing: 16) {
      Button(action: { dismiss() }) {
        Label("Close", systemImage: "xmark")
          .labelStyle(.iconOnly)
          .padding(10)
          .background(.ultraThinMaterial, in: Circle())
      }
      .accessibilityLabel("Close augmented reality painter")

      Spacer()

      Button(role: .destructive, action: { clearTrigger += 1 }) {
        HStack(spacing: 6) {
          Image(systemName: "trash")
          Text("Clear")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
      }
      .accessibilityLabel("Clear graffiti strokes")
    }
    .padding(.horizontal)
    .padding(.top, 24)
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Choose a color and drag on the world to paint your tag.")
        .font(.callout)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(Array(palette.enumerated()), id: \.offset) { index, entry in
            Button(action: { selectedColorIndex = index }) {
              Circle()
                .fill(entry.color)
                .frame(width: 36, height: 36)
                .overlay(
                  Circle().stroke(Color.white, lineWidth: selectedColorIndex == index ? 3 : 1)
                )
                .shadow(radius: selectedColorIndex == index ? 6 : 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(entry.name) paint")
          }
        }
        .padding(.vertical, 4)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Brush size")
          .font(.subheadline)
          .fontWeight(.semibold)
        Slider(
          value: Binding(
            get: { Double(brushSize) },
            set: { brushSize = CGFloat($0) }
          ),
          in: 0.008...0.04
        )
        Text(String(format: "%.1f cm", brushSize * 100))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text("Move your device to detect a surface, then press and drag to spray paint in space.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
    }
    .padding(18)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .padding(.horizontal)
    .padding(.bottom, 28)
  }

  private var unsupportedView: some View {
    VStack(spacing: 16) {
      Image(systemName: "arkit")
        .font(.system(size: 54))
        .foregroundColor(.secondary)
      Text("AR drawing requires a device that supports ARKit.")
        .font(.headline)
        .multilineTextAlignment(.center)
      Button("Close") { dismiss() }
        .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}

private struct ARGraffitiScene: UIViewRepresentable {
  @Binding var selectedColorIndex: Int
  @Binding var brushSize: CGFloat
  @Binding var clearTrigger: Int
  let palette: [GraffitiPaletteColor]

  static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> GraffitiARView {
    let view = GraffitiARView(frame: .zero)
    view.configureSession()
    view.currentColor = palette[safe: selectedColorIndex]?.uiColor ?? palette.first?.uiColor ?? .white
    view.brushSize = brushSize
    context.coordinator.attachCoachingOverlay(to: view)
    return view
  }

  func updateUIView(_ view: GraffitiARView, context: Context) {
    let currentColor = palette[safe: selectedColorIndex]?.uiColor ?? palette.first?.uiColor ?? .white
    view.currentColor = currentColor
    view.brushSize = brushSize

    if clearTrigger != context.coordinator.lastClearTrigger {
      view.clearPaint()
      context.coordinator.lastClearTrigger = clearTrigger
    }
  }

  static func dismantleUIView(_ uiView: GraffitiARView, coordinator: Coordinator) {
    uiView.session.pause()
  }

  class Coordinator: NSObject, ARCoachingOverlayViewDelegate {
    let parent: ARGraffitiScene
    var lastClearTrigger = 0

    init(_ parent: ARGraffitiScene) {
      self.parent = parent
    }

    func attachCoachingOverlay(to view: GraffitiARView) {
      guard ARGraffitiScene.isSupported else { return }
      let overlay = ARCoachingOverlayView()
      overlay.session = view.session
      overlay.delegate = self
      if #available(iOS 14.0, *) {
        overlay.goal = .anyPlane
      } else {
        overlay.goal = .tracking
      }
      overlay.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(overlay)
      NSLayoutConstraint.activate([
        overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        overlay.topAnchor.constraint(equalTo: view.topAnchor),
        overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
      ])
    }
  }
}

private final class GraffitiARView: ARSCNView {
  var currentColor: UIColor = .systemPink
  var brushSize: CGFloat = 0.02

  private let paintContainer = SCNNode()
  private var lastDrawPosition: SCNVector3?

  override init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    automaticallyUpdatesLighting = true
    scene = SCNScene()
    scene.rootNode.addChildNode(paintContainer)
    showsStatistics = false
  }

  func configureSession() {
    guard ARWorldTrackingConfiguration.isSupported else { return }
    let configuration = ARWorldTrackingConfiguration()
    configuration.planeDetection = [.horizontal, .vertical]
    configuration.environmentTexturing = .automatic
    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
      configuration.sceneReconstruction = .mesh
    }
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
  }

  func clearPaint() {
    paintContainer.childNodes.forEach { $0.removeFromParentNode() }
    lastDrawPosition = nil
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    lastDrawPosition = nil
    guard let location = touches.first?.location(in: self) else { return }
    addPaint(at: location)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    guard let location = touches.first?.location(in: self) else { return }
    addPaint(at: location)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    lastDrawPosition = nil
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesCancelled(touches, with: event)
    lastDrawPosition = nil
  }

  private func addPaint(at screenPoint: CGPoint) {
    guard let position = worldPosition(for: screenPoint) else { return }

    if let last = lastDrawPosition {
      let delta = position - last
      if delta.length() < Float(brushSize) * 0.3 { return }
    }

    let sphere = SCNSphere(radius: brushSize / 2)
    let material = SCNMaterial()
    material.diffuse.contents = currentColor
    material.lightingModel = .physicallyBased
    material.isDoubleSided = false
    sphere.firstMaterial = material

    let node = SCNNode(geometry: sphere)
    node.position = position
    node.name = "paint"
    paintContainer.addChildNode(node)

    lastDrawPosition = position
  }

  private func worldPosition(for screenPoint: CGPoint) -> SCNVector3? {
    if #available(iOS 14.0, *) {
      let targets: [ARRaycastQuery.Target] = [.existingPlaneGeometry, .estimatedPlane]
      for target in targets {
        if let query = raycastQuery(from: screenPoint, allowing: target, alignment: .any) {
          let results = session.raycast(query)
          if let result = results.first {
            let transform = result.worldTransform
            return SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
          }
        }
      }
    } else {
      let results = hitTest(screenPoint, types: [
        .existingPlaneUsingGeometry,
        .existingPlaneUsingExtent,
        .estimatedHorizontalPlane,
        .estimatedVerticalPlane,
        .featurePoint
      ])
      if let result = results.first {
        let transform = result.worldTransform
        return SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
      }
    }

    return nil
  }
}

private struct GraffitiPaletteColor: Identifiable {
  let id = UUID()
  let name: String
  let color: Color
  let uiColor: UIColor
}

private enum GraffitiPalette {
  static let `default`: [GraffitiPaletteColor] = [
    GraffitiPaletteColor(
      name: "Electric Blue",
      color: Color(red: 0.30, green: 0.56, blue: 0.99),
      uiColor: UIColor(red: 0.30, green: 0.56, blue: 0.99, alpha: 1.0)
    ),
    GraffitiPaletteColor(
      name: "Sunset Orange",
      color: Color(red: 0.96, green: 0.38, blue: 0.24),
      uiColor: UIColor(red: 0.96, green: 0.38, blue: 0.24, alpha: 1.0)
    ),
    GraffitiPaletteColor(
      name: "Neon Green",
      color: Color(red: 0.15, green: 0.80, blue: 0.44),
      uiColor: UIColor(red: 0.15, green: 0.80, blue: 0.44, alpha: 1.0)
    ),
    GraffitiPaletteColor(
      name: "Vivid Purple",
      color: Color(red: 0.60, green: 0.34, blue: 0.94),
      uiColor: UIColor(red: 0.60, green: 0.34, blue: 0.94, alpha: 1.0)
    ),
    GraffitiPaletteColor(
      name: "Hot Pink",
      color: Color(red: 0.97, green: 0.22, blue: 0.55),
      uiColor: UIColor(red: 0.97, green: 0.22, blue: 0.55, alpha: 1.0)
    ),
    GraffitiPaletteColor(
      name: "Bright Yellow",
      color: Color(red: 0.99, green: 0.82, blue: 0.25),
      uiColor: UIColor(red: 0.99, green: 0.82, blue: 0.25, alpha: 1.0)
    )
  ]
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

private extension SCNVector3 {
  static func -(lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
  }

  func length() -> Float {
    sqrtf(x * x + y * y + z * z)
  }
}

#Preview {
  ARGraffitiView()
}
