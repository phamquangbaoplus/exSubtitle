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
                    self.currentText = ""
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSRTFile)) { _ in
            selectSRTFile()
        }
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
    
    
    
    // 💡 Hàm phụ trợ kiểm tra Full Screen
    private func checkIfAppleTVIsFullScreen(tvRect: CGRect) -> Bool {
        let currentScreen = NSScreen.screens.first(where: { $0.frame.intersects(tvRect) }) ?? NSScreen.main
        guard let screenSize = currentScreen?.frame.size else { return false }
        
        return abs(tvRect.width - screenSize.width) < 15 && abs(tvRect.height - screenSize.height) < 15
    }
    
    
    // MARK: - 1. Setup Cửa sổ Floating chuẩn
    private func makeWindowFloatingAndTransparent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask = [.borderless]
                
                // Cấu hình đè Space Fullscreen
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.level = .mainMenu
                
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.isMovableByWindowBackground = true
            }
        }
    }
    
    // MARK: - 2. Timer bám đuổi & Kiểm tra che lấp thông minh
    private func startAppleTVWindowDocking() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let window = NSApplication.shared.windows.first else { return }
            
            // 💡 1. Quét thông tin vị trí & Kiểm tra che lấp
            guard let (tvRect, isObstructed) = self.checkTVWindowStatus() else {
                
                if window.isVisible {
                    window.orderOut(nil)
                }
                
                // Reset chữ phụ đề về rỗng để ngắt hiển thị triệt để
                DispatchQueue.main.async {
                    self.subManager.currentText = ""
                    self.subManager.isPlaying = false
                }
                
                return
            }
            
            // Nếu bị cửa sổ khác đè lên khu vực xem -> Tạm ẩn Subtitle
            if isObstructed {
                if window.isVisible {
                    window.orderOut(nil)
                }
                return
            }
            
            // Cập nhật kích thước TV nếu có thay đổi
            if self.tvWindowSize != tvRect.size {
                DispatchQueue.main.async {
                    self.tvWindowSize = tvRect.size
                }
            }
            
            // Cấu hình đè Space Fullscreen
            let requiredBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            if window.collectionBehavior != requiredBehavior {
                window.collectionBehavior = requiredBehavior
            }
            
            if window.level != .mainMenu {
                window.level = .mainMenu
            }
            
            // Tính toán khung hình Subtitle
            let overlayW: CGFloat = tvRect.width * 0.9
            let overlayH: CGFloat = max(60, tvRect.height * 0.2)
            let overlayX: CGFloat = tvRect.origin.x + (tvRect.width - overlayW) / 2
            
            let currentScreen = NSScreen.screens.first(where: { $0.frame.intersects(tvRect) }) ?? NSScreen.main
            let screenHeight = currentScreen?.frame.height ?? 1080
            let screenOriginY = currentScreen?.frame.origin.y ?? 0
            
            let liveBottomOffset = UserDefaults.standard.double(forKey: "bottomOffset")
            let calculatedOffset = tvRect.height * CGFloat(liveBottomOffset)
            
            let overlayY: CGFloat = (screenHeight + screenOriginY) - (tvRect.origin.y + tvRect.height) + calculatedOffset
            
            let targetFrame = NSRect(x: overlayX, y: overlayY, width: overlayW, height: overlayH)
            
            window.setFrame(targetFrame, display: true, animate: false)
            
            // Đảm bảo hiển thị nếu không bị che
            window.orderFrontRegardless()
        }
    }
    
    // 💡 Hàm kiểm tra xem Apple TV có bị cửa sổ ứng dụng khác đè lên không
    private func checkTVWindowStatus() -> (rect: CGRect, isObstructed: Bool)? {
        // Thêm cờ excludeDesktopElements để loại bỏ Wallpaper, Widgets...
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        
        var tvRect: CGRect?
        var tvWindowIndex: Int?
        
        // Bước A: Tìm cửa sổ Apple TV trong danh sách Z-Order
        for (index, info) in windowInfoList.enumerated() {
            if let ownerName = info[kCGWindowOwnerName as String] as? String,
               (ownerName == "TV" || ownerName == "Apple TV"),
               let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
               rect.width > 300 && rect.height > 200 {
                
                tvRect = rect
                tvWindowIndex = index
                break
            }
        }
        
        // Nếu không tìm thấy ở Space hiện tại (ví dụ: TV đang Fullscreen ở Space khác)
        guard let foundTVRect = tvRect, let tvIndex = tvWindowIndex else {
            if let fsRect = findTVWindow(options: [.optionAll]) {
                return (fsRect, false)
            }
            return nil
        }
        
        // Danh sách các App/System Process cần BỎ QUA không tính là "che lấp"
        let ignoredOwners: Set<String> = [
            "exSubtitle", "ExSubtitle", "Window Server", "Control Center",
            "SystemUIServer", "Dock", "NotificationCenter",
            "Spotlight", "Wallpaper", "WindowManager"
        ]
        
        // Bước B: Chỉ kiểm tra các cửa sổ ứng dụng thực sự nằm PHÍA TRÊN Apple TV
        for i in 0..<tvIndex {
            let info = windowInfoList[i]
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            
            // 1. Bỏ qua nếu thuộc danh sách hệ thống hoặc chính app exSubtitle
            if ignoredOwners.contains(ownerName) {
                continue
            }
            
            // 2. Chỉ kiểm tra các cửa sổ có Layer = 0 (Khu vực ứng dụng bình thường của user)
            let windowLayer = info[kCGWindowLayer as String] as? Int ?? 0
            if windowLayer != 0 {
                continue
            }
            
            // 3. Lấy khung hình của cửa sổ nằm phía trên
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let upperRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                
                // Nếu cửa sổ giao thoa đè lên khu vực cửa sổ TV
                if upperRect.intersects(foundTVRect) {
                    let intersection = upperRect.intersection(foundTVRect)
                    // Nếu diện tích bị đè lấp > 20% diện tích TV -> Mới coi là bị che!
                    if (intersection.width * intersection.height) > (foundTVRect.width * foundTVRect.height * 0.20) {
                        return (foundTVRect, true) // 🚨 Bị ứng dụng khác đè lên
                    }
                }
            }
        }
        
        return (foundTVRect, false) // 🟢 An toàn, hiện Subtitle bình thường
    }
    
    // MARK: - 3. Scan Cửa sổ Apple TV thông minh theo từng chế độ
    private func getAppleTVWindowRect() -> CGRect? {
        // Thử quét cửa sổ ở Space hiện tại trước (Tối ưu cho chế độ Windowed bám chính xác 100%)
        if let windowOnScreen = findTVWindow(options: [.optionOnScreenOnly, .excludeDesktopElements]) {
            return windowOnScreen
        }
        
        // Nếu không thấy (khi TV.app vào Full Screen chuyển Space), tiến hành quét xuyên Space
        return findTVWindow(options: [.optionAll])
    }
    
    private func findTVWindow(options: CGWindowListOption) -> CGRect? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        
        for info in windowInfoList {
            if let ownerName = info[kCGWindowOwnerName as String] as? String,
               (ownerName == "TV" || ownerName == "Apple TV"),
               let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                
                // Lọc bỏ thanh công cụ/menu phụ, chỉ lấy cửa sổ phim có kích thước hợp lệ
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
