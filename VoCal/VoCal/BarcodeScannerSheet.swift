//
//  BarcodeScannerSheet.swift
//  VoCal
//
//  Live AVFoundation barcode scanner. Points the rear camera at a product,
//  detects UPC-A / UPC-E / EAN-8 / EAN-13 / GTIN-14, hits
//  vocal.best/api/barcode/:code (which proxies Open Food Facts), and drops
//  the resolved meal straight into AppModel.
//
//  Falls back gracefully on the simulator (no rear camera) — shows a manual
//  entry field so the demo flow still works.
//

import SwiftUI
import AVFoundation
import UIKit

// MARK: - Sheet

struct BarcodeScannerSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var scanned: String?
    @State private var manualCode: String = ""
    @State private var lookingUp = false
    @State private var error: String?
    @State private var resolvedMeal: MealEntry?
    @State private var lastReasoning: String?

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 16)
                Group {
                    if let meal = resolvedMeal {
                        resultView(meal: meal)
                    } else if lookingUp {
                        loadingView
                    } else if let code = scanned {
                        confirmCodeView(code: code)
                    } else {
                        scannerView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BARCODE")
                    .eyebrow(Theme.Palette.pulse)
                Text(resolvedMeal == nil ? "Point at the package." : resolvedMeal!.name)
                    .font(Theme.Font.serif(28, weight: .medium))
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(2)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ash)
                    .frame(width: 30, height: 30)
                    .background(Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var scannerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LIVE CAMERA")
                .eyebrow()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .frame(height: 320)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    )
                BarcodeCameraView { code in
                    scanned = code
                    lookUp(code: code)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(height: 320)
                // Reticle
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.Palette.voltage, lineWidth: 1.5)
                    .frame(width: 220, height: 96)
                    .shadow(color: Theme.Palette.voltage.opacity(0.4), radius: 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("OR TYPE THE CODE")
                    .eyebrow()
                HStack(spacing: 10) {
                    TextField(
                        "",
                        text: $manualCode,
                        prompt: Text("e.g. 0049000028058").foregroundStyle(Theme.Palette.smoke)
                    )
                    .keyboardType(.numberPad)
                    .foregroundStyle(Theme.Palette.bone)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Palette.inkSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                    .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                            )
                    )
                    VoltageButton(title: "Look up", icon: "arrow.right") {
                        let code = manualCode.trimmingCharacters(in: .whitespaces)
                        guard !code.isEmpty else { return }
                        scanned = code
                        lookUp(code: code)
                    }
                }
            }
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.pulse)
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.Palette.voltage).controlSize(.small)
            Text("Looking up in Open Food Facts…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.smoke)
        }
    }

    private func confirmCodeView(code: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCANNED")
                .eyebrow()
            Text(code).font(Theme.Font.serif(28, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
                .monospacedDigit()
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.Palette.pulse)
            }
        }
    }

    private func resultView(meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayNumber(value: meal.calories, label: "calories")
            HStack(spacing: 10) {
                MacroPill(letter: "P", value: meal.protein, tint: Theme.Palette.protein)
                MacroPill(letter: "C", value: meal.carbs, tint: Theme.Palette.carbs)
                MacroPill(letter: "F", value: meal.fat, tint: Theme.Palette.fat)
                Spacer()
            }
            Text(meal.detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.ash)
            if let r = lastReasoning {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOURCE").eyebrow()
                    Text(r).font(.system(size: 12)).foregroundStyle(Theme.Palette.smoke)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let meal = resolvedMeal {
                GhostButton(title: "Scan another") {
                    resolvedMeal = nil
                    scanned = nil
                    manualCode = ""
                    error = nil
                }
                VoltageButton(title: "Save meal", icon: "checkmark") {
                    appModel.addMeal(meal)
                    dismiss()
                }
            } else if scanned != nil && !lookingUp {
                GhostButton(title: "Re-scan") {
                    scanned = nil
                    manualCode = ""
                    error = nil
                }
            } else {
                GhostButton(title: "Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Lookup

    private func lookUp(code: String) {
        Task {
            lookingUp = true
            error = nil
            defer { lookingUp = false }
            do {
                let (meal, source) = try await BarcodeAPI.lookup(code: code)
                resolvedMeal = MealEntry(
                    name: meal.name,
                    detail: meal.detail,
                    calories: meal.kcal,
                    protein: meal.protein_g,
                    carbs: meal.carbs_g,
                    fat: meal.fat_g,
                    loggedAt: .now,
                    slot: MealEntry.Slot(rawValue: meal.slot) ?? .snack,
                    source: .barcode
                )
                lastReasoning = "Resolved via \(source). Code \(code)."
            } catch BarcodeAPI.Error.notFound {
                // Reset `scanned` so the camera reticle comes back rather
                // than the user being stuck on the "Re-scan" footer with
                // a long-faded error message and no way to retry without
                // dismissing and re-opening the whole sheet.
                scanned = nil
                error = "Couldn't find that barcode. Try voice or photo logging."
            } catch {
                scanned = nil
                self.error = "Lookup failed. \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - AVFoundation camera wrapper

struct BarcodeCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerVC {
        let vc = BarcodeScannerVC()
        vc.onCode = onCode
        return vc
    }
    func updateUIViewController(_ uiViewController: BarcodeScannerVC, context: Context) {}
}

final class BarcodeScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReported = false
    /// Background queue used for session start/stop so we don't block the
    /// main thread (Apple recommends both calls run off-main; `stopRunning`
    /// can otherwise hang for the duration of the camera shutdown ~200ms).
    private let sessionQueue = DispatchQueue(label: "vocal.barcode.session", qos: .userInitiated)
    private var didConfigure = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasReported = false
        sessionQueue.async { [weak self] in
            guard let self, self.didConfigure, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Off-main: `stopRunning` synchronously waits for the camera capture
        // pipeline to flush, which can spin the main thread and leave the
        // green camera indicator lit in the status bar longer than needed.
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    deinit {
        // Belt-and-braces: if the view disappears for any reason we haven't
        // handled, ensure the AVCaptureSession is torn down so the camera
        // hardware (and the green "camera in use" indicator) is released.
        let session = self.session
        DispatchQueue.global(qos: .utility).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestAccessAndConfigure() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                        self.sessionQueue.async {
                            if self.didConfigure && !self.session.isRunning {
                                self.session.startRunning()
                            }
                        }
                    } else {
                        self.showFallbackLabel(text: "Camera access denied.\nUse manual entry below.")
                    }
                }
            }
        case .denied, .restricted:
            showFallbackLabel(text: "Camera access denied.\nUse manual entry below.")
        @unknown default:
            showFallbackLabel(text: "Camera unavailable.\nUse manual entry below.")
        }
    }

    private func showFallbackLabel(text: String) {
        let label = UILabel(frame: view.bounds)
        label.text = text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = UIColor(white: 1.0, alpha: 0.4)
        label.font = .systemFont(ofSize: 13)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            // Simulator / device with no camera — show placeholder text.
            showFallbackLabel(text: "Camera unavailable.\nUse manual entry below.")
            return
        }
        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            // Keep QR/PDF417 in the type set (some warehouse demos use them),
            // but we filter non-numeric payloads out in the callback so the
            // resolver never gets a URL or other non-barcode string.
            output.metadataObjectTypes = [
                .ean8, .ean13, .upce, .code128, .code39, .code93, .qr, .pdf417, .interleaved2of5
            ].filter { output.availableMetadataObjectTypes.contains($0) }
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
        didConfigure = true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasReported,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = obj.stringValue else { return }
        // Some scanned codes (QR especially) come back with URL prefixes or
        // human text. The food-barcode resolver only accepts 8-14 digit
        // payloads, so strip everything else and validate length before we
        // bother firing a network call.
        let digits = stringValue.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
        guard (8...14).contains(digits.count) else { return }
        hasReported = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCode?(digits)
    }
}

// MARK: - API client
//
// Resolution order:
//   1. VoCal backend (USDA Branded via FDC). Worker also tries Open Food
//      Facts but OFF returns 525 to Cloudflare-Workers traffic so the OFF
//      side never succeeds on the backend.
//   2. Direct Open Food Facts (works fine from a mobile client, which is
//      not on Cloudflare).
//   3. Throws .notFound if neither has the code.

enum BarcodeAPI {
    enum Error: Swift.Error, LocalizedError {
        case badResponse
        case notFound
        case server(String)
        var errorDescription: String? {
            switch self {
            case .badResponse: "Bad response."
            case .notFound:    "Barcode not found."
            case .server(let s): s
            }
        }
    }

    struct ParsedMealDTO: Codable {
        var name: String
        var detail: String
        var kcal: Int
        var protein_g: Int
        var carbs_g: Int
        var fat_g: Int
        var slot: String
        var source: String
        var confidence: Double
    }
    private struct BackendResponse: Codable { let meal: ParsedMealDTO; let source: String }
    private struct ErrorBody: Codable { let error: String? }

    static func lookup(code: String) async throws -> (ParsedMealDTO, String) {
        // Normalize: strip whitespace + non-digits so manually-typed entries
        // with hyphens or spaces still hit the resolvers (which require
        // 8-14 digit codes).
        let normalized = code.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map { String($0) }
            .joined()
        guard (8...14).contains(normalized.count) else {
            throw Error.notFound
        }
        // 1. Backend (USDA Branded).
        if let meal = try? await fetchBackend(code: normalized) {
            return meal
        }
        // 2. Open Food Facts direct from iOS — works because we're not on CF.
        if let meal = try? await fetchOpenFoodFacts(code: normalized) {
            return meal
        }
        throw Error.notFound
    }

    private static func fetchBackend(code: String) async throws -> (ParsedMealDTO, String) {
        guard let url = URL(string: "\(APIConfig.baseURL)/barcode/\(code)") else {
            throw Error.badResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        await AuthSession.shared.authorize(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }
        if http.statusCode == 404 { throw Error.notFound }
        if !(200..<300).contains(http.statusCode) {
            let body = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Error.server(body)
        }
        let parsed = try JSONDecoder().decode(BackendResponse.self, from: data)
        return (parsed.meal, parsed.source)
    }

    private struct OFFNutriments: Codable {
        var energy_kcal_serving: Double?
        var energy_kcal_100g: Double?
        var proteins_serving: Double?
        var proteins_100g: Double?
        var carbohydrates_serving: Double?
        var carbohydrates_100g: Double?
        var fat_serving: Double?
        var fat_100g: Double?
        enum CodingKeys: String, CodingKey {
            case energy_kcal_serving = "energy-kcal_serving"
            case energy_kcal_100g = "energy-kcal_100g"
            case proteins_serving, proteins_100g
            case carbohydrates_serving, carbohydrates_100g
            case fat_serving, fat_100g
        }
    }
    private struct OFFProduct: Codable {
        var status: Int
        var product: Inner?
        struct Inner: Codable {
            var product_name: String?
            var product_name_en: String?
            var brands: String?
            var quantity: String?
            var serving_size: String?
            var serving_quantity: ServingQuantity?
            var nutriments: OFFNutriments?
        }
        // OFF returns serving_quantity as either a number or a numeric string.
        enum ServingQuantity: Codable {
            case number(Double)
            case string(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Double.self) { self = .number(n) }
                else if let s = try? c.decode(String.self) { self = .string(s) }
                else { self = .number(0) }
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .number(let n): try c.encode(n)
                case .string(let s): try c.encode(s)
                }
            }
            var value: Double {
                switch self {
                case .number(let n): return n
                case .string(let s): return Double(s) ?? 0
                }
            }
        }
    }

    private static func fetchOpenFoodFacts(code: String) async throws -> (ParsedMealDTO, String) {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,product_name_en,brands,quantity,serving_size,serving_quantity,nutriments") else {
            throw Error.badResponse
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("VoCal/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Error.badResponse
        }
        let off = try JSONDecoder().decode(OFFProduct.self, from: data)
        guard off.status == 1, let p = off.product, let n = p.nutriments else {
            throw Error.notFound
        }
        let servingG = p.serving_quantity?.value ?? 100
        let scale = servingG > 0 ? servingG / 100 : 1
        let pick: (Double?, Double?) -> Int = { perServing, per100 in
            if let v = perServing, v.isFinite, v > 0 { return Int(v.rounded()) }
            if let v = per100, v.isFinite, v > 0 { return Int((v * scale).rounded()) }
            return 0
        }
        let kcal = pick(n.energy_kcal_serving, n.energy_kcal_100g)
        guard kcal > 0 else { throw Error.notFound }
        let brand = p.brands?
            .split(separator: ",").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        let productName = (p.product_name_en ?? p.product_name)?
            .trimmingCharacters(in: .whitespaces)
        // Filter out empty/whitespace-only fragments so we never end up with
        // "Coca-Cola · " or " · Apple Juice" — both ugly and load-bearing
        // since this becomes the meal name in HealthKit and the day log.
        let nameParts = [brand, productName].compactMap { $0?.isEmpty == false ? $0 : nil }
        let name = nameParts.joined(separator: " · ")
        let detail = (p.serving_size ?? p.quantity ?? "barcode \(code)")
        let meal = ParsedMealDTO(
            name: name.isEmpty ? "Barcode \(code)" : String(name.prefix(80)),
            detail: String(detail.prefix(120)),
            kcal: kcal,
            protein_g: pick(n.proteins_serving, n.proteins_100g),
            carbs_g: pick(n.carbohydrates_serving, n.carbohydrates_100g),
            fat_g: pick(n.fat_serving, n.fat_100g),
            slot: "snack",
            source: "barcode",
            confidence: 0.90
        )
        return (meal, "openfoodfacts-direct")
    }
}

#Preview {
    BarcodeScannerSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: [],
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
