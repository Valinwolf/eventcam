//
//  MediaView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI
import AVKit

struct MediaView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject var galleryStore: LocalGalleryStore

	@State private var currentIndex: Int
	@State private var message: String?
	@State private var verticalOffset: CGFloat = 0
	@State private var showingFailureInfo = false

	init(galleryStore: LocalGalleryStore, selectedItemID: UUID) {
		self.galleryStore = galleryStore
		let index = galleryStore.indexOfItem(selectedItemID) ?? 0
		_currentIndex = State(initialValue: index)
	}

	var body: some View {
		ZStack {
			Color.black
				.ignoresSafeArea()

			if !galleryStore.items.isEmpty {
				VStack(spacing: 0) {
					topBar

					TabView(selection: $currentIndex) {
						ForEach(Array(galleryStore.items.enumerated()), id: \.element.id) { index, item in
							mediaPage(for: item)
								.tag(index)
						}
					}
					.tabViewStyle(.page(indexDisplayMode: .never))
					.offset(y: verticalOffset)
					.gesture(
						DragGesture()
							.onChanged { value in
								if abs(value.translation.height) > abs(value.translation.width) {
									verticalOffset = max(0, value.translation.height)
								}
							}
							.onEnded { value in
								if value.translation.height > 140 {
									dismiss()
								} else {
									withAnimation(.spring()) {
										verticalOffset = 0
									}
								}
							}
					)
				}
			}
		}
		.alert("Upload Failure Details", isPresented: $showingFailureInfo) {
			Button("OK", role: .cancel) { }
		} message: {
			Text(humanReadableFailureMessage(for: currentItem))
		}
	}

	private var currentItem: LocalGalleryItem? {
		guard galleryStore.items.indices.contains(currentIndex) else { return nil }
		return galleryStore.items[currentIndex]
	}

	private var topBar: some View {
		VStack(spacing: 10) {
			HStack {
				Button {
					dismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.headline)
						.padding(10)
						.background(.ultraThinMaterial, in: Circle())
				}

				Spacer()

				if let item = currentItem {
					Button {
						galleryStore.saveItemToPhotos(item) { success in
							message = success ? "Saved to Photos." : "Save failed."
						}
					} label: {
						Image(systemName: "arrow.down.circle")
					}
					.buttonStyle(.borderedProminent)

					if item.uploadState == .failed {
						Button {
							showingFailureInfo = true
						} label: {
							Image(systemName: "info.circle")
						}
						.buttonStyle(.bordered)
					}

					Button {
						galleryStore.enqueueUpload(for: item.id)
						message = "Retrying upload."
					} label: {
						Image(systemName: "arrow.clockwise")
					}
					.buttonStyle(.bordered)
					.disabled(item.uploadState != .failed)

					Button(role: .destructive) {
						guard currentItem != nil else { return }

						let oldIndex = currentIndex
						let hadNextItem = oldIndex < galleryStore.items.count - 1

						if let item = currentItem {
							galleryStore.deleteItem(item)
						}

						if galleryStore.items.isEmpty {
							dismiss()
							return
						}

						withAnimation {
							if hadNextItem {
								currentIndex = min(oldIndex, galleryStore.items.count - 1)
							} else {
								currentIndex = max(0, oldIndex - 1)
							}
						}

						message = nil
					} label: {
						Image(systemName: "trash")
					}
					.buttonStyle(.bordered)
				}
			}

			if let item = currentItem {
				HStack {
					Text(item.displayFileName ?? item.fileName)
						.foregroundStyle(.white)
						.font(.caption)

					Spacer()

					Text(item.uploadState.rawValue.capitalized)
						.foregroundStyle(.white.opacity(0.8))
						.font(.caption)

					if let token = item.controlToken, !token.isEmpty {
						Image(systemName: "key.fill")
							.foregroundStyle(.green)
					}
				}
			}

			if let message {
				Text(message)
					.font(.caption)
					.foregroundStyle(.white.opacity(0.85))
			}
		}
		.padding()
	}

	@ViewBuilder
	private func mediaPage(for item: LocalGalleryItem) -> some View {
		switch item.type {
		case .photo:
			if let image = UIImage(contentsOfFile: galleryStore.fileURL(for: item).path) {
				Image(uiImage: image)
					.resizable()
					.scaledToFit()
					.padding()
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color.black)
			} else {
				Text("Image unavailable")
					.foregroundStyle(.white)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color.black)
			}

		case .video:
			VideoPlayer(player: AVPlayer(url: galleryStore.fileURL(for: item)))
				.background(Color.black)
				.ignoresSafeArea(edges: .bottom)
		}
	}

	private func humanReadableFailureMessage(for item: LocalGalleryItem?) -> String {
		guard let item else {
			return "No failure details are available."
		}

		let raw = item.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		if raw.isEmpty {
			return "The upload failed, but the server did not provide any additional details."
		}

		if let data = raw.data(using: .utf8),
		   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
			let errorText = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
			let detailsText = (json["details"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

			if let detailsText, !detailsText.isEmpty {
				return humanReadableFailureMessage(from: detailsText)
			}

			if let errorText, !errorText.isEmpty {
				return humanReadableFailureMessage(from: errorText)
			}
		}

		return humanReadableFailureMessage(from: raw)
	}

	private func humanReadableFailureMessage(from raw: String) -> String {
		let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		let lower = cleaned.lowercased()

		if lower.contains("timed out") || lower.contains("timeout") {
			return "The upload took too long and timed out. The network may have been slow or the server may not have responded in time."
		}

		if lower.contains("not found") || lower.contains("404") {
			return "The upload destination could not be found. This usually means the server or storage path is incorrect."
		}

		if lower.contains("403") || lower.contains("forbidden") || lower.contains("access denied") {
			return "The upload was rejected due to permissions or access restrictions."
		}

		if lower.contains("401") || lower.contains("unauthorized") {
			return "The upload request was not authorized. A new token or valid credentials may be required."
		}

		if lower.contains("500") || lower.contains("internal server error") {
			return "The server encountered an internal error while processing the upload."
		}

		if lower.contains("json") || lower.contains("decode") {
			return "The app received an unexpected response from the server."
		}

		if lower.contains("network") || lower.contains("offline") || lower.contains("internet") {
			return "The upload failed because of a network connectivity problem."
		}

		if lower.contains("direct upload failed") {
			return "The file could not be uploaded to storage. The server prepared the upload, but the storage provider rejected it."
		}

		if lower.contains("sqlstate") || lower.contains("not null violation") {
			return "The server rejected the upload because required media information was missing."
		}

		return cleaned
	}
}
