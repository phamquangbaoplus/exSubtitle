//
//  ExSubtitleApp.swift
//  ExSubtitle
//

import SwiftUI
import AppKit

enum FontWeightOption: String, CaseIterable, Identifiable {
    case regular = "Regular"
    case medium = "Medium"
    case bold = "Bold"
    case heavy = "Heavy"
    
    var id: String { rawValue }
    
    var nsWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
}

// MARK: - Danh sách Nền Phụ Đề
enum BackgroundStyleOption: String, CaseIterable, Identifiable {
    case transparent = "Transparent"
    case blur = "Blur"
    
    var id: String { rawValue }
}

extension Bundle {
    /// Trả về chuỗi Short Version (Ví dụ: "1.0.0")
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    /// Trả về Build Number (Ví dụ: "1")
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

@main
struct ExSubtitleApp: App {
    @StateObject private var subManager = SubtitleManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(subManager)
        }
    }
}

extension Notification.Name {
    static let openSRTFile = Notification.Name("openSRTFile")
}
// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "exSubtitle")
        }
        
        let menu = NSMenu()
        
        // 1. Header App + Version
        let version = Bundle.main.appVersion
        let headerItem = NSMenuItem(title: "  exSubtitle v\(version)", action: nil, keyEquivalent: "")
        if let headerIcon = NSImage(named: "AppIcon") {
            headerIcon.size = NSSize(width: 18, height: 18)
            headerItem.image = headerIcon
        }
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Chức năng chính
        menu.addItem(withTitle: NSLocalizedString("Load subtitle...", comment: ""), action: #selector(openSRT), keyEquivalent: "o")
            .target = self
        
        menu.addItem(NSMenuItem.separator())
        
        // 💡 3. DANH SÁCH MENU SETTINGS TỰ TẠO
        
        // --- Font Size Submenu ---
        let fontSizeMenu = NSMenu()
        let sizeOptions: [(String, Double)] = [("Small", 0.015), ("Medium", 0.020), ("Large", 0.025), ("Extra Large", 0.030)]
        let currentSizeRatio = UserDefaults.standard.double(forKey: "fontSizeRatio") == 0 ? 0.02 : UserDefaults.standard.double(forKey: "fontSizeRatio")
        
        for (title, value) in sizeOptions {
            let menuItem = NSMenuItem(title: title, action: #selector(changeFontSize(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = value
            if abs(currentSizeRatio - value) < 0.001 { menuItem.state = .on }
            fontSizeMenu.addItem(menuItem)
        }
        let fontSizeItem = NSMenuItem(title: NSLocalizedString("Font Size", comment: ""), action: nil, keyEquivalent: "")
        fontSizeItem.submenu = fontSizeMenu
        menu.addItem(fontSizeItem)
        
        // --- Font Weight Submenu ---
        let fontWeightMenu = NSMenu()
        let weightOptions = ["Regular", "Bold", "Heavy"]
        let currentWeight = UserDefaults.standard.string(forKey: "selectedFontWeight") ?? "Bold"
        
        for weight in weightOptions {
            let menuItem = NSMenuItem(title: weight, action: #selector(changeFontWeight(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = weight
            if currentWeight == weight { menuItem.state = .on }
            fontWeightMenu.addItem(menuItem)
        }
        let fontWeightItem = NSMenuItem(title: NSLocalizedString("Font Weight", comment: ""), action: nil, keyEquivalent: "")
        fontWeightItem.submenu = fontWeightMenu
        menu.addItem(fontWeightItem)
        
        // --- Background Style Submenu ---
        let bgStyleMenu = NSMenu()
        
        // 💡 Lấy giá trị hiện tại, nếu chưa có thì dùng rawValue mặc định của .transparent
        let currentBg = UserDefaults.standard.string(forKey: "backgroundStyle") ?? BackgroundStyleOption.transparent.rawValue
        
        // 💡 Duyệt qua tất cả case của Enum BackgroundStyleOption
        for option in BackgroundStyleOption.allCases {
            // 💡 Chuyển chữ cái đầu thành viết hoa làm tên hiển thị (Ví dụ: "transparent" -> "Transparent")
            let title = option.rawValue.capitalized
            
            let menuItem = NSMenuItem(
                title: title,
                action: #selector(changeBackgroundStyle(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = option.rawValue
            
            if currentBg == option.rawValue {
                menuItem.state = .on
            }
            bgStyleMenu.addItem(menuItem)
        }
        
        let bgStyleItem = NSMenuItem(title: NSLocalizedString("Background Style", comment: ""), action: nil, keyEquivalent: "")
        bgStyleItem.submenu = bgStyleMenu
        menu.addItem(bgStyleItem)
        
        // --- Bottom Offset Submenu ---
        let offsetMenu = NSMenu()
        let offsetOptions: [(String, Double)] = [("Low", 0.01), ("Medium", 0.03), ("High", 0.06)]
        let currentOffset = UserDefaults.standard.double(forKey: "bottomOffset") == 0 ? 0.02 : UserDefaults.standard.double(forKey: "bottomOffset")
        
        for (title, value) in offsetOptions {
            let menuItem = NSMenuItem(title: title, action: #selector(changeBottomOffset(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = value
            if abs(currentOffset - value) < 0.005 { menuItem.state = .on }
            offsetMenu.addItem(menuItem)
        }
        let offsetItem = NSMenuItem(title: NSLocalizedString("Position Offset", comment: ""), action: nil, keyEquivalent: "")
        offsetItem.submenu = offsetMenu
        menu.addItem(offsetItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Quit App
        menu.addItem(withTitle: NSLocalizedString("Quit", comment: ""), action: #selector(quitApp), keyEquivalent: "q")
            .target = self
        
        item.menu = menu
        statusItem = item
    }
    
    // MARK: - Handlers cho Menu Actions (Lưu vào UserDefaults & Refresh Checkmark)
    
    @objc private func openSRT() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSRTFile, object: nil)
    }
    
    @objc private func changeFontSize(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double {
            UserDefaults.standard.set(value, forKey: "fontSizeRatio")
            updateCheckmark(in: sender.menu, selectedItem: sender)
        }
    }
    
    @objc private func changeFontWeight(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String {
            UserDefaults.standard.set(value, forKey: "selectedFontWeight")
            updateCheckmark(in: sender.menu, selectedItem: sender)
        }
    }
    
    @objc private func changeBackgroundStyle(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String {
            UserDefaults.standard.set(value, forKey: "backgroundStyle")
            updateCheckmark(in: sender.menu, selectedItem: sender)
        }
    }
    
    @objc private func changeBottomOffset(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? Double {
            UserDefaults.standard.set(value, forKey: "bottomOffset")
            updateCheckmark(in: sender.menu, selectedItem: sender)
        }
    }
    
    private func updateCheckmark(in menu: NSMenu?, selectedItem: NSMenuItem) {
        guard let menu = menu else { return }
        for item in menu.items {
            item.state = (item == selectedItem) ? .on : .off
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
