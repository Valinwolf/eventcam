//
//  APIModels.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/28/26.
//

import Foundation

struct EventResponse: Decodable {
	let success: Bool?
	let eventCode: String?
	let exists: Bool
	let event: EventPayload?

	enum CodingKeys: String, CodingKey {
		case success
		case eventCode = "event_code"
		case exists
		case event
	}
}

struct EventPayload: Decodable {
	let eventCode: String?
	let eventName: String?
	let eventStart: String?
	let eventEnd: String?
	let galleryReleased: Bool?
	let hostNames: [String]?
	let allowPhotos: Bool?
	let allowVideos: Bool?
	let maxPhotos: Int?
	let maxGuests: Int?

	enum CodingKeys: String, CodingKey {
		case eventCode = "event_code"
		case eventName = "event_name"
		case eventStart = "event_start"
		case eventEnd = "event_end"
		case galleryReleased = "gallery_released"
		case hostNames = "host_names"
		case allowPhotos = "allow_photos"
		case allowVideos = "allow_videos"
		case maxPhotos = "max_photos"
		case maxGuests = "max_guests"
	}

	var eventStartDate: Date? {
		parseDate(eventStart)
	}

	var eventEndDate: Date? {
		parseDate(eventEnd)
	}

	private func parseDate(_ value: String?) -> Date? {
		guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return nil
		}

		if let date = Self.iso8601WithFractional.date(from: value) {
			return date
		}

		if let date = Self.iso8601.date(from: value) {
			return date
		}

		if let date = Self.postgresDateFormatter.date(from: value) {
			return date
		}

		return nil
	}

	private static let iso8601: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime]
		return formatter
	}()

	private static let iso8601WithFractional: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	private static let postgresDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
		return formatter
	}()
}

struct GuestPutRequest: Encodable {
	let name: String
}

struct GuestResponse: Decodable {
	let id: String
	let name: String
}

struct MediaCreateRequest: Encodable {
	let eventCode: String
	let guestID: String
	let mime: String

	enum CodingKeys: String, CodingKey {
		case eventCode = "event_code"
		case guestID = "guest_id"
		case mime
	}
}

struct MediaCreateResponse: Decodable {
	let id: String
	let upload: UploadInstruction
	let controlToken: String?
	let storageKey: String?
	let file: String?

	enum CodingKeys: String, CodingKey {
		case id
		case upload
		case controlToken = "control_token"
		case storageKey = "storage_key"
		case file
	}
}

struct UploadInstruction: Decodable {
	let method: String
	let url: String
	let headers: [String: String]?
	let expiresAt: String?

	enum CodingKeys: String, CodingKey {
		case method
		case url
		case headers
		case expiresAt = "expires_at"
	}
}

struct MediaPatchRequest: Encodable {
	let id: String
	let status: String
	let reason: String?
}
