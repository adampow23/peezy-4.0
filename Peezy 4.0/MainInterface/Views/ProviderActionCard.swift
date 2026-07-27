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

    var noun: String {
        switch self {
        case .addressChange: "address change"
        case .cancellation: "cancellation"
        }
    }

    var callScript: String {
        switch self {
        case .addressChange:
            "Hi, I'm calling to update the address on my account to my new address."
        case .cancellation:
            "Hi, I'm calling to cancel my membership. Please confirm the effective date and any final charge."
        }
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

    @Environment(\.openURL) private var openURL
    @State private var safariDestination: ProviderSafariDestination?
    @State private var identityDetails = ""
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
            EmptyView()
        }
    }

    private var actionHeading: String {
        switch resolution.method {
        case .link: "Continue with \(resolution.name)"
        case .call: "Call \(resolution.name)"
        case .concierge: "We'll take it from here"
        }
    }

    private func loadIdentityDetails() async {
        guard !userId.isEmpty,
              let identity = await IdentityService.shared.loadOrMigrate(userId: userId) else {
            identityDetails = ""
            return
        }

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
