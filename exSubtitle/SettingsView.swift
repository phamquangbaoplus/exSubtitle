//
//  SettingsView.swift
//  ExSubtitle
//

import SwiftUI
import AppKit

// MARK: - Danh sách Font Weight
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

struct SettingsView: View {
    @AppStorage("fontSizeRatio") private var fontSizeRatio: Double = 0.02
    @AppStorage("selectedFontFamily") private var selectedFontFamily: String = "Helvetica Neue"
    @AppStorage("selectedFontWeight") private var selectedFontWeight: String = FontWeightOption.regular.rawValue
    @AppStorage("backgroundStyle") private var backgroundStyle: String = BackgroundStyleOption.transparent.rawValue
    @AppStorage("bottomOffset") private var bottomOffset: Double = 0.02

    private var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    var body: some View {
        
        Form {

            Section(header: Text("Customize Subtitle").bold()) {
                // 1. Chọn Font Family từ Hệ thống
                Picker("Font Family:", selection: $selectedFontFamily) {
                    ForEach(availableFontFamilies, id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                // 2. Chọn Độ đậm nhạt (Font Weight)
                Picker("Weight:", selection: $selectedFontWeight) {
                    ForEach(FontWeightOption.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                // 3. Kiểu nền phụ đề (Select Picker)
                Picker("Background Style:", selection: $backgroundStyle) {
                    ForEach(BackgroundStyleOption.allCases) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                // 4. Chỉnh cỡ chữ
                VStack(alignment: .leading) {
                    Text("Size: \(String(format: "%.1f", fontSizeRatio * 100))%")
                    Slider(value: $fontSizeRatio, in: 0.015...0.045, step: 0.0025)
                }

                // 5. Chỉnh khoảng cách từ đáy
                VStack(alignment: .leading) {
                    Text("Bottom Offset: \(String(format: "%.1f", bottomOffset * 100))%")
                    Slider(value: $bottomOffset, in: 0.0...0.20, step: 0.005)
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 340)
    }
}
