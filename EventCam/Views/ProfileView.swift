//
//  ProfileView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String

    @AppStorage("savedParticipantName") private var savedParticipantName: String = ""
    @AppStorage("savedEventHistory") private var savedEventHistoryData: Data = Data()

    @State private var draftName: String
    @State private var pendingDeleteCode: String?
    @State private var showClearAllConfirmation = false
    @State private var infoMessage: String?

    init(name: Binding<String>) {
        self._name = name
        self._draftName = State(initialValue: name.wrappedValue)
    }

    private var eventHistory: [String] {
        EventHistoryStore.load(from: savedEventHistoryData)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    TextField("Your Name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Button("Save Name") {
                        saveName()
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let infoMessage {
                    Section {
                        Text(infoMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Clearing history does not delete uploaded photos or videos from the event organizer's side.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Event History") {
                    if eventHistory.isEmpty {
                        Text("No event history yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(eventHistory, id: \.self) { code in
                            HStack {
                                Text(code)
                                    .font(.system(.body, design: .monospaced))

                                Spacer()

                                Button(role: .destructive) {
                                    pendingDeleteCode = code
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Delete History Item", isPresented: Binding(
                get: { pendingDeleteCode != nil },
                set: { newValue in
                    if !newValue {
                        pendingDeleteCode = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteCode = nil
                }

                Button("Delete", role: .destructive) {
                    if let code = pendingDeleteCode {
                        removeHistoryItem(code)
                    }
                    pendingDeleteCode = nil
                }
            } message: {
                Text("This will remove the selected event code from local history only. It will not delete uploaded photos or videos.")
            }
            .alert("Clear All History", isPresented: $showClearAllConfirmation) {
                Button("Cancel", role: .cancel) {}

                Button("Clear All", role: .destructive) {
                    clearAllHistory()
                }
            } message: {
                Text("This will remove all saved event codes from local history only. It will not delete uploaded photos or videos.")
            }
        }
    }

    private func saveName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        draftName = trimmed
        name = trimmed
        savedParticipantName = trimmed
        infoMessage = "Name updated."
    }

    private func removeHistoryItem(_ code: String) {
        let updated = EventHistoryStore.remove(code, from: eventHistory)
        savedEventHistoryData = EventHistoryStore.save(updated)
        infoMessage = "Removed \(code) from history."
    }

    private func clearAllHistory() {
        savedEventHistoryData = EventHistoryStore.save(EventHistoryStore.clear())
        infoMessage = "Cleared all event history."
    }
}
