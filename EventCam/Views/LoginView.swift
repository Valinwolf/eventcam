//
//  LoginView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI

struct LoginView: View {
	@Binding var event: String
	@Binding var name: String

	let onLoginSuccess: () -> Void

	@AppStorage("savedParticipantName") private var savedParticipantName: String = ""
	@AppStorage("savedEventHistory") private var savedEventHistoryData: Data = Data()

	@State private var step: Step = .name
	@State private var draftName: String = ""
	@State private var draftEvent: String = ""
	@State private var showError = false
	@State private var showHistory = false

	@FocusState private var focusedField: Field?

	private enum Step {
		case name
		case event
	}

	private enum Field {
		case name
		case event
	}

	private var eventHistory: [String] {
		EventHistoryStore.load(from: savedEventHistoryData)
	}

	private var filteredHistory: [String] {
		let query = draftEvent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

		if query.isEmpty {
			return eventHistory
		}

		return eventHistory.filter { $0.contains(query) }
	}

	var body: some View {
		NavigationStack {
			VStack(spacing: 24) {
				Spacer()

				VStack(spacing: 12) {
					Image(systemName: "camera.fill")
						.font(.system(size: 50))
						.foregroundStyle(.blue)

					Text("EventCam")
						.font(.largeTitle)
						.fontWeight(.bold)

					if step == .event, !draftName.isEmpty {
						Text("Hi, \(draftName)")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}

				VStack(spacing: 16) {
					if step == .name {
						TextField("Your Name", text: $draftName)
							.textInputAutocapitalization(.words)
							.autocorrectionDisabled()
							.textContentType(.name)
							.submitLabel(.continue)
							.focused($focusedField, equals: .name)
							.onSubmit {
								continueFromName()
							}
							.padding()
							.background(.gray.opacity(0.1))
							.cornerRadius(10)
					} else {
						VStack(spacing: 8) {
							HStack(spacing: 8) {
								TextField("Event Code", text: $draftEvent)
									.textInputAutocapitalization(.characters)
									.autocorrectionDisabled()
									.font(.system(.body, design: .monospaced))
									.submitLabel(.go)
									.focused($focusedField, equals: .event)
									.onTapGesture {
										showHistory = true
									}
									.onChange(of: draftEvent) { _, _ in
										showHistory = true
									}
									.onSubmit {
										attemptLogin()
									}

								if !eventHistory.isEmpty {
									Button {
										withAnimation(.easeInOut(duration: 0.15)) {
											showHistory.toggle()
										}
									} label: {
										Image(systemName: "chevron.down")
											.rotationEffect(.degrees(showHistory ? 180 : 0))
											.animation(.easeInOut(duration: 0.15), value: showHistory)
											.foregroundStyle(.secondary)
									}
								}
							}
							.padding()
							.background(.gray.opacity(0.1))
							.cornerRadius(10)

							if showHistory && !filteredHistory.isEmpty {
								VStack(spacing: 0) {
									ForEach(filteredHistory, id: \.self) { historyItem in
										Button {
											draftEvent = historyItem
											showHistory = false
											focusedField = .event
										} label: {
											HStack {
												Image(systemName: "clock.arrow.circlepath")
													.foregroundStyle(.secondary)

												Text(historyItem)
													.font(.system(.body, design: .monospaced))
													.foregroundStyle(.primary)

												Spacer()
											}
											.padding(.horizontal, 12)
											.padding(.vertical, 10)
										}
										.buttonStyle(.plain)

										if historyItem != filteredHistory.last {
											Divider()
										}
									}
								}
								.background(.gray.opacity(0.08))
								.clipShape(RoundedRectangle(cornerRadius: 10))
							}
						}

						Button {
							step = .name
							focusedField = .name
						} label: {
							Text("Not \(draftName)? Change name")
								.font(.footnote)
						}
					}
				}

				Button {
					if step == .name {
						continueFromName()
					} else {
						attemptLogin()
					}
				} label: {
					Text(step == .name ? "Continue" : "Enter Event")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(primaryButtonDisabled)

				Spacer()

				Text("Photos and videos are stored locally and uploaded in the background.")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal)
			}
			.padding()
			.navigationTitle(step == .name ? "Welcome" : "Join Event")
			.alert("Missing Information", isPresented: $showError) {
				Button("OK", role: .cancel) { }
			} message: {
				Text(step == .name
					 ? "Please enter your name."
					 : "Please enter an event code.")
			}
			.onAppear {
				draftName = savedParticipantName.trimmingCharacters(in: .whitespacesAndNewlines)
				name = draftName

				if draftName.isEmpty {
					step = .name
					focusedField = .name
				} else {
					step = .event
					focusedField = .event
				}
			}
			.onTapGesture {
				if step == .event {
					showHistory = false
				}
			}
		}
	}

	private var primaryButtonDisabled: Bool {
		switch step {
		case .name:
			return draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		case .event:
			return draftEvent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}
	}

	private func continueFromName() {
		let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !trimmedName.isEmpty else {
			showError = true
			return
		}

		draftName = trimmedName
		name = trimmedName
		savedParticipantName = trimmedName

		withAnimation(.easeInOut(duration: 0.2)) {
			step = .event
			showHistory = true
		}

		focusedField = .event
	}

	private func attemptLogin() {
		let trimmedEvent = draftEvent.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !trimmedEvent.isEmpty else {
			showError = true
			return
		}

		let normalizedEvent = trimmedEvent.uppercased()

		draftEvent = normalizedEvent
		event = normalizedEvent
		name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)

		let updatedHistory = EventHistoryStore.add(normalizedEvent, to: eventHistory)
		savedEventHistoryData = EventHistoryStore.save(updatedHistory)

		showHistory = false
		onLoginSuccess()
	}
}
