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

	private let rootFolderName = "LocalGallery"
	private let indexFileName = "gallery.json"

	private var uploadQueue: [UUID] = []
	private var isUploading = false

	private(set) var eventCode: String = ""
	private(set) var participantName: String = ""

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

	func configureSession(eventCode: String, participantName: String) {
		let normalizedEvent = eventCode.trimmingCharacters(in: .whitespacesAndNewlines)
		let eventChanged = self.eventCode != normalizedEvent

		self.eventCode = normalizedEvent
		self.participantName = participantName

		if eventChanged {
			uploadQueue.removeAll()
			isUploading = false
			loadIndex()
		} else if items.isEmpty {
			loadIndex()
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

	func addPhoto(_ image: UIImage) {
		guard !eventCode.isEmpty else { return }

		ensureFolderExists()

		guard let data = image.pngData() else { return }

		let item = LocalGalleryItem(
			id: UUID(),
			type: .photo,
			fileName: "\(UUID().uuidString).png",
			createdAt: Date(),
			uploadState: .queued,
			uploadedAt: nil,
			storageKey: nil,
			controlToken: nil
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

	func addVideo(from temporaryURL: URL) {
		guard !eventCode.isEmpty else { return }

		ensureFolderExists()

		let item = LocalGalleryItem(
			id: UUID(),
			type: .video,
			fileName: "\(UUID().uuidString).mov",
			createdAt: Date(),
			uploadState: .queued,
			uploadedAt: nil,
			storageKey: nil,
			controlToken: nil
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
		let url = fileURL(for: item)
		try? FileManager.default.removeItem(at: url)

		items.removeAll { $0.id == item.id }
		uploadQueue.removeAll { $0 == item.id }
		saveIndex()
	}

	func eraseAll() {
		for item in items {
			try? FileManager.default.removeItem(at: fileURL(for: item))
		}

		items.removeAll()
		uploadQueue.removeAll()
		saveIndex()
	}

	func enqueueUpload(for id: UUID) {
		guard !uploadQueue.contains(id) else { return }

		if let index = indexOfItem(id) {
			items[index].uploadState = .queued
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
						self.saveIndex()
					}

					self.isUploading = false
					self.processUploadQueue()
				}
			} catch {
				await MainActor.run {
					if let freshIndex = self.indexOfItem(item.id) {
						self.items[freshIndex].uploadState = .failed
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
		let storageKey: String?
		let controlToken: String?
	}

	private func upload(item: LocalGalleryItem) async throws -> UploadResult {
		guard !eventCode.isEmpty, !participantName.isEmpty else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Missing event or participant name"]
			)
		}

		guard let url = URL(string: "https://cam.bigwolfphoto.studio/api/upload") else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 2,
				userInfo: [NSLocalizedDescriptionKey: "Invalid upload URL"]
			)
		}

		let sourceURL = fileURL(for: item)
		let fileData = try Data(contentsOf: sourceURL)
		let boundary = UUID().uuidString

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.timeoutInterval = 300
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		let mimeType: String
		switch item.type {
		case .photo:
			mimeType = "image/png"
		case .video:
			mimeType = "video/quicktime"
		}

		var body = Data()

		body.append("--\(boundary)\r\n".data(using: .utf8)!)
		body.append("Content-Disposition: form-data; name=\"id\"\r\n\r\n".data(using: .utf8)!)
		body.append("\(eventCode)\r\n".data(using: .utf8)!)

		body.append("--\(boundary)\r\n".data(using: .utf8)!)
		body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
		body.append("\(participantName)\r\n".data(using: .utf8)!)

		body.append("--\(boundary)\r\n".data(using: .utf8)!)
		body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(item.fileName)\"\r\n".data(using: .utf8)!)
		body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
		body.append(fileData)
		body.append("\r\n".data(using: .utf8)!)
		body.append("--\(boundary)--\r\n".data(using: .utf8)!)

		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 300
		config.timeoutIntervalForResource = 600

		let session = URLSession(configuration: config)
		let (responseData, response) = try await session.upload(for: request, from: body)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw NSError(
				domain: "LocalGalleryStore",
				code: 3,
				userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
			)
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let responseString = String(data: responseData, encoding: .utf8) ?? "Unknown error"
			throw NSError(
				domain: "LocalGalleryStore",
				code: httpResponse.statusCode,
				userInfo: [NSLocalizedDescriptionKey: responseString]
			)
		}

		let payload = try JSONDecoder().decode(UploadResponse.self, from: responseData)

		return UploadResult(
			storageKey: payload.storage_key,
			controlToken: payload.control_token
		)
	}

	func saveItemToPhotos(_ item: LocalGalleryItem, completion: @escaping (Bool) -> Void) {
		PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
			guard status == .authorized || status == .limited else {
				DispatchQueue.main.async { completion(false) }
				return
			}

			let fileURL = self.fileURL(for: item)

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
		PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
			guard status == .authorized || status == .limited else {
				DispatchQueue.main.async { completion(false) }
				return
			}

			PHPhotoLibrary.shared().performChanges {
				for item in self.items {
					let url = self.fileURL(for: item)

					switch item.type {
					case .photo:
						if let image = UIImage(contentsOfFile: url.path) {
							PHAssetChangeRequest.creationRequestForAsset(from: image)
						}
					case .video:
						PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
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
			return videoThumbnail(for: fileURL(for: item))
		}
	}

	private func videoThumbnail(for url: URL) -> UIImage? {
		let asset = AVAsset(url: url)
		let generator = AVAssetImageGenerator(asset: asset)
		generator.appliesPreferredTrackTransform = true

		do {
			let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
			return UIImage(cgImage: cgImage)
		} catch {
			return nil
		}
	}
}

private struct UploadResponse: Decodable {
	let storage_key: String?
	let control_token: String?
}
