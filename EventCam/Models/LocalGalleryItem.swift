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
}
