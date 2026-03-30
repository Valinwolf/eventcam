//
//  GalleryView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI

struct GalleryView: View {
	@Binding var event: String
	@Binding var name: String
	let onLogout: () -> Void

	@StateObject private var galleryStore = LocalGalleryStore()

	@State private var showingCamera = false
	@State private var cameraSessionID = UUID()
	@State private var pendingReopenAfterCapture = false

	@State private var showingProfile = false
	@State private var selectedItem: LocalGalleryItem?
	@State private var infoMessage: String?

	private let columns = [
		GridItem(.flexible()),
		GridItem(.flexible()),
		GridItem(.flexible())
	]

	var body: some View {
		NavigationStack {
			VStack(spacing: 12) {
				if let infoMessage {
					Text(infoMessage)
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.horizontal)
				}

				if !galleryStore.isEventOpenForCapture {
					closedEventBanner
				}

				ScrollView {
					LazyVGrid(columns: columns, spacing: 8) {
						if galleryStore.isEventOpenForCapture {
							CameraLauncherTile {
								openFreshCamera()
							}
						}

						ForEach(galleryStore.items) { item in
							GalleryTileView(item: item, store: galleryStore)
								.onTapGesture {
									selectedItem = item
								}
						}
					}
					.padding(.horizontal)
				}
			}
			.navigationTitle("Gallery")
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button {
						showingProfile = true
					} label: {
						Image(systemName: "person.crop.circle")
					}
				}

				ToolbarItem(placement: .topBarTrailing) {
					Menu {
						Button {
							Task {
								await galleryStore.refreshEventInfo()
							}
							infoMessage = "Refreshing event status."
						} label: {
							Label("Refresh Event Status", systemImage: "arrow.clockwise")
						}

						Button {
							galleryStore.retryFailedUploads()
							infoMessage = "Retrying failed uploads."
						} label: {
							Label("Retry Failed Uploads", systemImage: "arrow.clockwise")
						}

						Button {
							galleryStore.saveAllToPhotos { success in
								infoMessage = success
									? "Gallery saved to Photos."
									: "Could not save gallery."
							}
						} label: {
							Label("Save Gallery", systemImage: "arrow.down.circle")
						}

						Button(role: .destructive) {
							galleryStore.eraseAll()
							infoMessage = "Deleted local files."
						} label: {
							Label("Delete local files", systemImage: "trash")
						}

						Divider()

						Button(role: .destructive) {
							onLogout()
						} label: {
							Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
						}
					} label: {
						Image(systemName: "ellipsis.circle")
					}
				}
			}
			.onAppear {
				galleryStore.configureSession(eventCode: event, participantName: name)
			}
			.onChange(of: event) { _, newValue in
				galleryStore.configureSession(eventCode: newValue, participantName: name)
			}
			.onChange(of: name) { _, newValue in
				galleryStore.configureSession(eventCode: event, participantName: newValue)
			}
			.fullScreenCover(
				isPresented: $showingCamera,
				onDismiss: {
					handleCameraDismiss()
				}
			) {
				CameraView { captured in
					switch captured {
					case let .photo(image, takenAt):
						galleryStore.addPhoto(image, takenAt: takenAt)
					case let .video(url, takenAt):
						galleryStore.addVideo(from: url, takenAt: takenAt)
					}
				}
				.id(cameraSessionID)
				.ignoresSafeArea()
				.interactiveDismissDisabled(true)
			}
			.sheet(isPresented: $showingProfile) {
				ProfileView(name: $name)
			}
			.fullScreenCover(item: $selectedItem) { item in
				MediaView(
					galleryStore: galleryStore,
					selectedItemID: item.id
				)
			}
		}
	}

	private var closedEventBanner: some View {
		VStack(alignment: .leading, spacing: 6) {
			Label("This event is closed for new photos and videos.", systemImage: "camera.slash")
				.font(.subheadline.weight(.semibold))

			Text(closedEventMessage)
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.background(.orange.opacity(0.12))
		.overlay(
			RoundedRectangle(cornerRadius: 12)
				.stroke(.orange.opacity(0.25), lineWidth: 1)
		)
		.clipShape(RoundedRectangle(cornerRadius: 12))
		.padding(.horizontal)
	}

	private var closedEventMessage: String {
		guard let event = galleryStore.currentEventInfo?.event else {
			return "Uploads are currently unavailable for this event."
		}

		if let start = event.eventStartDate, Date() < start {
			return "This event has not started yet. Please check back when the event begins."
		}

		if let end = event.eventEndDate, Date() > end {
			return "This event has ended. You can still browse and save media that is already in your gallery."
		}

		return "Uploads are currently unavailable for this event."
	}

	private func openFreshCamera() {
		guard galleryStore.isEventOpenForCapture else { return }
		cameraSessionID = UUID()
		showingCamera = true
	}

	private func handleCameraDismiss() {
		guard pendingReopenAfterCapture else { return }
		guard galleryStore.isEventOpenForCapture else {
			pendingReopenAfterCapture = false
			return
		}

		pendingReopenAfterCapture = false

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			cameraSessionID = UUID()
			showingCamera = true
		}
	}
}
