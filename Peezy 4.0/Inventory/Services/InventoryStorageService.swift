import Foundation
import FirebaseStorage
import FirebaseFirestore

@Observable
final class InventoryStorageService {
    var uploadProgress: Double = 0.0
    var isUploading = false

    /// Upload frames to Storage, create Firestore session doc, return session
    func uploadFrames(
        _ frames: [ExtractedFrame],
        userId: String,
        roomName: String
    ) async throws -> InventoryScanSession {
        guard !frames.isEmpty else {
            throw InventoryStorageError.noFramesProvided
        }

        isUploading = true
        uploadProgress = 0.0
        defer { isUploading = false }

        let sessionId = UUID().uuidString
        var session = InventoryScanSession.newSession(userId: userId, roomName: roomName)
        session.id = sessionId

        let db = Firestore.firestore()
        let sessionRef = db.collection("users").document(userId)
            .collection("inventorySessions").document(sessionId)

        // Create Firestore session document with uploading status
        do {
            try await sessionRef.setData([
                "id": sessionId,
                "userId": userId,
                "roomName": roomName,
                "status": InventoryScanSession.ScanStatus.uploading.rawValue,
                "frameCount": 0,
                "items": [] as [[String: Any]],
                "createdAt": FieldValue.serverTimestamp()
            ])
        } catch {
            throw InventoryStorageError.firestoreWriteFailed(error.localizedDescription)
        }

        // Upload each frame to Firebase Storage
        let storage = Storage.storage()
        let totalCount = frames.count
        var completedCount = 0
        var uploadedCount = 0

        #if DEBUG
        print("[InventoryUpload] Starting upload of \(totalCount) frames for session \(sessionId)")
        #endif

        for (index, frame) in frames.enumerated() {
            guard let jpegData = frame.image.jpegData(compressionQuality: 0.7) else {
                #if DEBUG
                print("[InventoryUpload] frame[\(index)] failed JPEG conversion")
                #endif
                completedCount += 1
                uploadProgress = Double(completedCount) / Double(totalCount)
                continue
            }

            let storagePath = "inventory/\(userId)/\(sessionId)/frame_\(index).jpg"
            let storageRef = storage.reference().child(storagePath)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            #if DEBUG
            print("[InventoryUpload] frame[\(index)] uploading \(jpegData.count) bytes to \(storagePath)")
            #endif

            do {
                _ = try await storageRef.putDataAsync(jpegData, metadata: metadata)
                uploadedCount += 1
                #if DEBUG
                print("[InventoryUpload] frame[\(index)] uploaded successfully")
                #endif
            } catch {
                #if DEBUG
                print("[InventoryUpload] frame[\(index)] upload FAILED: \(error.localizedDescription)")
                #endif
            }

            completedCount += 1
            uploadProgress = Double(completedCount) / Double(totalCount)
        }

        #if DEBUG
        print("[InventoryUpload] Upload complete: \(uploadedCount)/\(totalCount) frames succeeded")
        #endif

        // Update Firestore document with frame count and processing status
        session.frameCount = uploadedCount
        session.status = .processing

        do {
            try await sessionRef.updateData([
                "frameCount": uploadedCount,
                "status": InventoryScanSession.ScanStatus.processing.rawValue
            ])
        } catch {
            throw InventoryStorageError.firestoreWriteFailed(error.localizedDescription)
        }

        return session
    }

    /// Observe a session document for status changes (processing -> complete)
    func observeSession(
        userId: String,
        sessionId: String,
        onChange: @escaping (InventoryScanSession) -> Void
    ) -> ListenerRegistration {
        let db = Firestore.firestore()
        let sessionRef = db.collection("users").document(userId)
            .collection("inventorySessions").document(sessionId)

        return sessionRef.addSnapshotListener { snapshot, error in
            guard let snapshot = snapshot, snapshot.exists,
                  let data = snapshot.data() else {
                return
            }

            // Decode session from Firestore data
            let status = InventoryScanSession.ScanStatus(
                rawValue: data["status"] as? String ?? "error"
            ) ?? .error

            let itemsData = data["items"] as? [[String: Any]] ?? []
            let items: [InventoryItem] = itemsData.compactMap { itemDict in
                guard let name = itemDict["name"] as? String else { return nil }
                return InventoryItem(
                    id: itemDict["id"] as? String ?? UUID().uuidString,
                    name: name,
                    category: itemDict["category"] as? String ?? "other",
                    quantity: (itemDict["quantity"] as? NSNumber)?.intValue ?? 1,
                    sizeEstimate: itemDict["sizeEstimate"] as? String ?? "medium",
                    isFragile: itemDict["isFragile"] as? Bool ?? false,
                    isHighValue: itemDict["isHighValue"] as? Bool ?? false,
                    confidence: itemDict["confidence"] as? Double ?? 0.5,
                    roomName: itemDict["roomName"] as? String ?? "",
                    shouldMove: itemDict["shouldMove"] as? Bool ?? true,
                    notes: itemDict["notes"] as? String ?? ""
                )
            }

            let createdAt: Date
            if let timestamp = data["createdAt"] as? Timestamp {
                createdAt = timestamp.dateValue()
            } else {
                createdAt = Date()
            }

            let completedAt: Date?
            if let timestamp = data["completedAt"] as? Timestamp {
                completedAt = timestamp.dateValue()
            } else {
                completedAt = nil
            }

            let session = InventoryScanSession(
                id: data["id"] as? String ?? sessionId,
                userId: data["userId"] as? String ?? userId,
                roomName: data["roomName"] as? String ?? "",
                status: status,
                frameCount: (data["frameCount"] as? NSNumber)?.intValue ?? 0,
                items: items,
                errorMessage: data["errorMessage"] as? String,
                createdAt: createdAt,
                completedAt: completedAt
            )

            onChange(session)
        }
    }
}

enum InventoryStorageError: LocalizedError {
    case noFramesProvided
    case firestoreWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFramesProvided:
            return "No frames provided for upload"
        case .firestoreWriteFailed(let message):
            return "Firestore write failed: \(message)"
        }
    }
}
