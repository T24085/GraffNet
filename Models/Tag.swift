import Foundation
import CoreGraphics
import FirebaseFirestoreSwift

// Optional paint stroke model if you later want vector graffiti
public struct CGPointCodable: Codable { public var x: Double; public var y: Double }

public struct Stroke: Codable {
  public var points: [CGPointCodable]
  public var colorHex: String
  public var width: Double
}

public struct Tag: Codable, Identifiable {
  @DocumentID public var id: String?
  public var authorId: String
  public var lat: Double
  public var lng: Double
  public var type: String            // "text" | "strokes" | "external"
  public var text: String?
  public var strokes: [Stroke]?
  public var thumb: Data?
  public var assetUrl: String?
  public var upvotes: Int
  public var downvotes: Int
  public var createdAt: Date
}

