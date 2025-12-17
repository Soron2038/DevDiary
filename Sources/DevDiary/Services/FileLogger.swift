import Foundation

/// Simple file logger for debugging - writes to ~/Library/Logs/DevDiary/debug.log
final class FileLogger {
    static let shared = FileLogger()
    
    private let fileURL: URL
    private let dateFormatter: DateFormatter
    
    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DevDiary", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        fileURL = logsDir.appendingPathComponent("debug.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Write header on launch
        let header = "\n\n========== DevDiary Launch \(dateFormatter.string(from: Date())) ==========\n"
        append(header)
    }
    
    func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] [\(fileName):\(line)] \(function): \(message)\n"
        append(entry)
    }
    
    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
}
