import Foundation
import SwiftUI

/// Provider-agnostic label attached to an issue.
struct ForgeLabel: Identifiable, Equatable {
    let id: String
    let name: String
    /// Hex color WITHOUT leading `#`.
    let hexColor: String

    var swiftUIColor: Color {
        Color(hex: hexColor)
    }
}

/// Provider-agnostic representation of an assigned issue.
struct ForgeIssue: Identifiable, Equatable {
    let id: String                    // "<accountId>:<providerId>"
    let providerAccountId: String
    let providerKind: ForgeKind
    let number: Int
    let title: String
    let webURL: String
    let createdAt: Date
    let updatedAt: Date
    let authorLogin: String
    let labels: [ForgeLabel]
    let repoFullName: String
}
