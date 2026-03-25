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

				ScrollView {
					LazyVGrid(columns: columns, spacing: 8) {
						CameraLauncherTile {
							showingCamera = true
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
			.sheet(isPresented: $showingCamera) {
				CameraView(galleryStore: galleryStore)
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
}
