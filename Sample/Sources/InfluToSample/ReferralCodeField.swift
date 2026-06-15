import SwiftUI
import InfluTo

/// Best-practice referral-code input (per the cross-platform UX spec):
/// a collapsed "Have a referral code?" disclosure → field (auto-uppercase, no
/// autocorrect, charset-filtered) → debounced live validation → explicit Apply →
/// an "applied" chip with Remove. Never blocks or annoys organic users.
struct ReferralCodeField: View {
    @Binding var appliedCode: String?
    let appUserID: String

    @State private var expanded = false
    @State private var text = ""
    @State private var state: FieldState = .idle
    @State private var info = ""
    @State private var task: Task<Void, Never>?

    enum FieldState: Equatable { case idle, validating, valid, applied, invalid }

    var body: some View {
        if let applied = appliedCode {
            HStack(alignment: .top) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                VStack(alignment: .leading) {
                    Text("Code \(applied) applied").font(.subheadline)
                    if !info.isEmpty { Text(info).font(.caption).foregroundColor(.secondary) }
                }
                Spacer()
                Button("Remove", role: .destructive) { remove() }.font(.caption)
            }
        } else if !expanded {
            Button { expanded = true } label: {
                Label("Have a referral code?", systemImage: "tag").font(.subheadline)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("REFERRAL CODE", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode)
                        .submitLabel(.done)
                        .onChange(of: text) { newValue in normalizeAndValidate(newValue) }
                        .onSubmit { apply() }
                    statusIcon
                    Button("Apply") { apply() }.disabled(state != .valid)
                }
                if !info.isEmpty {
                    Text(info).font(.caption)
                        .foregroundColor(state == .invalid ? .red : .green)
                }
            }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch state {
        case .validating: ProgressView()
        case .valid: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .invalid: Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        default: Color.clear.frame(width: 1, height: 1)
        }
    }

    private func normalizeAndValidate(_ raw: String) {
        // Uppercase + strip to [A-Z0-9-]. Re-assigning text re-triggers onChange
        // with normalized == raw, which then proceeds.
        let normalized = String(raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" })
        if normalized != raw { text = normalized; return }

        task?.cancel()
        info = ""
        guard normalized.count >= 3 else { state = .idle; return }
        state = .validating
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)   // debounce
            if Task.isCancelled { return }
            let res = await InfluTo.validateCode(normalized)
            if Task.isCancelled { return }
            if res.valid {
                state = .valid
                if let name = res.campaign?.name { info = "Valid — \(name)" } else { info = "Valid code" }
            } else {
                state = .invalid
                info = res.errorCode == "CODE_EXPIRED"
                    ? "This code has expired"
                    : (res.error ?? "This code isn't valid")
            }
        }
    }

    private func apply() {
        guard state == .valid else { return }
        let code = text
        Task { @MainActor in
            let res = await InfluTo.applyCode(code, appUserId: appUserID)
            if res.applied == true || res.valid {
                appliedCode = code
                if let name = res.campaign?.name { info = "via \(name)" } else { info = "" }
                state = .applied
                expanded = false
            } else {
                state = .invalid
                info = res.error ?? "Could not apply code"
            }
        }
    }

    private func remove() {
        Task { await InfluTo.clearAttribution() }
        appliedCode = nil
        text = ""
        state = .idle
        info = ""
        expanded = false
    }
}
