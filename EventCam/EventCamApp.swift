//
//  EventCamApp.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/23/26.
//

import SwiftUI

@main
struct EventCamApp: App {
	enum Screen {
		case login
		case gallery
	}

	@State private var screen: Screen = .login
	@State private var eventCode: String = ""
	@State private var userName: String = ""

	var body: some Scene {
		WindowGroup {
			switch screen {
			case .login:
				LoginView(
					event: $eventCode,
					name: $userName,
					onLoginSuccess: {
						screen = .gallery
					}
				)

			case .gallery:
				GalleryView(
					event: $eventCode,
					name: $userName,
					onLogout: {
						eventCode = ""
						screen = .login
					}
				)
			}
		}
	}
}
