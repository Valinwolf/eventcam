//
//  EventHistoryStore.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import Foundation

enum EventHistoryStore {

	private static let maxItems = 20

	// MARK: - Load

	static func load(from data: Data?) -> [String] {
		guard let data else { return [] }

		do {
			let decoded = try JSONDecoder().decode([String].self, from: data)
			return decoded
		} catch {
			print("EventHistoryStore: Failed to decode history: \(error)")
			return []
		}
	}

	// MARK: - Save

	static func save(_ history: [String]) -> Data {
		do {
			return try JSONEncoder().encode(history)
		} catch {
			print("EventHistoryStore: Failed to encode history: \(error)")
			return Data()
		}
	}

	// MARK: - Add / Upsert

	static func add(_ code: String, to history: [String]) -> [String] {
		let normalized = normalize(code)

		guard !normalized.isEmpty else { return history }

		var newHistory = history.filter { normalize($0) != normalized }

		newHistory.insert(normalized, at: 0)

		if newHistory.count > maxItems {
			newHistory = Array(newHistory.prefix(maxItems))
		}

		return newHistory
	}

	// MARK: - Remove One

	static func remove(_ code: String, from history: [String]) -> [String] {
		let normalized = normalize(code)
		return history.filter { normalize($0) != normalized }
	}

	// MARK: - Clear All

	static func clear() -> [String] {
		return []
	}

	// MARK: - Normalize

	private static func normalize(_ value: String) -> String {
		value
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.uppercased()
	}
}
