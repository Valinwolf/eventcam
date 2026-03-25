//
//  CameraLauncherTile.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI

struct CameraLauncherTile: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			RoundedRectangle(cornerRadius: 10)
				.fill(.gray.opacity(0.15))
				.frame(height: 110)
				.overlay {
					VStack(spacing: 8) {
						Image(systemName: "camera.fill")
							.font(.title2)

						Text("Camera")
							.font(.caption)
					}
					.foregroundStyle(.primary)
				}
		}
		.buttonStyle(.plain)
	}
}
