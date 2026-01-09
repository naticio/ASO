//
//  CrossPlatform.swift
//  ASO
//

import SwiftUI

#if os(macOS)
import AppKit

extension Color {
    static let systemBackground = Color(NSColor.windowBackgroundColor)
    static let secondarySystemBackground = Color(NSColor.controlBackgroundColor)
    static let tertiarySystemBackground = Color(NSColor.underPageBackgroundColor)
    static let systemGroupedBackground = Color(NSColor.windowBackgroundColor)
    static let secondarySystemGroupedBackground = Color(NSColor.controlBackgroundColor)
}

extension NSColor {
    static let secondarySystemBackground = NSColor.controlBackgroundColor
}

typealias PlatformColor = NSColor
#else
import UIKit

extension Color {
    static let systemBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
    static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
}

typealias PlatformColor = UIColor
#endif
