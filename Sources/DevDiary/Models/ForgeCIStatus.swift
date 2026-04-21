import Foundation
import SwiftUI

/// Unified CI status that maps GitHub Actions conclusions and GitLab pipeline states
/// onto a shared vocabulary for UI display.
enum ForgeCIStatus: String {
    case success
    case failure
    case pending       // queued, in_progress, waiting, running
    case cancelled
    case skipped
    case unknown
    case noWorkflows   // Repository has no pipelines/workflows

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .pending: return .orange
        case .cancelled, .skipped: return .gray
        case .unknown, .noWorkflows: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .cancelled: return "nosign"
        case .skipped: return "arrow.right.circle"
        case .unknown: return "questionmark.circle"
        case .noWorkflows: return "minus.circle"
        }
    }

    var localizationKey: String {
        "workflow.status.\(rawValue)"
    }
}
