#if canImport(SwiftUI)
import SwiftUI

/// Pre-built, configurable referral-code input.
///
/// Validates live (debounced) as the user types, applies on the button. By default it
/// shows ONLY the field + a valid/invalid state — the campaign name and the influencer's
/// personal name are hidden unless `showCampaignName` / `showReferrerName` are set (both
/// default `false`, consistent across the InfluTo SDKs). For full control, build your own
/// UI and call `InfluTo.validateCode` / `InfluTo.applyCode` directly.
///
/// ```swift
/// InfluToReferralCodeInput(appUserId: "user_123") { result in
///     // result.applied == true -> code applied
/// }
/// ```
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct InfluToReferralCodeInput: View {
    /// Customizable text labels.
    public struct Labels: Sendable {
        public var placeholder = "Referral code"
        public var apply = "Apply"
        public var valid = "Code applied"
        public var invalid = "This code isn't valid"
        public init() {}
    }

    private let appUserId: String?
    private let autoPrefill: Bool
    private let autoValidate: Bool
    private let showCampaignName: Bool
    private let showReferrerName: Bool
    private let title: String?
    private let labels: Labels
    private let onValidated: ((CodeValidationResult) -> Void)?
    private let onApplied: ((CodeValidationResult) -> Void)?

    public init(
        appUserId: String? = nil,
        autoPrefill: Bool = true,
        autoValidate: Bool = false,
        showCampaignName: Bool = false,
        showReferrerName: Bool = false,
        title: String? = nil,
        labels: Labels = Labels(),
        onValidated: ((CodeValidationResult) -> Void)? = nil,
        onApplied: ((CodeValidationResult) -> Void)? = nil
    ) {
        self.appUserId = appUserId
        self.autoPrefill = autoPrefill
        self.autoValidate = autoValidate
        self.showCampaignName = showCampaignName
        self.showReferrerName = showReferrerName
        self.title = title
        self.labels = labels
        self.onValidated = onValidated
        self.onApplied = onApplied
    }

    private enum Status: Equatable { case idle, validating, valid, invalid, applied }

    @State private var code = ""
    @State private var status: Status = .idle
    @State private var result: CodeValidationResult?
    @State private var debounce: Task<Void, Never>?

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }

            HStack {
                TextField(labels.placeholder, text: $code)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onChange(of: code) { newValue in onCodeChange(newValue) }
                    .onSubmit { apply() }
                    .modifier(PlatformInputStyle())
                statusIcon
            }

            if let info = message {
                Text(info.text).font(.caption).foregroundColor(info.color)
            }

            Button(labels.apply) { apply() }
                .disabled(status != .valid)

            if status == .applied {
                if showCampaignName, let name = result?.campaign?.name {
                    Text(name).font(.subheadline.bold())
                }
                if showReferrerName, let inf = result?.influencer {
                    Text("Referred by \(inf.name)").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .task { if autoPrefill { await prefill() } }
    }

    @ViewBuilder private var statusIcon: some View {
        switch status {
        case .validating: ProgressView()
        case .valid, .applied: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .invalid: Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .idle: EmptyView()
        }
    }

    private var message: (text: String, color: Color)? {
        switch status {
        case .valid, .applied: return (labels.valid, .green)
        case .invalid: return (result?.error ?? labels.invalid, .red)
        default: return nil
        }
    }

    private func onCodeChange(_ raw: String) {
        let normalized = String(raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" })
        if normalized != raw { code = normalized; return }
        debounce?.cancel()
        guard normalized.count >= 3 else { status = .idle; return }
        status = .validating
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            let r = await InfluTo.validateCode(normalized)
            if Task.isCancelled { return }
            result = r
            onValidated?(r)
            status = r.valid ? .valid : .invalid
        }
    }

    private func prefill() async {
        if let c = await InfluTo.getPrefilledCode() {
            code = c
            if autoValidate { onCodeChange(c) }
        }
    }

    private func apply() {
        guard status == .valid else { return }
        let c = code
        Task { @MainActor in
            let r = await InfluTo.applyCode(c, appUserId: appUserId)
            result = r
            if r.applied == true || r.valid {
                onApplied?(r)
                status = .applied
            } else {
                status = .invalid
            }
        }
    }
}

/// iOS-only text-input modifiers (gated so the package still builds on macOS/tvOS/watchOS).
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
private struct PlatformInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .textInputAutocapitalization(.characters)
            .keyboardType(.asciiCapable)
        #else
        content
        #endif
    }
}
#endif
