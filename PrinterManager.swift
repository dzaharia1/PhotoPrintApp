import Foundation

class PrinterManager {
    
    // Executes a system command and returns the stdout
    private static func runCommand(path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                print("Command \(path) \(arguments.joined(separator: " ")) failed with status \(process.terminationStatus): \(errorMsg)")
            }
            return output
        } catch {
            print("Failed to execute \(path): \(error)")
            return ""
        }
    }
    
    // Discover active CUPS printers
    static func getPrinters() -> [String] {
        let output = runCommand(path: "/usr/bin/lpstat", arguments: ["-p"])
        if output.isEmpty { return [] }
        
        return output.split(separator: "\n")
            .filter { $0.hasPrefix("printer ") }
            .compactMap { line -> String? in
                let parts = line.split(separator: " ")
                if parts.count > 1 {
                    return String(parts[1])
                }
                return nil
            }
    }
    
    // Query dynamic option properties (e.g. MediaType, InputSlot) for a selected printer
    static func getPrinterOptions(printer: String, key: String) -> [String] {
        guard !printer.isEmpty else { return [] }
        let output = runCommand(path: "/usr/bin/lpoptions", arguments: ["-p", printer, "-l"])
        if output.isEmpty { return [] }
        
        // Find line starting with key/ or key:
        let lines = output.split(separator: "\n")
        guard let line = lines.first(where: { $0.hasPrefix("\(key)/") || $0.hasPrefix("\(key):") }) else {
            return []
        }
        
        // Format of line is usually: key/Label: Choice *DefaultChoice Choice2
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count > 1 else { return [] }
        
        let choicesStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return choicesStr.split(separator: " ").map { choice -> String in
            var c = String(choice)
            if c.hasPrefix("*") {
                c.removeFirst()
            }
            return c
        }
    }
    
    // Submits the print job via `lp`
    static func printComposite(filePath: String, config: PrintConfig) -> String? {
        guard !config.printer.isEmpty else { return "No printer selected" }
        
        let arguments = [
            "-d", config.printer,
            "-o", "PageSize=\(config.cupsPaperSize)",
            "-o", "InputSlot=\(config.inputSlot)",
            "-o", "MediaType=\(config.mediaType)",
            "-o", "scaling=100",
            filePath
        ]
        
        // Log the print command we are sending
        print("Sending print command: lp \(arguments.joined(separator: " "))")
        
        let output = runCommand(path: "/usr/bin/lp", arguments: arguments)
        if output.contains("request id is") {
            return output
        } else if !output.isEmpty {
            return output
        }
        return nil
    }
}
