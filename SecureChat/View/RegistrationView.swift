//
//  PhoneNumberView.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import SwiftUI

// MARK: - Country

struct Country: Identifiable, Hashable {
    let id: String              // ISO 3166-1 alpha-2
    let flag: String
    let name: String
    let dialCode: String        // includes "+"
    let digitRange: ClosedRange<Int>
    let groups: [Int]           // display grouping, e.g. [4, 6] -> "7911 123456"
    let example: String

    static let all: [Country] = [
        Country(id: "GB", flag: "🇬🇧", name: "United Kingdom", dialCode: "+44",
                digitRange: 10...10, groups: [4, 6], example: "7911 123456"),
        Country(id: "IT", flag: "🇮🇹", name: "Italy", dialCode: "+39",
                digitRange: 9...10, groups: [3, 3, 4], example: "312 345 6789"),
        Country(id: "US", flag: "🇺🇸", name: "United States", dialCode: "+1",
                digitRange: 10...10, groups: [3, 3, 4], example: "201 555 0123"),
        Country(id: "FR", flag: "🇫🇷", name: "France", dialCode: "+33",
                digitRange: 9...9, groups: [1, 2, 2, 2, 2], example: "6 12 34 56 78"),
        Country(id: "DE", flag: "🇩🇪", name: "Germany", dialCode: "+49",
                digitRange: 10...11, groups: [4, 7], example: "1511 2345678"),
        Country(id: "ES", flag: "🇪🇸", name: "Spain", dialCode: "+34",
                digitRange: 9...9, groups: [3, 3, 3], example: "612 345 678")
    ]

    var maxDigits: Int { digitRange.upperBound }

    func isValid(_ digits: String) -> Bool {
        digitRange.contains(digits.count)
    }

    /// Inserts spaces according to `groups`. Anything past the last group is appended as-is.
    func format(_ digits: String) -> String {
        var result = ""
        var index = digits.startIndex

        for group in groups {
            guard index < digits.endIndex else { break }
            let end = digits.index(index, offsetBy: group, limitedBy: digits.endIndex) ?? digits.endIndex
            if !result.isEmpty { result += " " }
            result += digits[index..<end]
            index = end
        }

        if index < digits.endIndex {
            result += " " + digits[index...]
        }
        return result
    }
}

// MARK: - Registration view

struct PhoneNumberView: View {

    /// Called with the number in E.164 form, e.g. "+447911123456".
    var onContinue: (String) async throws -> Void

    @State private var country: Country = Country.all[0]
    @State private var digits = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var isPhoneFocused: Bool

    /// Single source of truth is `digits` (unformatted). The field only ever
    /// *displays* a formatted string, so there's no reformat-loop to manage.
    private var phoneText: Binding<String> {
        Binding(
            get: { country.format(digits) },
            set: { newValue in
                digits = String(newValue.filter(\.isNumber).prefix(country.maxDigits))
                errorMessage = nil
            }
        )
    }

    private var e164: String { country.dialCode + digits }
    private var isValid: Bool { country.isValid(digits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            phoneField
            footer
            Spacer(minLength: 0)
            continueButton
        }
        .padding(24)
        .onAppear { isPhoneFocused = true }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's your number?")
                .font(.largeTitle.bold())
            Text("We'll text you a code to verify it's really you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var phoneField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                countryMenu

                Divider().frame(height: 28)

                TextField(country.example, text: phoneText)
                    .font(.title3)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($isPhoneFocused)
                    .submitLabel(.continue)
                    .onSubmit { submit() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(errorMessage == nil ? .clear : Color.red, lineWidth: 1)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: errorMessage)
    }

    private var countryMenu: some View {
        Menu {
            Picker("Country", selection: $country) {
                ForEach(Country.all) { item in
                    Text("\(item.flag)  \(item.name)  \(item.dialCode)").tag(item)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(country.flag)
                Text(country.dialCode)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.title3)
        }
        .onChange(of: country) { _, newCountry in
            // Trim if the new country has a shorter max length.
            digits = String(digits.prefix(newCountry.maxDigits))
        }
    }

    private var footer: some View {
        Text("By continuing you agree to our Terms and Privacy Policy.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var continueButton: some View {
        Button(action: submit) {
            ZStack {
                Text("Continue").opacity(isSubmitting ? 0 : 1)
                if isSubmitting { ProgressView().tint(.white) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isValid || isSubmitting)
    }

    // MARK: Actions

    private func submit() {
        guard isValid, !isSubmitting else { return }
        isPhoneFocused = false
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                try await onContinue(e164)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhoneNumberView { number in
        try await Task.sleep(for: .seconds(1))
        print("Sending code to \(number)")
    }
}
