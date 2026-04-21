import SwiftUI
import AppKit

/// View for generating and exporting activity reports
struct ReportsView: View {
    @State private var selectedReportType: ReportService.ReportType = .today
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var generatedReport = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showCopiedFeedback = false
    @State private var showSaveSuccess = false
    
    var body: some View {
        HSplitView {
            // Left: Options
            optionsPanel
                .frame(minWidth: 200, maxWidth: 280)
            
            // Right: Preview
            previewPanel
        }
    }
    
    // MARK: - Options Panel
    
    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("reports.title")
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Report type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("reports.type")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ForEach(ReportService.ReportType.allCases.filter { $0 != .custom }) { type in
                            ReportTypeButton(
                                type: type,
                                isSelected: selectedReportType == type,
                                action: {
                                    selectedReportType = type
                                    generateReport()
                                }
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Custom date range
                    VStack(alignment: .leading, spacing: 12) {
                        Text("reports.customRange")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Date range with aligned labels
                        VStack(spacing: 8) {
                            HStack {
                                Text("reports.from")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, alignment: .leading)
                                
                                DatePicker(
                                    "",
                                    selection: $customStartDate,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.field)
                                .labelsHidden()
                            }
                            
                            HStack {
                                Text("reports.to")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 32, alignment: .leading)
                                
                                DatePicker(
                                    "",
                                    selection: $customEndDate,
                                    in: ...Date(),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.field)
                                .labelsHidden()
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        
                        Button(action: {
                            selectedReportType = .custom
                            generateReport()
                        }) {
                            Label(String(localized: "reports.generate"), systemImage: "doc.text")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(customStartDate > customEndDate)
                    }
                    
                    Divider()
                    
                    // Actions
                    VStack(spacing: 8) {
                        Button(action: copyToClipboard) {
                            Label(String(localized: "reports.copy"), systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(generatedReport.isEmpty)
                        
                        Button(action: saveToFile) {
                            Label(String(localized: "reports.save"), systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(generatedReport.isEmpty)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Preview Panel
    
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("reports.preview")
                    .font(.headline)
                
                Spacer()
                
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                if showSaveSuccess {
                    Label(String(localized: "reports.saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding()
            
            Divider()
            
            if let error = errorMessage {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if generatedReport.isEmpty && !isGenerating {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("reports.empty")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Markdown preview
                ScrollView {
                    Text(generatedReport)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
    
    // MARK: - Actions
    
    private func generateReport() {
        isGenerating = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let report = try ReportService.shared.generateReport(
                    type: selectedReportType,
                    customStart: customStartDate,
                    customEnd: customEndDate
                )
                
                DispatchQueue.main.async {
                    self.generatedReport = report
                    self.isGenerating = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedReport, forType: .string)
        
        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedFeedback = false
        }
    }
    
    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = generateFileName()
        panel.message = String(localized: "reports.save.message")
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try generatedReport.write(to: url, atomically: true, encoding: .utf8)
                showSaveSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showSaveSuccess = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func generateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        switch selectedReportType {
        case .today:
            return "DevDiary-\(dateFormatter.string(from: Date())).md"
        case .yesterday:
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            return "DevDiary-\(dateFormatter.string(from: yesterday)).md"
        case .thisWeek, .lastWeek:
            return "DevDiary-Week-\(dateFormatter.string(from: Date())).md"
        case .thisMonth:
            dateFormatter.dateFormat = "yyyy-MM"
            return "DevDiary-\(dateFormatter.string(from: Date())).md"
        case .custom:
            return "DevDiary-\(dateFormatter.string(from: customStartDate))-to-\(dateFormatter.string(from: customEndDate)).md"
        }
    }
}

// MARK: - Supporting Views

private struct ReportTypeButton: View {
    let type: ReportService.ReportType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .frame(width: 20)
                Text(String(localized: String.LocalizationValue(type.localizationKey)))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        switch type {
        case .today: return "sun.max"
        case .yesterday: return "moon"
        case .thisWeek: return "calendar"
        case .lastWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar.circle"
        case .custom: return "calendar.badge.plus"
        }
    }
}

#Preview {
    ReportsView()
        .frame(width: 800, height: 600)
}
