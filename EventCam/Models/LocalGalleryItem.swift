//
//  LocalGalleryItem.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import Foundation

struct LocalGalleryItem: Identifiable, Codable, Equatable {
	enum MediaType: String, Codable {
		case photo
		case video
	}

	enum UploadState: String, Codable {
		case pending
		case queued
		case uploading
		case uploaded
		case failed
	}

	let id: UUID
	let type: MediaType
	let fileName: String
	let createdAt: Date

	var uploadState: UploadState
	var uploadedAt: Date?
	var storageKey: String?
	var controlToken: String?

	// New API-backed metadata
	var remoteID: String?
	var guestID: String?
	var takenAt: Date?
	var displayFileName: String?

	init(
		id: UUID,
		type: MediaType,
		fileName: String,
		createdAt: Date,
		uploadState: UploadState,
		uploadedAt: Date?,
		storageKey: String?,
		controlToken: String?,
		remoteID: String? = nil,
		guestID: String? = nil,
		takenAt: Date? = nil,
		displayFileName: String? = nil
	) {
		self.id = id
		self.type = type
		self.fileName = fileName
		self.createdAt = createdAt
		self.uploadState = uploadState
		self.uploadedAt = uploadedAt
		self.storageKey = storageKey
		self.controlToken = controlToken
		self.remoteID = remoteID
		self.guestID = guestID
		self.takenAt = takenAt
		self.displayFileName = displayFileName
	}
}
