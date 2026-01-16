//
//  AllergenScanner.swift
//  AllergenScanner
//
//  Created by Chapman, Cole G on 1/16/26.
//

import Foundation // part for default header, delete?

// MARK: - Main App Entry Point
import SwiftUI
import Combine

@main
struct AllergenScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Models
struct Allergen: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isCustom: Bool
    var synonyms: [String]
    
    init(id: UUID = UUID(), name: String, isCustom: Bool = false, synonyms: [String] = []) {
        self.id = id
        self.name = name
        self.isCustom = isCustom
        self.synonyms = synonyms
    }
}

// MARK: - Allergen Manager
class AllergenManager: ObservableObject {
    @Published var selectedAllergens: [Allergen] = []
    
    let commonAllergensWithSynonyms: [String: [String]] = [
        "milk": ["dairy", "lactose", "casein", "whey", "cream", "butter", "cheese", "yogurt", "curd"],
        "eggs": ["egg", "albumin", "ovomucoid", "ovalbumin", "lysozyme", "eggwhite", "eggyolk"],
        "peanuts": ["peanut", "groundnut", "goober", "arachis"],
        "tree nuts": ["almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "pine nut", "chestnut", "beechnut", "butternut", "brazil nut"],
        "soy": ["soya", "soybean", "soybeans", "tofu", "edamame", "miso", "tempeh", "soy lecithin", "textured vegetable protein", "tvp"],
        "wheat": ["gluten", "flour", "bran", "semolina", "durum", "spelt", "farina", "bulgur", "couscous", "kamut"],
        "fish": ["salmon", "tuna", "cod", "halibut", "anchovy", "sardine", "bass", "trout", "mackerel", "tilapia"],
        "shellfish": ["shrimp", "crab", "lobster", "crayfish", "prawn", "clam", "mussel", "oyster", "scallop", "squid", "octopus"],
        "sesame": ["tahini", "sesame seed", "sesame oil", "benne"],
        "gluten": ["wheat", "barley", "rye", "triticale", "malt", "brewer's yeast"],
        "coconut": ["coconut", "cocos nucifera", "sodium cocoate", "coco betaine", "cocamide mipa", "coco glucoside"],
        "annatto": ["annatto", "achiote", "bixin", "norbixin"]
    ]
    
    var commonAllergens: [String] {
        Array(commonAllergensWithSynonyms.keys).sorted()
    }
    
    init() {
        loadAllergens()
    }
    
    func toggleAllergen(_ name: String) {
        if let index = selectedAllergens.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            selectedAllergens.remove(at: index)
        } else {
            let synonyms = commonAllergensWithSynonyms[name.lowercased()] ?? []
            selectedAllergens.append(Allergen(name: name, synonyms: synonyms))
        }
        saveAllergens()
    }
    
    func addCustomAllergen(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedAllergens.contains(where: { $0.name.lowercased() == trimmed.lowercased() }) else { return }
        
        selectedAllergens.append(Allergen(name: trimmed, isCustom: true, synonyms: []))
        saveAllergens()
    }
    
    func removeAllergen(_ allergen: Allergen) {
        selectedAllergens.removeAll { $0.id == allergen.id }
        saveAllergens()
    }
    
    func isSelected(_ name: String) -> Bool {
        selectedAllergens.contains { $0.name.lowercased() == name.lowercased() }
    }
    
    struct AllergenMatch {
        let allergen: String
        let matchType: MatchType
        
        enum MatchType {
            case exact      // Direct match
            case fuzzy      // Close match (Levenshtein distance)
        }
    }
    
    func findAllergens(in text: String) -> [AllergenMatch] {
        let normalizedText = normalizeText(text)
        let words = extractWords(from: normalizedText)
        var matches: [AllergenMatch] = []
        
        for allergen in selectedAllergens {
            let normalizedAllergen = normalizeText(allergen.name)
            let allTermsToCheck = [normalizedAllergen] + allergen.synonyms.map { normalizeText($0) }
            
            var foundExact = false
            var foundFuzzy = false
            
            // Check main allergen name and all synonyms
            for term in allTermsToCheck {
                if hasExactMatch(allergen: term, in: words) {
                    foundExact = true
                    break
                }
            }
            
            if foundExact {
                matches.append(AllergenMatch(allergen: allergen.name, matchType: .exact))
            } else {
                // Check for fuzzy match on main allergen name and synonyms
                for term in allTermsToCheck {
                    if hasFuzzyMatch(allergen: term, in: words) != nil {
                        foundFuzzy = true
                        break
                    }
                }
                
                if foundFuzzy {
                    matches.append(AllergenMatch(allergen: allergen.name, matchType: .fuzzy))
                }
            }
        }
        
        return matches
    }
    
    private func normalizeText(_ text: String) -> String {
        // Remove hyphens, underscores, and convert to lowercase
        return text.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
    
    private func extractWords(from text: String) -> [String] {
        // Split on whitespace and punctuation, filter out empty strings
        let components = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components.filter { !$0.isEmpty }
    }
    
    private func hasExactMatch(allergen: String, in words: [String]) -> Bool {
        let allergenSingular = removePlural(allergen)
        
        for word in words {
            let wordSingular = removePlural(word)
            
            // Check if allergen matches word (considering plural forms)
            if allergen == word || allergenSingular == wordSingular {
                return true
            }
            
            // Check if allergen is contained in word (e.g., "soy" in "soybean")
            if word.contains(allergen) || word.contains(allergenSingular) {
                return true
            }
        }
        
        return false
    }
    
    private func hasFuzzyMatch(allergen: String, in words: [String]) -> String? {
        let allergenSingular = removePlural(allergen)
        let threshold = max(1, allergen.count / 4) // Allow ~25% difference
        
        for word in words {
            let wordSingular = removePlural(word)
            
            // Skip if word is too short or too different in length
            guard word.count >= 3 else { continue }
            guard abs(allergen.count - word.count) <= threshold else { continue }
            
            // Calculate Levenshtein distance
            let distance = levenshteinDistance(allergen, word)
            let distanceSingular = levenshteinDistance(allergenSingular, wordSingular)
            
            if distance <= threshold || distanceSingular <= threshold {
                return word
            }
        }
        
        return nil
    }
    
    private func removePlural(_ word: String) -> String {
        // Simple plural removal (handles most common cases)
        if word.hasSuffix("ies") && word.count > 4 {
            return String(word.dropLast(3)) + "y"
        } else if word.hasSuffix("es") && word.count > 3 {
            return String(word.dropLast(1))
        } else if word.hasSuffix("s") && word.count > 2 {
            return String(word.dropLast())
        }
        return word
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        var dist = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)
        
        for i in 0...s1.count {
            dist[i][0] = i
        }
        
        for j in 0...s2.count {
            dist[0][j] = j
        }
        
        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i-1] == s2[j-1] ? 0 : 1
                dist[i][j] = min(
                    dist[i-1][j] + 1,      // deletion
                    dist[i][j-1] + 1,      // insertion
                    dist[i-1][j-1] + cost  // substitution
                )
            }
        }
        
        return dist[s1.count][s2.count]
    }
    
    private func saveAllergens() {
        if let encoded = try? JSONEncoder().encode(selectedAllergens) {
            UserDefaults.standard.set(encoded, forKey: "selectedAllergens")
        }
    }
    
    private func loadAllergens() {
        if let data = UserDefaults.standard.data(forKey: "selectedAllergens"),
           let decoded = try? JSONDecoder().decode([Allergen].self, from: data) {
            selectedAllergens = decoded
        }
    }
}

// MARK: - Camera View Controller
import AVFoundation
import Vision

class CameraViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onTextDetected: ((String) -> Void)?
    
    private var lastProcessTime: Date = Date()
    private let processingInterval: TimeInterval = 1.0 // Process every 1 second
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        guard let captureSession = captureSession,
              let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        
        if let previewLayer = previewLayer {
            view.layer.addSublayer(previewLayer)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }
    
    func stopCamera() {
        captureSession?.stopRunning()
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Throttle processing
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= processingInterval else { return }
        lastProcessTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: " ")
            
            if !recognizedText.isEmpty {
                DispatchQueue.main.async {
                    self?.onTextDetected?(recognizedText)
                }
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Camera View SwiftUI Wrapper
struct CameraView: UIViewControllerRepresentable {
    @Binding var detectedText: String
    @Binding var isScanning: Bool
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onTextDetected = { text in
            detectedText = text
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        if !isScanning {
            uiViewController.stopCamera()
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var allergenManager: AllergenManager
    @State private var customAllergenText = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Common Allergens")) {
                    ForEach(allergenManager.commonAllergens, id: \.self) { allergen in
                        Button(action: {
                            allergenManager.toggleAllergen(allergen)
                        }) {
                            HStack {
                                Text(allergen.capitalized)
                                    .foregroundColor(.primary)
                                Spacer()
                                if allergenManager.isSelected(allergen) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Custom Allergens")) {
                    HStack {
                        TextField("Add custom allergen", text: $customAllergenText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        Button(action: {
                            allergenManager.addCustomAllergen(customAllergenText)
                            customAllergenText = ""
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .disabled(customAllergenText.isEmpty)
                    }
                    
                    ForEach(allergenManager.selectedAllergens.filter { $0.isCustom }) { allergen in
                        HStack {
                            Text(allergen.name.capitalized)
                            Spacer()
                            Button(action: {
                                allergenManager.removeAllergen(allergen)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Your Allergens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var allergenManager = AllergenManager()
    @State private var isScanning = false
    @State private var showSettings = false
    @State private var detectedText = ""
    @State private var detectedAllergens: [AllergenManager.AllergenMatch] = []
    
    var body: some View {
        ZStack {
            // Camera View
            if isScanning {
                CameraView(detectedText: $detectedText, isScanning: $isScanning)
                    .edgesIgnoringSafeArea(.all)
                    .onChange(of: detectedText) { oldValue, newValue in
                        detectedAllergens = allergenManager.findAllergens(in: newValue)
                    }
                
                // Focus Frame
                GeometryReader { geometry in
                    Rectangle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: geometry.size.width * 0.8,
                               height: geometry.size.height * 0.6)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .opacity(0.5)
                }
            } else {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                        .opacity(0.5)
                    Text("Tap to start scanning")
                        .foregroundColor(.white)
                        .font(.title3)
                        .padding(.top)
                }
            }
            
            VStack {
                // Header
                HStack {
                    Text("Allergen Scanner")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.blue)
                
                // Alert Banner
                if !detectedAllergens.isEmpty {
                    let exactMatches = detectedAllergens.filter { $0.matchType == .exact }
                    let fuzzyMatches = detectedAllergens.filter { $0.matchType == .fuzzy }
                    
                    if !exactMatches.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allergens Detected!")
                                    .font(.headline)
                                Text("Found: \(exactMatches.map { $0.allergen }.joined(separator: ", "))")
                                    .font(.subheadline)
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    if !fuzzyMatches.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Possible Allergens")
                                    .font(.headline)
                                Text("Similar to: \(fuzzyMatches.map { $0.allergen }.joined(separator: ", "))")
                                    .font(.subheadline)
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, exactMatches.isEmpty ? 8 : 4)
                    }
                } else if isScanning && !detectedText.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Safe to Eat!")
                                .font(.headline)
                            Text("No allergens detected")
                                .font(.subheadline)
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // Detected Text Display
                if !detectedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected Text:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(detectedText)
                            .font(.caption)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.white)
                }
                
                // Control Buttons
                HStack(spacing: 12) {
                    if isScanning {
                        Button(action: {
                            isScanning = false
                            detectedText = ""
                            detectedAllergens = []
                        }) {
                            Text("Stop Scanning")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    } else {
                        Button(action: { isScanning = true }) {
                            Text("Start Scanning")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
                .background(Color.white)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(allergenManager: allergenManager)
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
