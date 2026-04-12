import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var storage: StorageService

    @State private var childName: String = ""
    @State private var age: Int = 6
    @State private var gender: String = ""
    @State private var location: String = ""
    @State private var savedProfileName: String = ""
    @State private var savedProfileAge: Int = 6
    @State private var savedProfileGender: String = ""
    @State private var savedProfileLocation: String = ""
    @State private var showProfileSavedFeedback = false
    @State private var showClearProfileConfirmation = false
    @State private var showFeaturesAndPrivacyPolicy = false

    @State private var readingMode: ReadingMode = .scroll
    @State private var enhancedTextSize: Bool = false
    @State private var textSizeScale: Double = 0.5
    @State private var tapImageToExpand: Bool = true

    private var previewFontSize: CGFloat {
        let minSize: CGFloat = 14
        let maxSize: CGFloat = 32
        return minSize + CGFloat(textSizeScale) * (maxSize - minSize)
    }

    private let textSizeSliderStep = 1.0 / 7.0

    private var trimmedChildName: String {
        childName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasUnsavedProfileChanges: Bool {
        trimmedChildName != savedProfileName
        || age != savedProfileAge
        || gender != savedProfileGender
        || location != savedProfileLocation
    }

    private var canSaveProfile: Bool {
        !trimmedChildName.isEmpty && hasUnsavedProfileChanges
    }

    private var primaryButtonBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var primaryButtonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Reading")) {
                    Picker("Reading Mode", selection: $readingMode) {
                        Text("Scroll Down").tag(ReadingMode.scroll)
                        Text("Page Flip").tag(ReadingMode.pageFlip)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Enhance Text Size", isOn: $enhancedTextSize)

                    if enhancedTextSize {
                        HStack(spacing: 12) {
                            Text("A")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Slider(value: $textSizeScale, in: 0...1, step: textSizeSliderStep)

                            Text("A")
                                .font(.title)
                                .foregroundColor(.secondary)
                        }

                        Text("A quick brown fox jumped over the lazy dog")
                            .font(.system(size: previewFontSize))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Toggle("Tap Image to Expand", isOn: $tapImageToExpand)
                }
                .listRowBackground(AppPalette.card(for: colorScheme))

                Section(header: Text("Child Profile"), footer: Text("Optional. You can update this any time.")) {
                    TextField("Child Name", text: $childName)
                    Stepper("Age: \(age)", value: $age, in: 1...12)
                    TextField("Gender (Optional)", text: $gender)
                    TextField("Location/Culture (Optional)", text: $location)

                    HStack(spacing: 12) {
                        Button {
                            saveProfile()
                        } label: {
                            HStack(spacing: 8) {
                                if showProfileSavedFeedback {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text(showProfileSavedFeedback ? "Saved" : "Save")
                            }
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(primaryButtonBackground)
                        .foregroundStyle(primaryButtonForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(!canSaveProfile)

                        if storage.profile != nil {
                            Button(role: .destructive) {
                                showClearProfileConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.red)
                                    .frame(width: 42, height: 42)
                                    .background(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear profile")
                        }
                    }
                }
                .listRowBackground(AppPalette.card(for: colorScheme))

                Section {
                    Button {
                        showFeaturesAndPrivacyPolicy = true
                    } label: {
                        Text("Features and Privacy Policy")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background(for: colorScheme))
            .navigationTitle("Settings")
            .sheet(isPresented: $showFeaturesAndPrivacyPolicy) {
                FeaturesPrivacyPolicyView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        persistSettings()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                loadProfileFields()
                loadSettingsFields()
            }
            .onChange(of: childName) { _, _ in
                showProfileSavedFeedback = false
            }
            .onChange(of: age) { _, _ in
                showProfileSavedFeedback = false
            }
            .onChange(of: gender) { _, _ in
                showProfileSavedFeedback = false
            }
            .onChange(of: location) { _, _ in
                showProfileSavedFeedback = false
            }
            .onChange(of: readingMode) { _, _ in persistSettings() }
            .onChange(of: enhancedTextSize) { _, _ in persistSettings() }
            .onChange(of: textSizeScale) { _, _ in persistSettings() }
            .onChange(of: tapImageToExpand) { _, _ in persistSettings() }
            .confirmationDialog(
                "Clear child details?",
                isPresented: $showClearProfileConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Data", role: .destructive) {
                    storage.clearProfile()
                    loadProfileFields()
                    showProfileSavedFeedback = false
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the saved child profile details from this device.")
            }
        }
    }

    private func loadProfileFields() {
        if let profile = storage.profile {
            childName = profile.childName
            age = profile.age
            gender = profile.gender
            location = profile.location
            savedProfileName = profile.childName
            savedProfileAge = profile.age
            savedProfileGender = profile.gender
            savedProfileLocation = profile.location
        } else {
            childName = ""
            age = 6
            gender = ""
            location = ""
            savedProfileName = ""
            savedProfileAge = 6
            savedProfileGender = ""
            savedProfileLocation = ""
        }
    }

    private func loadSettingsFields() {
        readingMode = storage.settings.readingMode
        enhancedTextSize = storage.settings.enhancedTextSize
        textSizeScale = storage.settings.textSizeScale
        tapImageToExpand = storage.settings.tapImageToExpand
    }

    private func saveProfile() {
        let trimmedName = trimmedChildName
        guard !trimmedName.isEmpty, hasUnsavedProfileChanges else { return }
        storage.saveProfile(Profile(childName: trimmedName, age: age, gender: gender, location: location))
        savedProfileName = trimmedName
        savedProfileAge = age
        savedProfileGender = gender
        savedProfileLocation = location
        childName = trimmedName
        showProfileSavedFeedback = true
    }

    private func persistSettings() {
        storage.saveSettings(
            AppSettings(
                readingMode: readingMode,
                enhancedTextSize: enhancedTextSize,
                tapImageToExpand: tapImageToExpand,
                textSizeScale: textSizeScale
            )
        )
    }
}
