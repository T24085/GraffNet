import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseAuth

final class TagService {
  private let db = Firestore.firestore()

  func createTextTag(lat: Double, lng: Double, text: String) throws {
    let uid = Auth.auth().currentUser?.uid ?? "anon"
    let tag = Tag(
      authorId: uid,
      lat: lat,
      lng: lng,
      type: "text",
      text: text,
      strokes: nil,
      thumb: nil,
      assetUrl: nil,
      upvotes: 0,
      downvotes: 0,
      createdAt: Date()
    )
    _ = try db.collection("tags").addDocument(from: tag)
  }

  // Simple bounding box query: range on lat in Firestore, filter lng in-memory
  func tagsNear(lat: Double, lng: Double, delta: Double = 0.01, limit: Int = 100) async throws -> [Tag] {
    let snapshot = try await db.collection("tags")
      .whereField("lat", isGreaterThan: lat - delta)
      .whereField("lat", isLessThan:  lat + delta)
      .limit(to: limit)
      .getDocuments()

    let docs: [Tag] = snapshot.documents.compactMap { try? $0.data(as: Tag.self) }
    let lowerLng = lng - delta, upperLng = lng + delta
    return docs.filter { $0.lng >= lowerLng && $0.lng <= upperLng }
  }

  func vote(tagId: String, up: Bool) async throws {
    try await db.collection("tags").document(tagId).updateData([
      up ? "upvotes" : "downvotes": FieldValue.increment(Int64(1))
    ])
  }
}

