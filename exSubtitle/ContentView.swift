//
//  ContentView.swift
//  ExSubtitle
//

import SwiftUI
import AppKit
import CoreGraphics
import Combine
import UniformTypeIdentifiers
import Foundation
import MediaRemoteAdapter

// MARK: - 1. MODEL ĐỌC FILE .SRT
struct SubtitleItem {
    let startMs: Int
    let endMs: Int
    let text: String
}

class SubtitleManager: ObservableObject {
    @Published var currentText: String = NSLocalizedString("Open .srt file to start load subtitle", comment: "Initial status message")
    @Published var isPlaying: Bool = false
    @Published var timeOffsetMs: Int = 0
    @Published var debugTimeStr: String = "00:00"
    
    private var subtitles: [SubtitleItem] = []
    
    private var currentPositionMs: Double = 0.0
    private var internalTimer: Timer?
    private var lastSystemTime: TimeInterval = 0
    
    private let mediaController = MediaController()
    private var appNapActivityToken: NSObjectProtocol?

    init() {
        setupMediaRemoteListener()
        preventAppNap()
    }

    private func preventAppNap() {
        appNapActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Synchronize subtitles in real time with the TV app."
        )
    }

    private func setupMediaRemoteListener() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                guard let info = trackInfo else {
                    self.isPlaying = false
                    return
                }
                
                let previouslyPlaying = self.isPlaying
                self.isPlaying = info.payload.isPlaying ?? false
                
                if let elapsedSeconds = info.payload.currentElapsedTime {
                    let realPosMs = elapsedSeconds * 1000.0
                    
                    if abs(self.currentPositionMs - realPosMs) > 200 || !self.isPlaying {
                        self.currentPositionMs = realPosMs
                    }
                    
                    self.lastSystemTime = ProcessInfo.processInfo.systemUptime
                    
                    let sec = Int(realPosMs / 1000)
                    self.debugTimeStr = String(format: "%02d:%02d", sec / 60, sec % 60)
                }
                
                if !previouslyPlaying && self.isPlaying && self.currentText.contains("Waiting to play the movie") {
                    self.currentText = ""
                }
                
                self.updateSub()
            }
        }

        mediaController.startListening()
        startInternalTimer()
    }

    private func startInternalTimer() {
        internalTimer?.invalidate()
        internalTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isPlaying {
                let now = ProcessInfo.processInfo.systemUptime
                if self.lastSystemTime > 0 {
                    let deltaMs = (now - self.lastSystemTime) * 1000.0
                    if deltaMs > 0 && deltaMs < 200 {
                        self.currentPositionMs += deltaMs
                    }
                }
                self.lastSystemTime = now
                self.updateSub()
            }
        }
    }

    private func updateSub() {
        let posInt = Int(self.currentPositionMs)
        let effectiveTime = posInt - timeOffsetMs
        
        if let match = subtitles.first(where: { $0.startMs <= effectiveTime && effectiveTime <= $0.endMs }) {
            if self.currentText != match.text {
                DispatchQueue.main.async {
                    self.currentText = match.text
                }
            }
        } else {
            if !self.subtitles.isEmpty && posInt > 0 {
                if !self.currentText.isEmpty && !self.currentText.contains(NSLocalizedString("Subtitle has been loaded", comment: "")) {
                    DispatchQueue.main.async {
                        self.currentText = ""
                    }
                }
            }
        }
    }

    func loadSRT(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalizedContent.components(separatedBy: "\n\n")
        var parsed: [SubtitleItem] = []
        
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                             .components(separatedBy: "\n")
                             .map { $0.trimmingCharacters(in: .whitespaces) }
                             .filter { !$0.isEmpty }
            
            if let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) {
                let times = lines[timeIndex].components(separatedBy: "-->")
                if times.count == 2,
                   let start = parseTime(times[0]),
                   let end = parseTime(times[1]) {
                    
                    let textLines = Array(lines[(timeIndex + 1)...])
                    
                    if !textLines.isEmpty {
                        let fullText = textLines.joined(separator: "\n")
                        parsed.append(SubtitleItem(startMs: start, endMs: end, text: fullText))
                    }
                }
            }
        }
        self.subtitles = parsed
        let delayInfo = timeOffsetMs != 0 ? "(Delay \(timeOffsetMs)ms)" : ""
        self.currentText = NSLocalizedString("Subtitle has been loaded", comment: "") + " \(delayInfo)"
    }

    private func parseTime(_ timeStr: String) -> Int? {
        let cleanStr = timeStr.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = cleanStr.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return Int((hours * 3600 + minutes * 60 + seconds) * 1000)
    }

    func adjustOffset(by ms: Int) {
        timeOffsetMs += ms
    }
}

// MARK: - 2. COMPONENT HIỂN THỊ CHỮ VIỀN ĐEN SẮC NÉT
struct HTMLStrokeText: View {
    let rawText: String
    let fontSize: CGFloat
    
    @AppStorage("selectedFontFamily") private var selectedFontFamily: String = "Helvetica Neue"
    @AppStorage("selectedFontWeight") private var selectedFontWeight: String = "Bold"

    private var customNSFont: NSFont {
        let weightOption = FontWeightOption(rawValue: selectedFontWeight) ?? .regular
        var fontDescriptor = NSFontDescriptor(fontAttributes: [.family: selectedFontFamily])
        
        var traits: NSFontDescriptor.SymbolicTraits = []
        if weightOption == .bold || weightOption == .heavy {
            traits.insert(.bold)
        }
        
        if !traits.isEmpty {
            fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
        }
        
        fontDescriptor = fontDescriptor.addingAttributes([
            .traits: [NSFontDescriptor.TraitKey.weight: weightOption.nsWeight]
        ])
        
        return NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: weightOption.nsWeight)
    }

    var attributedString: AttributedString {
        var cleanRawText = rawText
        
        if selectedFontWeight == FontWeightOption.regular.rawValue {
            cleanRawText = cleanRawText.replacingOccurrences(of: "<b>", with: "", options: .caseInsensitive)
                                       .replacingOccurrences(of: "</b>", with: "", options: .caseInsensitive)
                                       .replacingOccurrences(of: "<strong>", with: "", options: .caseInsensitive)
                                       .replacingOccurrences(of: "</strong>", with: "", options: .caseInsensitive)
        }
        
        let htmlData = Data(cleanRawText.utf8)
        if let nsAttributedString = try? NSMutableAttributedString(
            data: htmlData,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) {
            let range = NSRange(location: 0, length: nsAttributedString.length)
            
            nsAttributedString.removeAttribute(.font, range: range)
            nsAttributedString.addAttributes([
                .font: customNSFont,
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black,
                .strokeWidth: -3.5
            ], range: range)
            
            return AttributedString(nsAttributedString)
        }
        
        var fallback = AttributedString(cleanRawText)
        fallback.font = .system(size: fontSize)
        fallback.foregroundColor = .white
        return fallback
    }

    var body: some View {
        Text(attributedString)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .minimumScaleFactor(0.5)
            .shadow(color: .black, radius: 1, x: 0, y: 1)
    }
}

// MARK: - 3. GIAO DIỆN SWIFTUI TRONG SUỐT
struct ContentView: View {
    @EnvironmentObject var subManager: SubtitleManager
    private var defaultDelayMs: Int = 0
    @AppStorage("fontSizeRatio") private var fontSizeRatio: Double = 0.02
    @AppStorage("backgroundStyle") private var backgroundStyle: String = BackgroundStyleOption.transparent.rawValue
    @AppStorage("bottomOffset") private var bottomOffset: Double = 0.02
    
    @State private var tvWindowSize: CGSize = CGSize(width: 800, height: 450)

    var body: some View {
        let calculatedFontSize = max(14, tvWindowSize.width * fontSizeRatio)

        VStack {
            Spacer()
            HTMLStrokeText(rawText: subManager.currentText, fontSize: calculatedFontSize)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if backgroundStyle == BackgroundStyleOption.blur.rawValue && !subManager.currentText.isEmpty {
                            ZStack {
                                    VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                                    Color.black.opacity(0.1) // Phủ thêm màu đen mờ nhẹ
                                }
                                .cornerRadius(8)
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(8)
        .background(Color.clear)
        .onAppear {
            makeWindowFloatingAndTransparent()
            startAppleTVWindowDocking()
            requestAccessibilityPermissionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSRTFile)) { _ in
            selectSRTFile()
        }
    }
    
    private func requestAccessibilityPermissionIfNeeded() {
        let isTrusted = AXIsProcessTrusted()
        if isTrusted {
            return
        }
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func selectSRTFile() {
        let panel = NSOpenPanel()
        if #available(macOS 11.0, *) {
            let srtType = UTType(filenameExtension: "srt") ?? .plainText
            panel.allowedContentTypes = [srtType, .plainText]
        } else {
            panel.allowedFileTypes = ["srt", "txt"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            let extractedMs = extractMsFromFilename(url: url) ?? defaultDelayMs
            
            showDelayPrompt(initialValue: extractedMs) { delayMs in
                subManager.timeOffsetMs = delayMs
                subManager.loadSRT(url: url)
            }
        }
    }
    
    private func extractMsFromFilename(url: URL) -> Int? {
        let filename = url.deletingPathExtension().lastPathComponent
        let pattern = #"\((-?\d+)ms\)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: filename, options: [], range: NSRange(location: 0, length: filename.utf16.count)),
              let range = Range(match.range(at: 1), in: filename) else {
            return nil
        }
        
        return Int(filename[range])
    }

    private func showDelayPrompt(initialValue: Int, completion: @escaping (Int) -> Void) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Delay Subtitle (ms)", comment: "")
        alert.informativeText = NSLocalizedString("Enter the subtitle delay/postponement time (milliseconds):\n- POSITIVE number: Later.\n- NEGATIVE number: Earlier.", comment: "")
        alert.alertStyle = .informational
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        inputTextField.stringValue = "\(initialValue)"
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: NSLocalizedString("Use default settings (0ms)", comment: ""))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let delayValue = Int(inputTextField.stringValue) ?? initialValue
            completion(delayValue)
        } else {
            completion(defaultDelayMs)
        }
    }

    private func makeWindowFloatingAndTransparent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask = [.borderless]
                window.level = .floating
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.isMovableByWindowBackground = true
            }
        }
    }

    private func startAppleTVWindowDocking() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let tvRect = getAppleTVWindowRect(),
                  let window = NSApplication.shared.windows.first else { return }

            if self.tvWindowSize != tvRect.size {
                DispatchQueue.main.async {
                    self.tvWindowSize = tvRect.size
                }
            }

            let overlayW: CGFloat = tvRect.width * 0.9
            let overlayH: CGFloat = max(60, tvRect.height * 0.2)
            let overlayX: CGFloat = tvRect.origin.x + (tvRect.width - overlayW) / 2
            
            guard let screenHeight = NSScreen.main?.frame.height else { return }
            
            // 💡 Đọc trực tiếp từ UserDefaults để luôn lấy giá trị mới nhất khi kéo Slider
            let liveBottomOffset = UserDefaults.standard.double(forKey: "bottomOffset")
            let calculatedOffset = tvRect.height * CGFloat(liveBottomOffset)
            
            let overlayY: CGFloat = screenHeight - (tvRect.origin.y + tvRect.height) + calculatedOffset

            let targetFrame = NSRect(x: overlayX, y: overlayY, width: overlayW, height: overlayH)
            window.setFrame(targetFrame, display: true, animate: false)
        }
    }


    private func getAppleTVWindowRect() -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }

        for info in windowInfoList {
            if let ownerName = info[kCGWindowOwnerName as String] as? String,
               (ownerName == "TV" || ownerName == "Apple TV"),
               let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                if rect.width > 300 && rect.height > 200 {
                    return rect
                }
            }
        }
        return nil
    }
}

// MARK: - 4. HELPER CHẾ ĐỘ NỀN MỜ (BLUR EFFECT)
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow // 👈 Dùng Semantic Material thay cho .dark
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        
        // Buộc hiệu ứng hiển thị theo tông tối (Vibrant Dark)
        visualEffectView.appearance = NSAppearance(named: .vibrantDark)
        
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = NSAppearance(named: .vibrantDark)
    }
}

