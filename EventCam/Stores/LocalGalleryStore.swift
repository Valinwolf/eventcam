//
//  LocalGalleryStore.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import Foundation
import UIKit
import AVFoundation
import Photos
import Combine

@MainActor
final class LocalGalleryStore: ObservableObject {
	@Published private(set) var items: [LocalGalleryItem] = []
	@Published private(set) var currentEventInfo: EventResponse?

	private let rootFolderName = "LocalGallery"
	private let indexFileName = "gallery.json"
	private let defaultServerBaseURL = "https://cam.bigwolfphoto.studio"

	private var uploadQueue: [UUID] = []
	private var isUploading = false

	private(set) var eventCode: String = ""
	private(set) var participantName: String = ""

	private let userDefaults = UserDefaults.standard

	init() {}

	private var documentsURL: URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
	}

	private var rootFolderURL: URL {
		documentsURL.appendingPathComponent(rootFolderName, isDirectory: true)
	}

	private var eventFolderURL: URL {
		let safeEvent = sanitizedEventFolderName(eventCode)
		return rootFolderURL.appendingPathComponent(safeEvent, isDirectory: true)
	}

	private var indexFileURL: URL {
		eventFolderURL.appendingPathComponent(indexFileName)
	}

	private var serverBaseURLString: String {
		let raw = userDefaults.string(forKey: "savedServerBaseURL") ?? defaultServerBaseURL
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

		if trimmed.isEmpty {
			return defaultServerBaseURL
		}

		return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
	}

	private var apiBaseURL: URL {
		guard let url = URL(string: serverBaseURLString + "/api") else {
			return URL(string: defaultServerBaseURL + "/api")!
		}
		return url
	}

	var isEventOpenForCapture: Bool {
		guard let event = currentEventInfo?.event else {
			return true
		}

		let now = Date()

		if let start = event.eventStartDate, now < start {
			return false
		}

		if let end = event.eventEndDate, now > end {
			return false
		}

		return true
	}

	func configureSession(eventCode: String, participantName: String) {
		let normalizedEvent = eventCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
		let normalizedName = participantName.trimmingCharacters(in: .whitespacesAndNewlines)

		let eventChanged = self.eventCode != normalizedEvent
		let nameChanged = self.participantName != normalizedName

		self.eventCode = normalizedEvent
		self.participantName = normalizedName

		if eventChanged {
			uploadQueue.removeAll()
			isUploading = false
			loadIndex()
		} else if items.isEmpty {
			loadIndex()
		}

		if !normalizedEvent.isEmpty, eventChanged || nameChanged || currentEventInfo == nil {
			Task {
				await refreshEventInfo()
			}
		} else if normalizedEvent.isEmpty {
			currentEventInfo = nil
		}
	}

	func refreshEventInfo() async {
		guard !eventCode.isEmpty else {
			currentEventInfo = nil
			return
		}

		do {
			let eventInfo = try await fetchEvent(eventCode: eventCode)
			currentEventInfo = eventInfo
		} catch {
			print("Failed to refresh event info: \(error)")
			currentEventInfo = nil
		}
	}

	private func sanitizedEventFolderName(_ value: String) -> String {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		let cleaned = trimmed.replacingOccurrences(
			of: #"[^A-Za-z0-9_-]+"#,
			with: "_",
			options: .regularExpression
		)
		return cleaned.isEmpty ? "default" : cleaned
	}

	private func ensureFolderExists() {
		if !FileManager.default.fileExists(atPath: rootFolderURL.path) {
			try? FileManager.default.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)
		}

		if !FileManager.default.fileExists(atPath: eventFolderURL.path) {
			try? FileManager.default.createDirectory(at: eventFolderURL, withIntermediateDirectories: true)
		}
	}

	private func loadIndex() {
		guard !eventCode.isEmpty else {
			items = []
			return
		}

		ensureFolderExists()

		guard FileManager.default.fileExists(atPath: indexFileURL.path) else {
			items = []
			return
		}

		do {
			let data = try Data(contentsOf: indexFileURL)
			let decoded = try JSONDecoder().decode([LocalGalleryItem].self, from: data)
			items = decoded.sorted { $0.createdAt > $1.createdAt }
		} catch {
			print("Failed to load gallery index: \(error)")
			items = []
		}
	}

	private func saveIndex() {
		guard !eventCode.isEmpty else { return }

		ensureFolderExists()

		do {
			let data = try JSONEncoder().encode(items)
			try data.write(to: indexFileURL, options: .atomic)
		} catch {
			print("Failed to save gallery index: \(error)")
		}
	}

	func fileURL(for item: LocalGalleryItem) -> URL {
		eventFolderURL.appendingPathComponent(item.fileName)
	}

	func addPhoto(_ image: UIImage, takenAt: Date) {
		guard !eventCode.isEmpty else { return }

		ensureFolderExists()

		guard let data = image.pngData() else { return }

		let fileName = "\(UUID().uuidString).png"
		let item = LocalGalleryItem(
			id: UUID(),
			type: .photo,
			fileName: fileName,
			createdAt: Date(),
			uploadState: .queued,
			uploadedAt: nil,
			storageKey: nil,
			controlToken: nil,
			remoteID: nil,
			guestID: nil,
			takenAt: takenAt,
			displayFileName: nil,
			failureReason: nil
		)

		let destination = fileURL(for: item)

		do {
			try data.write(to: destination, options: .atomic)
			items.insert(item, at: 0)
			saveIndex()
			enqueueUpload(for: item.id)
		} catch {
			print("Failed to save photo locally: \(error)")
		}
	}

	func addVideo(from temporaryURL: URL, takenAt: Date) {
		guard !eventCode.isEmpty else { return }

		ensureFolderExists()

		let fileName = "\(UUID().uuidString).mov"
		let item = LocalGalleryItem(
			id: UUID(),
			type: .video,
			fileName: fileName,
			createdAt: Date(),
			uploadState: .queued,
			uploadedAt: nil,
			storageKey: nil,
			controlToken: nil,
			remoteID: nil,
			guestID: nil,
			takenAt: takenAt,
			displayFileName: nil,
			failureReason: nil
		)

		let destination = fileURL(for: item)

		do {
			if FileManager.default.fileExists(atPath: destination.path) {
				try FileManager.default.removeItem(at: destination)
			}

			try FileManager.default.copyItem(at: temporaryURL, to: destination)
			items.insert(item, at: 0)
			saveIndex()
			enqueueUpload(for: item.id)
		} catch {
			print("Failed to save video locally: \(error)")
		}
	}

	func item(with id: UUID) -> LocalGalleryItem? {
		items.first { $0.id == id }
	}

	func indexOfItem(_ id: UUID) -> Int? {
		items.firstIndex { $0.id == id }
	}

	func deleteItem(_ item: LocalGalleryItem) {
		let remoteID = item.remoteID
		let controlToken = item.controlToken

		let url = fileURL(for: item)
		try? FileManager.default.removeItem(at: url)

		items.removeAll { $0.id == item.id }
		uploadQueue.removeAll { $0 == item.id }
		saveIndex()

		guard let remoteID, let controlToken, !remoteID.isEmpty, !controlToken.isEmpty else {
			return
		}

		Task {
			do {
				try await deleteRemoteMedia(id: remoteID, token: controlToken)
			} catch {
				print("Failed to delete remote media \(remoteID): \(error)")
			}
		}
	}

	func eraseAll() {
		let remoteDeletes = items.compactMap { item -> (String, String)? in
			guard let remoteID = item.remoteID,
				  let token = item.controlToken,
				  !remoteID.isEmpty,
				  !token.isEmpty else {
				return nil
			}

			return (remoteID, token)
		}

		for item in items {
			try? FileManager.default.removeItem(at: fileURL(for: item))
		}

		items.removeAll()
		uploadQueue.removeAll()
		saveIndex()

		Task {
			for (id, token) in remoteDeletes {
				do {
					try await deleteRemoteMedia(id: id, token: token)
				} catch {
					print("Failed to delete remote media \(id): \(error)")
				}
			}
		}
	}

	func enqueueUpload(for id: UUID) {
		guard !uploadQueue.contains(id) else { return }

		if let index = indexOfItem(id) {
			items[index].uploadState = .queued
			items[index].failureReason = nil
			saveIndex()
		}

		uploadQueue.append(id)
		processUploadQueue()
	}

	func retryFailedUploads() {
		let failedIDs = items
			.filter { $0.uploadState == .failed }
			.map(\.id)

		for id in failedIDs {
			enqueueUpload(for: id)
		}
	}

	private func processUploadQueue() {
		guard !isUploading else { return }
		guard !uploadQueue.isEmpty else { return }

		let nextID = uploadQueue.removeFirst()

		guard let index = indexOfItem(nextID) else {
			processUploadQueue()
			return
		}

		isUploading = true
		items[index].uploadState = .uploading
		items[index].failureReason = nil
		saveIndex()

		let item = items[index]

		Task {
			do {
				let result = try await upload(item: item)

				await MainActor.run {
					if let freshIndex = self.indexOfItem(item.id) {
						self.items[freshIndex].uploadState = .uploaded
						self.items[freshIndex].uploadedAt = Date()
						self.items[freshIndex].storageKey = result.storageKey
						self.items[freshIndex].controlToken = result.controlToken
						self.items[freshIndex].remoteID = result.remoteID
						self.items[freshIndex].guestID = result.guestID
						self.items[freshIndex].displayFileName = result.displayFileName
						self.items[freshIndex].failureReason = nil
						self.saveIndex()
					}

					self.isUploading = false
					self.processUploadQueue()
				}
			} catch {
				await MainActor.run {
					if let freshIndex = self.indexOfItem(item.id) {
						self.items[freshIndex].uploadState = .failed
						self.items[freshIndex].failureReason = error.localizedDescription
						self.saveIndex()
					}

					print("Upload failed for \(item.id): \(error)")
					self.isUploading = false
					self.processUploadQueue()
				}
			}
		}
	}

	struct UploadResult {
		let remoteID: String
		let guestID: String
		let storageKey: String?
		let controlToken: String?
		let displayFileName: String?
	}

	private func upload(item: LocalGalleryItem) async throws -> UploadResult {
		guard !eventCode.isEmpty, !participantName.isEmpty else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Missing event or participant name"]
			)
		}

		let eventInfo = try await fetchEvent(eventCode: eventCode)
		currentEventInfo = eventInfo

		guard eventInfo.exists else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 2,
				userInfo: [NSLocalizedDescriptionKey: "Event does not exist"]
			)
		}

		let guest = try await ensureGuest()

		let mimeType: String

		switch item.type {
		case .photo:
			mimeType = "image/png"
		case .video:
			mimeType = "video/quicktime"
		}

		let createResponse = try await createMedia(
			eventCode: eventCode,
			guestID: guest.id,
			mime: mimeType
		)

		print("=== Upload Instruction Debug ===")
		print("URL:", createResponse.upload.url)
		print("Method:", createResponse.upload.method)
		print("Headers:", createResponse.upload.headers ?? [:])
		print("================================")

		let sourceURL = fileURL(for: item)
		let fileData = try Data(contentsOf: sourceURL)

		try await uploadDirect(
			data: fileData,
			instruction: createResponse.upload,
			mimeType: mimeType
		)

		do {
			try await finalizeMedia(id: createResponse.id, status: "uploaded", reason: nil)
		} catch {
			try? await finalizeMedia(id: createResponse.id, status: "failed", reason: error.localizedDescription)
			throw error
		}

		return UploadResult(
			remoteID: createResponse.id,
			guestID: guest.id,
			storageKey: createResponse.storageKey,
			controlToken: createResponse.controlToken,
			displayFileName: createResponse.file
		)
	}

	private func ensureGuest() async throws -> GuestResponse {
		let key = guestStorageKey(for: participantName)

		if let cachedID = userDefaults.string(forKey: key), !cachedID.isEmpty {
			return GuestResponse(id: cachedID, name: participantName)
		}

		var request = URLRequest(url: apiBaseURL.appendingPathComponent("guest"))
		request.httpMethod = "PUT"
		request.timeoutInterval = 60
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let payload = GuestPutRequest(name: participantName)
		request.httpBody = try JSONEncoder().encode(payload)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTP(response: response, data: data)

		let guest = try JSONDecoder().decode(GuestResponse.self, from: data)
		userDefaults.set(guest.id, forKey: key)

		return guest
	}

	private func fetchEvent(eventCode: String) async throws -> EventResponse {
		var components = URLComponents(url: apiBaseURL.appendingPathComponent("event"), resolvingAgainstBaseURL: false)
		components?.queryItems = [
			URLQueryItem(name: "id", value: eventCode)
		]

		guard let url = components?.url else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 3,
				userInfo: [NSLocalizedDescriptionKey: "Invalid event URL"]
			)
		}

		let (data, response) = try await URLSession.shared.data(from: url)
		try validateHTTP(response: response, data: data)

		return try JSONDecoder().decode(EventResponse.self, from: data)
	}

	private func createMedia(eventCode: String, guestID: String, mime: String) async throws -> MediaCreateResponse {
		var request = URLRequest(url: apiBaseURL.appendingPathComponent("media"))
		request.httpMethod = "PUT"
		request.timeoutInterval = 60
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let payload = MediaCreateRequest(
			eventCode: eventCode,
			guestID: guestID,
			mime: mime
		)

		request.httpBody = try JSONEncoder().encode(payload)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTP(response: response, data: data)

		return try JSONDecoder().decode(MediaCreateResponse.self, from: data)
	}

	private func uploadDirect(data: Data, instruction: UploadInstruction, mimeType: String) async throws {
		guard let url = URL(string: instruction.url) else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 4,
				userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"]
			)
		}

		var request = URLRequest(url: url)
		request.httpMethod = instruction.method
		request.timeoutInterval = 1800

		if let headers = instruction.headers {
			for (key, value) in headers {
				request.setValue(value, forHTTPHeaderField: key)
			}
		}

		if request.value(forHTTPHeaderField: "Content-Type") == nil {
			request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
		}

		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 1800
		config.timeoutIntervalForResource = 10800

		let session = URLSession(configuration: config)
		let (responseData, response) = try await session.upload(for: request, from: data)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 5,
				userInfo: [NSLocalizedDescriptionKey: "Invalid upload response"]
			)
		}

		if !(200...299).contains(httpResponse.statusCode) {
			let responseText = String(data: responseData, encoding: .utf8) ?? "No response body"
			print("Direct upload failed body:", responseText)

			throw NSError(
				domain: "LocalGalleryStore",
				code: httpResponse.statusCode,
				userInfo: [NSLocalizedDescriptionKey: "Direct upload failed with status \(httpResponse.statusCode)"]
			)
		}
	}

	private func finalizeMedia(id: String, status: String, reason: String?) async throws {
		var request = URLRequest(url: apiBaseURL.appendingPathComponent("media"))
		request.httpMethod = "PATCH"
		request.timeoutInterval = 60
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let payload = MediaPatchRequest(id: id, status: status, reason: reason)
		request.httpBody = try JSONEncoder().encode(payload)

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTP(response: response, data: data)
	}

	private func deleteRemoteMedia(id: String, token: String) async throws {
		var components = URLComponents(url: apiBaseURL.appendingPathComponent("media"), resolvingAgainstBaseURL: false)
		components?.queryItems = [
			URLQueryItem(name: "id", value: id),
			URLQueryItem(name: "token", value: token)
		]

		guard let url = components?.url else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 6,
				userInfo: [NSLocalizedDescriptionKey: "Invalid delete URL"]
			)
		}

		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		request.timeoutInterval = 60

		let (data, response) = try await URLSession.shared.data(for: request)
		try validateHTTP(response: response, data: data)
	}

	private func validateHTTP(response: URLResponse, data: Data) throws {
		guard let httpResponse = response as? HTTPURLResponse else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 7,
				userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
			)
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
			throw NSError(
				domain: "LocalGalleryStore",
				code: httpResponse.statusCode,
				userInfo: [NSLocalizedDescriptionKey: responseString]
			)
		}
	}

	private func guestStorageKey(for name: String) -> String {
		let normalized = name
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()

		return "eventcam.guest.\(normalized)"
	}

	func saveItemToPhotos(_ item: LocalGalleryItem, completion: @escaping (Bool) -> Void) {
		let fileURL = fileURL(for: item)

		PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
			guard status == .authorized || status == .limited else {
				DispatchQueue.main.async { completion(false) }
				return
			}

			PHPhotoLibrary.shared().performChanges {
				switch item.type {
				case .photo:
					if let image = UIImage(contentsOfFile: fileURL.path) {
						PHAssetChangeRequest.creationRequestForAsset(from: image)
					}
				case .video:
					PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
				}
			} completionHandler: { success, _ in
				DispatchQueue.main.async {
					completion(success)
				}
			}
		}
	}

	func saveAllToPhotos(completion: @escaping (Bool) -> Void) {
		let snapshots = items.map { item in
			(item: item, url: fileURL(for: item))
		}

		PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
			guard status == .authorized || status == .limited else {
				DispatchQueue.main.async { completion(false) }
				return
			}

			PHPhotoLibrary.shared().performChanges {
				for snapshot in snapshots {
					switch snapshot.item.type {
					case .photo:
						if let image = UIImage(contentsOfFile: snapshot.url.path) {
							PHAssetChangeRequest.creationRequestForAsset(from: image)
						}
					case .video:
						PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: snapshot.url)
					}
				}
			} completionHandler: { success, _ in
				DispatchQueue.main.async {
					completion(success)
				}
			}
		}
	}

	func thumbnailImage(for item: LocalGalleryItem) -> UIImage? {
		switch item.type {
		case .photo:
			return UIImage(contentsOfFile: fileURL(for: item).path)
		case .video:
			return nil
		}
	}

	func loadThumbnail(for item: LocalGalleryItem) async -> UIImage? {
		switch item.type {
		case .photo:
			return UIImage(contentsOfFile: fileURL(for: item).path)
		case .video:
			return await videoThumbnail(for: fileURL(for: item))
		}
	}

	private func videoThumbnail(for url: URL) async -> UIImage? {
		let asset = AVURLAsset(url: url)
		let generator = AVAssetImageGenerator(asset: asset)
		generator.appliesPreferredTrackTransform = true

		return await withCheckedContinuation { continuation in
			generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
				if let cgImage {
					continuation.resume(returning: UIImage(cgImage: cgImage))
				} else {
					if let error {
						print("Failed to generate video thumbnail: \(error)")
					}
					continuation.resume(returning: nil)
				}
			}
		}
	}
}
