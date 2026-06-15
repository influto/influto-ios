import SwiftUI
import StoreKit
import InfluTo

/// The whole sample flow, top to bottom — a copy-paste reference for integrators:
/// 1 configure → 2 attribution → 3 referral input → 4 paywall (StoreKit 2 purchase
/// → reportPurchase) → 5 confirm it landed in InfluTo.
struct ContentView: View {
    @EnvironmentObject var config: SampleConfig
    @StateObject private var vm = SampleViewModel()
    @StateObject private var store = PurchaseManager()

    var body: some View {
        NavigationStack {
            Form {
                configSection
                if vm.initialized {
                    attributionSection
                    referralSection
                    paywallSection
                    resultSection
                    autoCaptureSection
                }
                aboutSection
            }
            .navigationTitle("InfluTo Sample")
        }
    }

    // MARK: 1 · Configuration

    private var configSection: some View {
        Section {
            field("InfluTo API key", text: $config.apiKey, secure: true,
                  placeholder: "it_live_… or it_test_…")
            field("Product ID (SKU)", text: $config.productID,
                  placeholder: SampleConfig.defaultProductID)
            field("App user ID", text: $config.appUserID, placeholder: "app user id")
            Button {
                Task {
                    await vm.initialize(config: config)
                    if vm.initialized {
                        let uid = config.appUserID
                        store.startListening(appUserID: { uid })
                        await store.loadProducts(ids: [config.productID])
                    }
                }
            } label: {
                Label(vm.initialized ? "Re-initialize" : "Initialize SDK", systemImage: "play.circle")
            }
            Text(vm.statusLine)
                .font(.caption)
                .foregroundColor(vm.initialized ? .green : .secondary)
        } header: {
            Text("1 · Configuration")
        } footer: {
            Text("Your key is stored on-device only (UserDefaults) and never committed. Get it from the InfluTo dashboard → your app → API key.")
        }
    }

    // MARK: 2 · Attribution

    private var attributionSection: some View {
        Section("2 · Attribution") {
            LabeledContent("Attribution", value: vm.attribution)
            if let code = vm.appliedCode { LabeledContent("Stored code", value: code) }
        }
    }

    // MARK: 3 · Referral input

    private var referralSection: some View {
        Section("3 · Referral code (test attribution)") {
            Text("A · Prebuilt SDK component").font(.caption).foregroundColor(.secondary)
            InfluToReferralCodeInput(appUserId: config.appUserID) { _ in
                Task { vm.appliedCode = await InfluTo.getReferralCode() }
            }
            Divider()
            Text("B · Custom (build your own UI)").font(.caption).foregroundColor(.secondary)
            ReferralCodeField(appliedCode: $vm.appliedCode, appUserID: config.appUserID)
        }
    }

    // MARK: 4 · Paywall

    private var paywallSection: some View {
        Section {
            if store.products.isEmpty {
                Text("Loading products…").foregroundColor(.secondary)
            }
            ForEach(store.products, id: \.id) { product in
                Button {
                    let uid = config.appUserID
                    let code = vm.appliedCode
                    Task { _ = await store.purchase(product, appUserID: uid, referralCode: code) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.displayName)
                            Text(product.description).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if store.purchasedProductIDs.contains(product.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else {
                            Text(product.displayPrice).bold()
                        }
                    }
                }
                .disabled(store.isWorking || store.purchasedProductIDs.contains(product.id))
            }
        } header: {
            Text("4 · Paywall")
        } footer: {
            Text("Buys via StoreKit 2 (sandbox / StoreKit Testing), then calls InfluTo.reportPurchase with the signed transaction.")
        }
    }

    // MARK: 5 · Result

    private var resultSection: some View {
        Section("5 · Result") {
            if !store.lastResult.isEmpty { Text(store.lastResult).font(.callout) }
            Button {
                Task { await vm.checkLanded(config: config) }
            } label: {
                Label("Did it land in InfluTo?", systemImage: "checkmark.shield")
            }
            .disabled(vm.checking)
            if vm.checking { ProgressView() }
            if !vm.landedSummary.isEmpty {
                Text(vm.landedSummary).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 6 · Auto-capture (opt-in)

    private var autoCaptureSection: some View {
        Section {
            Button {
                Task { await vm.backSync() }
            } label: {
                Label("Back-sync existing purchases", systemImage: "arrow.triangle.2.circlepath")
            }
            if !vm.syncSummary.isEmpty {
                Text(vm.syncSummary).font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Text("6 · Auto-capture (default)")
        } footer: {
            Text("For store-direct apps the SDK auto-reports purchases on init — no manual reportPurchase needed (set autoCapture:false to opt out). This button runs an on-demand back-sync. Returns {fetched, sent, failed}.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Best-practice InfluTo integration: initialize → identify → attribution → referral input → StoreKit 2 purchase → reportPurchase → confirm it landed. Copy these patterns into your app.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, secure: Bool = false, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
        }
    }
}
