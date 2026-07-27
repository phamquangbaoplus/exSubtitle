import SwiftUI
import AppKit
import CoreGraphics

// MARK: - 1. MODEL ĐỌC FILE .SRT
struct SubtitleItem {
    let startMs: Int
    let endMs: Int
    let text: String
}

class SubtitleManager: ObservableObject {
    @Published var currentText: String = "Chưa nạp file .SRT"
    @Published var isPlaying: Bool = false
    @Published var timeOffsetMs: Int = 0
    
    private var subtitles: [SubtitleItem] = []
    private var currentTimeMs: Int = 0
    private var timer: Timer?

    func loadSRT(url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let blocks = content.components(separatedBy: "\n\n")
        var parsed: [SubtitleItem] = []
        
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            if lines.count >= 3 {
                let timeLine = lines[1]
                let times = timeLine.components(separatedBy: " --> ")
                if times.count == 2,
                   let start = parseTime(times[0]),
                   let end = parseTime(times[1]) {
                    let text = lines[2...].joined(separator: "\n")
                    parsed.append(SubtitleItem(startMs: start, endMs: end, text: text))
                }
            }
        }
        self.subtitles = parsed
        self.currentText = "Đã nạp \(subtitles.count) câu sub. Bấm ▶ để bắt đầu"
    }

    private func parseTime(_ timeStr: String) -> Int? {
        let cleanStr = timeStr.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let parts = cleanStr.components(separatedBy: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) else { return nil }
        return Int((hours * 3600 + minutes * 60 + seconds) * 1000)
    }

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                self.updateSub()
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func updateSub() {
        currentTimeMs += 100
        let effectiveTime = currentTimeMs + timeOffsetMs
        
        if let match = subtitles.first(where: { $0.startMs <= effectiveTime && effectiveTime <= $0.endMs }) {
            self.currentText = match.text
        } else {
            self.currentText = ""
        }
    }

    func adjustOffset(by ms: Int) {
        timeOffsetMs += ms
    }
}

// MARK: - 2. GIAO DIỆN SWIFTUI Trong Suốt
struct ContentView: View {
    @StateObject private var subManager = SubtitleManager()

    var body: some View {
        VStack(spacing: 8) {
            // Thanh công cụ nhỏ
            HStack(spacing: 12) {
                Button("📁 Mở file .SRT") {
                    selectSRTFile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(subManager.isPlaying ? "⏸ Tạm dừng" : "▶ Phát") {
                    subManager.togglePlay()
                }
                .controlSize(.small)

                Button("-1s") { subManager.adjustOffset(by: -1000) }
                    .controlSize(.small)
                Button("+1s") { subManager.adjustOffset(by: 1000) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            // Hiển thị chữ phụ đề
            Text(subManager.currentText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.75))
                .cornerRadius(8)
                .shadow(radius: 4)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color.clear)
        .onAppear {
            makeWindowFloatingAndTransparent()
            startAppleTVWindowDocking()
        }
    }

    private func selectSRTFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            subManager.loadSRT(url: url)
        }
    }

    // Cấu hình cửa sổ macOS: Trong suốt & Luôn nổi trên cùng (Floating)
    private func makeWindowFloatingAndTransparent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .floating // Luôn nổi trên mọi cửa sổ
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
            }
        }
    }

    // Tự động quét và "hút" phụ đề bám theo cửa sổ Apple TV
    private func startAppleTVWindowDocking() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let tvRect = getAppleTVWindowRect(),
                  let window = NSApplication.shared.windows.first else { return }

            let overlayW: CGFloat = tvRect.width * 0.85
            let overlayH: CGFloat = 110
            let overlayX: CGFloat = tvRect.origin.x + (tvRect.width - overlayW) / 2
            
            // macOS dùng hệ tọa độ Y từ dưới lên trên
            guard let screenHeight = NSScreen.main?.frame.height else { return }
            let overlayY: CGFloat = screenHeight - (tvRect.origin.y + tvRect.height) + 40

            let targetFrame = NSRect(x: overlayX, y: overlayY, width: overlayW, height: overlayH)
            
            // Di chuyển mượt mà tới vị trí cửa sổ Apple TV
            window.setFrame(targetFrame, display: true, animate: false)
        }
    }

    // API macOS lấy tọa độ cửa sổ Apple TV
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
