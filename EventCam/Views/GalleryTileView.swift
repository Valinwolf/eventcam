//
//  GalleryTileView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI

struct GalleryTileView: View {
	let item: LocalGalleryItem
	let store: LocalGalleryStore

	@State private var videoThumbnail: UIImage?

	var body: some View {
		ZStack(alignment: .topTrailing) {
			ZStack(alignment: .bottomTrailing) {
				if let image = displayImage {
					Image(uiImage: image)
						.resizable()
						.scaledToFill()
						.frame(height: 110)
						.frame(maxWidth: .infinity)
						.clipped()
						.cornerRadius(10)
				} else {
					RoundedRectangle(cornerRadius: 10)
						.fill(.gray.opacity(0.2))
						.frame(height: 110)
						.overlay {
							Image(systemName: item.type == .video ? "video.slash.fill" : "photo")
								.font(.title3)
								.foregroundStyle(.secondary)
						}
				}

				if item.type == .video {
					Image(systemName: "video.fill")
						.padding(6)
						.background(.ultraThinMaterial, in: Circle())
						.padding(6)
				}
			}

			Text(uploadLabel)
				.font(.caption2)
				.padding(.horizontal, 6)
				.padding(.vertical, 4)
				.background(.ultraThinMaterial, in: Capsule())
				.padding(6)
		}
		.task(id: item.id) {
			guard item.type == .video else { return }
			videoThumbnail = await store.loadThumbnail(for: item)
		}
	}

	private var displayImage: UIImage? {
		switch item.type {
		case .photo:
			return store.thumbnailImage(for: item)
		case .video:
			return videoThumbnail
		}
	}

	private var uploadLabel: String {
		switch item.uploadState {
		case .pending: return "Pending"
		case .queued: return "Queued"
		case .uploading: return "Uploading"
		case .uploaded: return "Uploaded"
		case .failed: return "Failed"
		}
	}
}
