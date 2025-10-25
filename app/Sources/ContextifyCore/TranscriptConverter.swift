//
//  TranscriptConverter.swift
//  ContextifyCore
//
//  Swift implementation of bidirectional transcript conversion
//  Reference: scripts/convert_transcript.py
//

import Foundation

// MARK: - Public Types

/// Supported transcript formats
public enum TranscriptFormat: String, Sendable {
    case claudeCode = "claude-code"
    case codexCLI = "codex"
}

/// Conversion statistics
public struct ConversionStats: Sendable {
    public var totalLines: Int = 0
    public var converted: Int = 0
    public var skipped: Int = 0
    public var errors: Int = 0
    public var toolCallsDirect: Int = 0        // Tier 1 (Bash ↔ shell)
    public var toolCallsSummarized: Int = 0    // Tier 2 (Edit, Read, etc.)
    public var toolCallsSkipped: Int = 0       // Tier 3 (TodoWrite, etc.)

    public init() {}
}

/// Result of a conversion operation
public struct ConversionResult: Sendable {
    public let stats: ConversionStats
    public let actualOutputPath: URL
    public let sessionId: String?
    public let projectDir: String?

    public init(stats: ConversionStats, actualOutputPath: URL, sessionId: String?, projectDir: String?) {
        self.stats = stats
        self.actualOutputPath = actualOutputPath
        self.sessionId = sessionId
        self.projectDir = projectDir
    }
}

/// Conversion errors
public enum ConversionError: Error, LocalizedError {
    case invalidFormat(String)
    case fileNotFound(String)
    case invalidJSON(line: Int, error: String)
    case missingRequiredField(line: Int, field: String)
    case sameFormat
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid format: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .invalidJSON(let line, let error): return "JSON parse error at line \(line): \(error)"
        case .missingRequiredField(let line, let field): return "Missing required field '\(field)' at line \(line)"
        case .sameFormat: return "Source and target formats must be different"
        case .ioError(let msg): return "I/O error: \(msg)"
        }
    }
}

// MARK: - Transcript Converter

/// Bidirectional transcript converter (Claude Code ↔ Codex CLI)
public actor TranscriptConverter {

    private let verbose: Bool
    private var stats: ConversionStats
    private var sessionId: String?
    private var projectDir: String?
    private var actualOutputPath: URL?

    public init(verbose: Bool = false) {
        self.verbose = verbose
        self.stats = ConversionStats()
    }

    // MARK: - Public API

    /// Convert transcript from one format to another
    public func convert(
        from: TranscriptFormat,
        to: TranscriptFormat,
        inputPath: URL,
        outputPath: URL
    ) async throws -> ConversionResult {

        guard from != to else {
            throw ConversionError.sameFormat
        }

        log("Converting \(from.rawValue) → \(to.rawValue)")
        log("Input: \(inputPath.path)")
        log("Output: \(outputPath.path)")

        // Reset state
        stats = ConversionStats()
        sessionId = nil
        projectDir = nil
        actualOutputPath = outputPath

        // Perform conversion
        switch (from, to) {
        case (.claudeCode, .codexCLI):
            try await claudeToCodex(inputPath: inputPath, outputPath: outputPath)
        case (.codexCLI, .claudeCode):
            try await codexToClaude(inputPath: inputPath, outputPath: outputPath)
        case (.claudeCode, .claudeCode), (.codexCLI, .codexCLI):
            // Already validated above, but compiler requires exhaustiveness
            throw ConversionError.sameFormat
        }

        return ConversionResult(
            stats: stats,
            actualOutputPath: actualOutputPath ?? outputPath,
            sessionId: sessionId,
            projectDir: projectDir
        )
    }

    // MARK: - Claude Code → Codex CLI

    private func claudeToCodex(inputPath: URL, outputPath: URL) async throws {
        // Generate session ID
        let newSessionId = UUID().uuidString.lowercased()
        sessionId = newSessionId

        // Validate and possibly auto-correct output path
        let correctedPath = try validateCodexOutputPath(outputPath, sessionId: newSessionId)
        actualOutputPath = correctedPath

        log("Using session ID: \(newSessionId)")

        guard let inputStream = InputStream(url: inputPath) else {
            throw ConversionError.fileNotFound(inputPath.path)
        }
        inputStream.open()
        defer { inputStream.close() }

        guard let outputStream = OutputStream(url: correctedPath, append: false) else {
            throw ConversionError.ioError("Cannot create output file: \(correctedPath.path)")
        }
        outputStream.open()
        defer { outputStream.close() }

        var lineNumber = 0
        var firstMessage = true
        var toolResultsMap: [String: (result: [String: Any], lineNum: Int)] = [:]

        // Two-pass: Load all records first to build tool results map
        let records = try loadRecords(from: inputPath)

        // Build tool results map
        for (idx, record) in records.enumerated() {
            if record["type"] as? String == "user",
               let message = record["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if block["type"] as? String == "tool_result",
                       let toolUseId = block["tool_use_id"] as? String {
                        toolResultsMap[toolUseId] = (result: block, lineNum: idx + 1)
                    }
                }
            }
        }

        // Process records
        for (idx, record) in records.enumerated() {
            lineNumber = idx + 1
            stats.totalLines += 1

            guard let recordType = record["type"] as? String else {
                log("Line \(lineNumber): Missing 'type' field")
                stats.skipped += 1
                continue
            }

            // Skip non-message records
            if recordType != "user" && recordType != "assistant" {
                log("Line \(lineNumber): Skipping type=\(recordType)")
                stats.skipped += 1
                continue
            }

            // Skip meta/sidechain
            if (record["isMeta"] as? Bool) == true || (record["isSidechain"] as? Bool) == true {
                log("Line \(lineNumber): Skipping meta/sidechain")
                stats.skipped += 1
                continue
            }

            guard let timestamp = record["timestamp"] as? String else {
                log("Line \(lineNumber): Missing required field 'timestamp'")
                stats.errors += 1
                continue
            }

            // Generate session_meta from first message
            if firstMessage {
                let cwd = record["cwd"] as? String ?? "/"
                projectDir = cwd

                let sessionMeta: [String: Any] = [
                    "timestamp": timestamp,
                    "type": "session_meta",
                    "payload": [
                        "id": newSessionId,
                        "timestamp": timestamp,
                        "cwd": cwd,
                        "originator": "swift_contextify_converter",
                        "cli_version": "converted-1.0.0",
                        "instructions": NSNull(),
                        "source": "cli"  // Required for Codex picker
                    ]
                ]

                try writeJSON(sessionMeta, to: outputStream)
                log("Generated session_meta (session_id=\(newSessionId))")
                firstMessage = false
            }

            // Convert message
            if recordType == "user" {
                try convertUserMessage(record, timestamp: timestamp, lineNumber: lineNumber, to: outputStream)
            } else if recordType == "assistant" {
                try await convertAssistantMessage(
                    record,
                    timestamp: timestamp,
                    lineNumber: lineNumber,
                    toolResultsMap: toolResultsMap,
                    to: outputStream
                )
            }
        }
    }

    // MARK: - Codex CLI → Claude Code

    private func codexToClaude(inputPath: URL, outputPath: URL) async throws {
        var gitContext: [String: String] = [:]
        var previousUuid: String?

        // Monotonic timestamp generator
        var baseTimestamp = Date()
        func nextTimestamp() -> String {
            baseTimestamp.addTimeInterval(0.001) // +1ms
            return ISO8601DateFormatter().string(from: baseTimestamp).replacingOccurrences(of: "+00:00", with: "Z")
        }

        // Load and validate
        let records = try loadRecords(from: inputPath)

        // Extract session_id from session_meta
        for record in records {
            if record["type"] as? String == "session_meta",
               let payload = record["payload"] as? [String: Any] {
                sessionId = payload["id"] as? String
                projectDir = payload["cwd"] as? String

                if let gitInfo = payload["git"] as? [String: Any] {
                    gitContext["gitBranch"] = gitInfo["branch"] as? String ?? "main"
                    gitContext["gitCommit"] = gitInfo["commit_hash"] as? String
                } else {
                    gitContext["gitBranch"] = "main"
                }
                gitContext["cwd"] = projectDir ?? "/"
                break
            }
        }

        // Validate/correct output filename
        let correctedPath = try validateClaudeCodeOutputPath(outputPath, sessionId: sessionId)
        actualOutputPath = correctedPath

        guard let outputStream = OutputStream(url: correctedPath, append: false) else {
            throw ConversionError.ioError("Cannot create output file: \(correctedPath.path)")
        }
        outputStream.open()
        defer { outputStream.close() }

        var lineNumber = 0
        var convertedCalls = Set<String>()

        // Process messages
        for (idx, record) in records.enumerated() {
            lineNumber = idx + 1
            stats.totalLines += 1

            guard let recordType = record["type"] as? String else {
                stats.skipped += 1
                continue
            }

            if recordType != "response_item" {
                log("Line \(lineNumber): Skipping type=\(recordType)")
                stats.skipped += 1
                continue
            }

            guard let payload = record["payload"] as? [String: Any],
                  payload["type"] as? String == "message" else {
                log("Line \(lineNumber): Skipping non-message response_item")
                stats.skipped += 1
                continue
            }

            guard let timestamp = record["timestamp"] as? String else {
                log("Line \(lineNumber): Missing timestamp")
                stats.errors += 1
                continue
            }

            guard let role = payload["role"] as? String else {
                log("Line \(lineNumber): Missing role")
                stats.errors += 1
                continue
            }

            // Extract content
            let contentBlocks = payload["content"] as? [[String: Any]] ?? []
            var contentParts: [String] = []
            for block in contentBlocks {
                if let text = block["text"] as? String, !text.isEmpty {
                    contentParts.append(text)
                }
            }

            let content = contentParts.joined(separator: "\n")

            if content.isEmpty {
                log("Line \(lineNumber): No extractable content")
                stats.skipped += 1
                continue
            }

            // Generate UUID
            let messageUuid = UUID().uuidString.lowercased()

            if role == "user" {
                try convertUserMessageToClaude(
                    content: content,
                    uuid: messageUuid,
                    parentUuid: previousUuid,
                    gitContext: gitContext,
                    sessionId: sessionId ?? "converted",
                    timestamp: nextTimestamp(),
                    to: outputStream
                )

                // Add file-history-snapshot
                let snapshot: [String: Any] = [
                    "type": "file-history-snapshot",
                    "messageId": messageUuid,
                    "snapshot": [
                        "messageId": messageUuid,
                        "trackedFileBackups": [:],
                        "timestamp": nextTimestamp()
                    ],
                    "isSnapshotUpdate": false
                ]
                try writeJSON(snapshot, to: outputStream)

                stats.converted += 1
            } else {
                try convertAssistantMessageToClaude(
                    content: content,
                    uuid: messageUuid,
                    parentUuid: previousUuid,
                    gitContext: gitContext,
                    sessionId: sessionId ?? "converted",
                    timestamp: nextTimestamp(),
                    to: outputStream
                )
                stats.converted += 1
            }

            previousUuid = messageUuid
        }
    }

    // MARK: - User Message Conversion

    private func convertUserMessage(
        _ record: [String: Any],
        timestamp: String,
        lineNumber: Int,
        to outputStream: OutputStream
    ) throws {
        guard let message = record["message"] as? [String: Any] else {
            throw ConversionError.missingRequiredField(line: lineNumber, field: "message")
        }

        // Extract text content
        let content = message["content"]
        let (contentArray, textForEvent) = try extractContent(content, contentType: "input_text", lineNumber: lineNumber)

        guard !contentArray.isEmpty else {
            log("Line \(lineNumber): No extractable content")
            stats.skipped += 1
            return
        }

        // Write user response_item
        let codexMessage: [String: Any] = [
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "message",
                "role": "user",
                "content": contentArray
            ]
        ]
        try writeJSON(codexMessage, to: outputStream)

        // Write user_message event
        let eventMsg: [String: Any] = [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "user_message",
                "message": textForEvent,
                "kind": "plain"
            ]
        ]
        try writeJSON(eventMsg, to: outputStream)

        // Write turn_context
        let turnContext: [String: Any] = [
            "timestamp": timestamp,
            "type": "turn_context",
            "payload": [
                "cwd": record["cwd"] as? String ?? "/",
                "approval_policy": "on-request",
                "sandbox_policy": [
                    "mode": "workspace-write",
                    "network_access": false,
                    "exclude_tmpdir_env_var": false,
                    "exclude_slash_tmp": false
                ],
                "model": "gpt-5-codex",
                "summary": "auto"
            ]
        ]
        try writeJSON(turnContext, to: outputStream)

        stats.converted += 1
        log("Line \(lineNumber): Converted user message + turn_context")
    }

    private func convertAssistantMessage(
        _ record: [String: Any],
        timestamp: String,
        lineNumber: Int,
        toolResultsMap: [String: (result: [String: Any], lineNum: Int)],
        to outputStream: OutputStream
    ) async throws {
        guard let message = record["message"] as? [String: Any] else {
            throw ConversionError.missingRequiredField(line: lineNumber, field: "message")
        }

        // Extract content
        let content = message["content"]
        let (contentArray, textForEventInitial) = try extractContent(content, contentType: "output_text", lineNumber: lineNumber)
        var textForEvent = textForEventInitial

        // Extract tool_use blocks
        var toolUses: [[String: Any]] = []
        if let contentBlocks = content as? [[String: Any]] {
            for block in contentBlocks {
                if block["type"] as? String == "tool_use" {
                    toolUses.append(block)
                }
            }
        }

        // Collect Tier 2 summaries
        var tier2Summaries: [String] = []

        // Process tool_use blocks
        for toolUse in toolUses {
            guard let toolName = toolUse["name"] as? String,
                  let toolId = toolUse["id"] as? String else {
                continue
            }

            // Find matching tool_result
            let toolResult = toolResultsMap[toolId]?.result

            if toolName == "Bash" {
                // Tier 1: Direct conversion (shell function_call + output)
                let (funcCall, funcOutput) = try convertBashToShell(
                    toolUse: toolUse,
                    toolResult: toolResult,
                    timestamp: timestamp,
                    workdir: record["cwd"] as? String
                )

                if let fc = funcCall {
                    try writeJSON(fc, to: outputStream)
                    stats.toolCallsDirect += 1
                }

                if let fo = funcOutput {
                    try writeJSON(fo, to: outputStream)
                }

            } else if ["Edit", "Read", "Write", "Grep", "Glob"].contains(toolName) {
                // Tier 2: Lossy text summary
                let summary = toolToTextSummary(toolUse: toolUse, toolResult: toolResult)
                tier2Summaries.append(summary)
                stats.toolCallsSummarized += 1

            } else {
                // Tier 3: Skip entirely
                stats.toolCallsSkipped += 1
            }
        }

        // Append Tier 2 summaries to text
        if !tier2Summaries.isEmpty {
            if !textForEvent.isEmpty {
                textForEvent += "\n\n" + tier2Summaries.joined(separator: "\n")
            } else {
                textForEvent = tier2Summaries.joined(separator: "\n")
            }
        }

        // Write agent_message event (what displays in Codex UI)
        if !textForEvent.isEmpty {
            let agentMessageEvent: [String: Any] = [
                "timestamp": timestamp,
                "type": "event_msg",
                "payload": [
                    "type": "agent_message",
                    "message": textForEvent
                ]
            ]
            try writeJSON(agentMessageEvent, to: outputStream)
        }

        // Write assistant response_item (canonical data)
        if !textForEvent.isEmpty || !contentArray.isEmpty {
            let finalContentArray: [[String: Any]]
            if !textForEvent.isEmpty {
                finalContentArray = [["type": "output_text", "text": textForEvent]]
            } else {
                finalContentArray = contentArray
            }

            let codexMessage: [String: Any] = [
                "timestamp": timestamp,
                "type": "response_item",
                "payload": [
                    "type": "message",
                    "role": "assistant",
                    "content": finalContentArray
                ]
            ]
            try writeJSON(codexMessage, to: outputStream)
        }

        stats.converted += 1
        log("Line \(lineNumber): Converted assistant message (agent_message + response_item)")
    }

    // MARK: - Tool Call Conversion

    private func convertBashToShell(
        toolUse: [String: Any],
        toolResult: [String: Any]?,
        timestamp: String,
        workdir: String?
    ) throws -> (functionCall: [String: Any]?, functionOutput: [String: Any]?) {

        guard let input = toolUse["input"] as? [String: Any],
              let command = input["command"] as? String,
              let toolId = toolUse["id"] as? String else {
            return (nil, nil)
        }

        // Convert tool_use_id to call_id
        let callId = toolUseIdToCallId(toolId)

        // Wrap command as ["bash", "-c", "command"]
        let commandArray = ["bash", "-c", command]

        // Build function_call arguments
        let arguments: [String: Any] = [
            "command": commandArray,
            "workdir": workdir ?? "/"
        ]

        let argumentsJSON = try JSONSerialization.data(withJSONObject: arguments)
        let argumentsString = String(data: argumentsJSON, encoding: .utf8) ?? "{}"

        let functionCall: [String: Any] = [
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "function_call",
                "name": "shell",
                "arguments": argumentsString,
                "call_id": callId
            ]
        ]

        // Build function_call_output
        let output = toolResult?["content"] as? String ?? ""
        let isError = toolResult?["is_error"] as? Bool ?? false
        let exitCode = isError ? 1 : 0

        let outputMetadata: [String: Any] = [
            "output": output,
            "metadata": [
                "exit_code": exitCode,
                "duration_seconds": 0.0
            ]
        ]

        let outputJSON = try JSONSerialization.data(withJSONObject: outputMetadata)
        let outputString = String(data: outputJSON, encoding: .utf8) ?? "{}"

        let functionOutput: [String: Any] = [
            "timestamp": timestamp,
            "type": "response_item",
            "payload": [
                "type": "function_call_output",
                "call_id": callId,
                "output": outputString
            ]
        ]

        return (functionCall, functionOutput)
    }

    private func toolToTextSummary(toolUse: [String: Any], toolResult: [String: Any]?) -> String {
        guard let toolName = toolUse["name"] as? String,
              let input = toolUse["input"] as? [String: Any] else {
            return "I used a tool."
        }

        switch toolName {
        case "Edit":
            let filePath = input["file_path"] as? String ?? "unknown file"
            return "I edited `\(filePath)` using the Edit tool."

        case "Read":
            let filePath = input["file_path"] as? String ?? "unknown file"
            let offset = input["offset"] as? Int
            let limit = input["limit"] as? Int

            if let offset = offset, let limit = limit {
                return "I read `\(filePath)` (lines \(offset) to \(offset + limit)) using the Read tool."
            } else if offset != nil || limit != nil {
                let rangeDesc = offset != nil ? "(from line \(offset!))" : "(limited)"
                return "I read `\(filePath)` \(rangeDesc) using the Read tool."
            } else {
                return "I read `\(filePath)` using the Read tool."
            }

        case "Write":
            let filePath = input["file_path"] as? String ?? "unknown file"
            let contentLen = (input["content"] as? String)?.count ?? 0
            return "I created/wrote `\(filePath)` (\(contentLen) characters) using the Write tool."

        case "Grep":
            let pattern = input["pattern"] as? String ?? "pattern"
            let path = input["path"] as? String ?? "."
            let outputMode = input["output_mode"] as? String ?? "files_with_matches"

            let resultContent = toolResult?["content"] as? String ?? ""
            let matchCount = resultContent.components(separatedBy: "\n").count

            if outputMode == "count" {
                return "I searched for `\(pattern)` in `\(path)` (count mode) using the Grep tool."
            } else if outputMode == "files_with_matches" {
                return "I searched for `\(pattern)` in `\(path)` and found \(matchCount) matching files using the Grep tool."
            } else {
                return "I searched for `\(pattern)` in `\(path)` using the Grep tool."
            }

        case "Glob":
            let pattern = input["pattern"] as? String ?? "pattern"
            let path = input["path"] as? String ?? "."

            let resultContent = toolResult?["content"] as? String ?? ""
            let matchCount = resultContent.components(separatedBy: "\n").count

            return "I found \(matchCount) files matching `\(pattern)` in `\(path)` using the Glob tool."

        default:
            return "I used the \(toolName) tool."
        }
    }

    // MARK: - Claude Code Message Conversion

    private func convertUserMessageToClaude(
        content: String,
        uuid: String,
        parentUuid: String?,
        gitContext: [String: String],
        sessionId: String,
        timestamp: String,
        to outputStream: OutputStream
    ) throws {
        let claudeMessage: [String: Any] = [
            "parentUuid": parentUuid ?? NSNull(),
            "isSidechain": false,
            "userType": "external",
            "cwd": gitContext["cwd"] ?? "/",
            "sessionId": sessionId,
            "version": "2.0.26",
            "gitBranch": gitContext["gitBranch"] ?? "main",
            "type": "user",
            "message": [
                "role": "user",
                "content": content
            ],
            "uuid": uuid,
            "timestamp": timestamp,
            "thinkingMetadata": [
                "level": "none",
                "disabled": true,
                "triggers": []
            ]
        ]

        try writeJSON(claudeMessage, to: outputStream)
    }

    private func convertAssistantMessageToClaude(
        content: String,
        uuid: String,
        parentUuid: String?,
        gitContext: [String: String],
        sessionId: String,
        timestamp: String,
        to outputStream: OutputStream
    ) throws {
        let claudeMessage: [String: Any] = [
            "parentUuid": parentUuid ?? NSNull(),
            "isSidechain": false,
            "userType": "external",
            "cwd": gitContext["cwd"] ?? "/",
            "sessionId": sessionId,
            "version": "2.0.26",
            "gitBranch": gitContext["gitBranch"] ?? "main",
            "message": [
                "model": "claude-sonnet-4-5-20250929",
                "id": "msg_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                "type": "message",
                "role": "assistant",
                "content": [
                    ["type": "text", "text": content]
                ],
                "stop_reason": NSNull(),
                "stop_sequence": NSNull(),
                "usage": [
                    "input_tokens": 100,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "cache_creation": [
                        "ephemeral_5m_input_tokens": 0,
                        "ephemeral_1h_input_tokens": 0
                    ],
                    "output_tokens": 50,
                    "service_tier": "standard"
                ]
            ],
            "requestId": "req_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            "type": "assistant",
            "uuid": uuid,
            "timestamp": timestamp
        ]

        try writeJSON(claudeMessage, to: outputStream)
    }

    // MARK: - Helpers

    private func loadRecords(from url: URL) throws -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url) else {
            throw ConversionError.fileNotFound(url.path)
        }

        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: .newlines)

        var records: [[String: Any]] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            guard let jsonData = trimmed.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw ConversionError.invalidJSON(line: idx + 1, error: "Invalid JSON")
            }

            records.append(record)
        }

        return records
    }

    private func extractContent(_ content: Any?, contentType: String, lineNumber: Int) throws -> (contentArray: [[String: Any]], textForEvent: String) {
        var contentArray: [[String: Any]] = []
        var textParts: [String] = []

        if let contentString = content as? String {
            contentArray = [["type": contentType, "text": contentString]]
            textParts = [contentString]
        } else if let contentBlocks = content as? [[String: Any]] {
            for block in contentBlocks {
                if let text = block["text"] as? String, !text.isEmpty {
                    contentArray.append(["type": contentType, "text": text])
                    textParts.append(text)
                }
            }
        }

        return (contentArray, textParts.joined(separator: "\n"))
    }

    private func validateCodexOutputPath(_ path: URL, sessionId: String) throws -> URL {
        let basename = path.lastPathComponent
        let pattern = #"^rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl$"#

        if basename.range(of: pattern, options: .regularExpression) != nil {
            return path
        }

        // Auto-correct to proper Codex format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone.current
        let timestamp = formatter.string(from: Date())

        let codexFilename = "rollout-\(timestamp)-\(sessionId).jsonl"

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)

        let codexDir = homeDir
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")
            .appendingPathComponent(String(year))
            .appendingPathComponent(String(format: "%02d", month))
            .appendingPathComponent(String(format: "%02d", day))

        try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let correctedPath = codexDir.appendingPathComponent(codexFilename)

        log("Warning: Output filename doesn't match Codex format")
        log("User provided: \(path.path)")
        log("Using instead: \(correctedPath.path)")

        return correctedPath
    }

    private func validateClaudeCodeOutputPath(_ path: URL, sessionId: String?) throws -> URL {
        let basename = path.lastPathComponent
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl$"#

        if basename.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return path
        }

        // Use session ID from Codex file if available
        let uuid = sessionId ?? UUID().uuidString.lowercased()
        let correctedFilename = "\(uuid).jsonl"
        let correctedPath = path.deletingLastPathComponent().appendingPathComponent(correctedFilename)

        log("Warning: Output filename '\(basename)' is not UUID format")
        log("Using instead: \(correctedFilename)")

        return correctedPath
    }

    private func writeJSON(_ object: [String: Any], to stream: OutputStream) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard var jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ConversionError.ioError("Cannot encode JSON to string")
        }

        jsonString += "\n"

        guard let data = jsonString.data(using: .utf8) else {
            throw ConversionError.ioError("Cannot encode string to data")
        }

        let bytesWritten = data.withUnsafeBytes { bufferPointer in
            stream.write(bufferPointer.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
        }

        if bytesWritten < 0 {
            throw ConversionError.ioError("Failed to write to output stream")
        }
    }

    private func toolUseIdToCallId(_ toolUseId: String) -> String {
        if toolUseId.hasPrefix("toolu_") {
            return "call_" + String(toolUseId.dropFirst(6))
        }
        return "call_" + toolUseId
    }

    private func callIdToToolUseId(_ callId: String) -> String {
        if callId.hasPrefix("call_") {
            return "toolu_" + String(callId.dropFirst(5))
        }
        return "toolu_" + callId
    }

    private func log(_ message: String) {
        if verbose {
            print("[DEBUG] \(message)")
        }
    }
}
