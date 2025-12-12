import ContextifyCore
import Foundation

@main
struct TranscriptValidatorCLI {

    static func main() throws {
        var provider = "claude.code"
        var pathArgument: String?

        let args = Array(CommandLine.arguments.dropFirst())
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--provider":
                index += 1
                guard index < args.count else { usage("Missing provider after --provider") }
                provider = args[index]
            case "--help", "-h":
                usage(nil)
            default:
                if pathArgument == nil {
                    pathArgument = arg
                } else {
                    usage("Unexpected argument: \(arg)")
                }
            }
            index += 1
        }

        guard let path = pathArgument else {
            usage("Missing transcript path")
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs("❌ File not found: \(url.path)\n", stderr)
            exit(2)
        }

        let parser = MultiProviderParser()
        let data = try String(contentsOf: url, encoding: .utf8)
        let lines = data.split(whereSeparator: \.isNewline)

        var lineNumber = 0
        var parsedCount = 0
        var skippedCount = 0

        for rawLine in lines {
            lineNumber += 1
            let line = String(rawLine)
            do {
                _ = try parser.parse(
                    line: line,
                    lineNumber: lineNumber,
                    transcriptId: "CLI-TEST",
                    projectId: "CLI-TEST",
                    provider: provider,
                    sessionId: nil
                )
                parsedCount += 1
            } catch ParserError.skipEntry {
                skippedCount += 1
            } catch {
                fputs("❌ Parse error at line \(lineNumber): \(error)\n", stderr)
                exit(3)
            }
        }

        print("✅ Parsed \(parsedCount) entries (\(skippedCount) skipped) from \(lineNumber) lines")
    }

    private static func usage(_ message: String?) -> Never {
        if let message {
            fputs("Error: \(message)\n\n", stderr)
        }
        fputs("Usage: swift run TranscriptValidatorCLI [--provider claude.code|codex.cli] <path-to-transcript.jsonl>\n", stderr)
        exit(message == nil ? 0 : 1)
    }
}
