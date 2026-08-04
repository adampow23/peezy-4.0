//
//  ProviderActionCard.swift
//  Peezy 4.0
//
//  Self-service terminal for provider links and calls. Resolver confidence and
//  internal method names intentionally never appear in this view.
//

import SwiftUI
import SafariServices
import UIKit

enum ProviderActionKind {
    case addressChange
    case cancellation
    case locationTransfer
    case recordsTransfer
    case accountClosure

    init(intent: ProviderIntent) {
        switch intent {
        case .cancel: self = .cancellation
        case .updateAddress: self = .addressChange
        case .transferLocation: self = .locationTransfer
        case .transferRecords: self = .recordsTransfer
        case .closeAccount: self = .accountClosure
        }
    }

    var noun: String {
        switch self {
        case .addressChange: "address change"
        case .cancellation: "cancellation"
        case .locationTransfer: "location transfer"
        case .recordsTransfer: "records transfer"
        case .accountClosure: "account closure"
        }
    }

    var callScript: String {
        switch self {
        case .addressChange:
            "Hi, I'm calling to update the address on my account to my new address."
        case .cancellation:
            "Hi, I'm calling to cancel my membership. Please confirm the effective date and any final charge."
        case .locationTransfer:
            "Hi, I'm calling to transfer my membership to a location near my new address."
        case .recordsTransfer:
            "Hi, I'm calling to transfer my records to a new provider. What do you need from me?"
        case .accountClosure:
            "Hi, I'm calling to close my account. Please confirm the effective date and any final balance."
        }
    }
}

enum ProviderNoticeFormatter {
    static func line(noticeDays: Int, moveDate: Date, calendar: Calendar = .current) -> String? {
        guard (1...365).contains(noticeDays),
              let deadline = calendar.date(byAdding: .day, value: -noticeDays, to: moveDate) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "This one needs \(noticeDays) days' notice — do it by \(formatter.string(from: deadline)) to be clear before your move."
    }
}

struct ProviderActionCard: View {
    let taskTitle: String
    let resolution: ProviderResolution
    let actionKind: ProviderActionKind
    let userId: String
    let showBack: Bool
    let onDone: () -> Void
    let onBack: () -> Void
    var identityOverride: PeezyIdentity? = nil

    @Environment(\.openURL) private var openURL
    @State private var safariDestination: ProviderSafariDestination?
    @State private var identityDetails = ""
    @State private var identityMoveDate: Date?
    @State private var copyStatus: String?

    var body: some View {
        VStack(spacing: 0) {
            providerHeader

            Spacer()

            VStack(spacing: 18) {
                Image(systemName: resolution.method == .call ? "phone.fill" : "safari.fill")
                    .font(.title)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(width: 64, height: 64)
                    .background(PeezyTheme.Colors.deepInk.opacity(0.08), in: Circle())
                    .accessibilityHidden(true)

                Text(actionHeading)
                    .font(.title2.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .multilineTextAlignment(.center)

                actionContent

                if !resolution.requirements.isEmpty {
                    requirementsList
                }

                Button {
                    UIPasteboard.general.string = identityDetails
                    copyStatus = "Copied your details."
                    PeezyHaptics.light()
                } label: {
                    Label("Copy my details", systemImage: "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(PeezyTheme.Colors.deepInk)
                .disabled(identityDetails.isEmpty)
                .accessibilityHint("Copies your name, new address, and phone number when available")
                .accessibilityIdentifier("provider.action.copy")

                if identityDetails.isEmpty {
                    Text("Add your name and new address in Settings to copy them here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("provider.action.copy_unavailable")
                } else if let copyStatus {
                    Text(copyStatus)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("provider.action.copy_result")
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            PeezyAssessmentButton("Done") {
                onDone()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("provider.action.done")
        }
        .accessibilityIdentifier("provider.action.card")
        .task(id: userId) {
            await loadIdentityDetails()
        }
        .sheet(item: $safariDestination) { destination in
            ProviderSafariView(url: destination.url)
                .ignoresSafeArea()
        }
    }

    private var requirementsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(resolution.requirements.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(resolution.requirements[index].text)
                }
                .font(.subheadline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .accessibilityIdentifier("provider.requirement.\(index)")
            }

            if let noticeLine {
                Text(noticeLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .accessibilityIdentifier("provider.requirement.notice_deadline")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PeezyTheme.Colors.deepInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("provider.requirements")
    }

    private var noticeLine: String? {
        guard let moveDate = identityMoveDate,
              let noticeDays = resolution.requirements.first(where: { $0.kind == .noticePeriod })?.noticeDays else {
            return nil
        }
        return ProviderNoticeFormatter.line(noticeDays: noticeDays, moveDate: moveDate)
    }

    private var providerHeader: some View {
        HStack(alignment: .center, spacing: 6) {
            if showBack {
                Button {
                    PeezyHaptics.light()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to provider search")
                .accessibilityIdentifier("provider.action.back")
            }

            Spacer()

            Text(taskTitle.uppercased())
                .font(.caption.bold())
                .tracking(1.5)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var actionContent: some View {
        switch resolution.method {
        case .link:
            if let url = resolution.url {
                PeezyAssessmentButton("Open " + resolution.name) {
                    safariDestination = ProviderSafariDestination(url: url)
                }
                .accessibilityHint(
                    "Opens " + resolution.name + "'s official " + actionKind.noun + " page in the app"
                )
                .accessibilityIdentifier("provider.action.open")
            }

        case .call:
            if let phone = resolution.phone {
                Text(phone)
                    .font(.headline)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("provider.action.phone")

                Text(actionKind.callScript)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Suggested call script: \(actionKind.callScript)")
                    .accessibilityIdentifier("provider.action.script")

                PeezyAssessmentButton("Call " + resolution.name) {
                    let dialable = phone.filter { $0.isNumber || $0 == "+" }
                    if let url = URL(string: "tel:\(dialable)") {
                        openURL(url)
                    }
                }
                .accessibilityHint("Calls " + phone)
                .accessibilityIdentifier("provider.action.call")
            }

        case .concierge:
            VStack(spacing: 12) {
                Text("Search \(resolution.name)'s official website or use the number on your account statement. Ask for \(actionKind.noun), and have your account details ready.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(resolution.citations.enumerated()), id: \.offset) { _, citation in
                    if let url = URL(string: citation.url) {
                        Link(citation.title, destination: url)
                            .font(.subheadline.bold())
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                    }
                }
            }
            .accessibilityIdentifier("provider.action.direct_guidance")
        }
    }

    private var actionHeading: String {
        switch resolution.method {
        case .link: "Continue with \(resolution.name)"
        case .call: "Call \(resolution.name)"
        case .concierge: "Here's how to reach them directly"
        }
    }

    private func loadIdentityDetails() async {
        if let identityOverride {
            apply(identity: identityOverride)
            return
        }
        guard !userId.isEmpty,
              let identity = await IdentityService.shared.loadOrMigrate(userId: userId) else {
            identityDetails = ""
            identityMoveDate = nil
            return
        }

        apply(identity: identity)
    }

    private func apply(identity: PeezyIdentity) {
        var lines: [String] = []
        let name = identity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { lines.append("Name: \(name)") }
        if let address = identity.newAddress?.displayLine,
           !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("New address: \(address)")
        }
        if let phone = identity.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phone.isEmpty {
            lines.append("Phone: \(phone)")
        }
        identityDetails = lines.joined(separator: "\n")
        identityMoveDate = identity.moveDate
    }
}

struct ProviderResolutionLoadingCard: View {
    let taskTitle: String
    let providerName: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.bold())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .accessibilityLabel("Cancel provider lookup")
                .accessibilityIdentifier("provider.resolving.back")

                Spacer()

                Text(taskTitle.uppercased())
                    .font(.caption.bold())
                    .tracking(1.5)
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)

            Spacer()

            ProgressView("Checking \(providerName)…")
                .font(.body)
                .tint(PeezyTheme.Colors.deepInk)
                .accessibilityLabel("Checking " + providerName + " for an official action")
                .accessibilityIdentifier("provider.resolving.progress")

            Spacer()
        }
        .accessibilityIdentifier("provider.resolving.card")
    }
}

private struct ProviderSafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ProviderSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
