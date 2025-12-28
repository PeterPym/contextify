import Foundation

public struct TailScanResult: Sendable {
  public let approxNewEntries: Int?
  public let confidence: Confidence?
  public let tailLastEntryTs: Double?
  public let scannedBytes: Int
  public let totalLinesScanned: Int
  public let parseErrors: Int
  public let timedOut: Bool

  public enum Confidence: String, Sendable {
    case high
    case medium
    case low
  }
}

public actor TranscriptTailScanner {
  private let maxTailBytes: Int
  private let hardTimeoutMs: Int
  private let iso8601FormatterWithFractional: ISO8601DateFormatter
  private let iso8601FormatterStandard: ISO8601DateFormatter

  public init(maxTailBytes: Int = 65536, hardTimeoutMs: Int = 50) {
    self.maxTailBytes = maxTailBytes
    self.hardTimeoutMs = hardTimeoutMs
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    self.iso8601FormatterWithFractional = fractional
    self.iso8601FormatterStandard = standard
  }

  public func scanTail(
    fileURL: URL,
    baselineLastEntryTs: Double,
    baselineFileSize: Int64?,
    provider: String
  ) async -> TailScanResult {
    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let handle = try FileHandle(forReadingFrom: fileURL)
      defer { try? handle.close() }

      let fileSize = try handle.seekToEnd()
      if let baselineFileSize,
         fileSize < UInt64(baselineFileSize) {
        return TailScanResult(
          approxNewEntries: nil,
          confidence: nil,
          tailLastEntryTs: nil,
          scannedBytes: 0,
          totalLinesScanned: 0,
          parseErrors: 0,
          timedOut: false
        )
      }

      let tailSize = min(maxTailBytes, Int(fileSize))
      if tailSize <= 0 {
        return TailScanResult(
          approxNewEntries: nil,
          confidence: nil,
          tailLastEntryTs: nil,
          scannedBytes: 0,
          totalLinesScanned: 0,
          parseErrors: 0,
          timedOut: false
        )
      }

      let startOffset = UInt64(fileSize) - UInt64(tailSize)
      try handle.seek(toOffset: startOffset)
      let data = try handle.readToEnd() ?? Data()

      return scanTail(
        data: data,
        fileSize: Int64(fileSize),
        baselineLastEntryTs: baselineLastEntryTs,
        baselineFileSize: baselineFileSize,
        provider: provider,
        startTime: startTime
      )
    } catch {
      return TailScanResult(
        approxNewEntries: nil,
        confidence: .low,
        tailLastEntryTs: nil,
        scannedBytes: 0,
        totalLinesScanned: 0,
        parseErrors: 1,
        timedOut: false
      )
    }
  }

  public func scanTail(
    data: Data,
    fileSize: Int64,
    baselineLastEntryTs: Double,
    baselineFileSize: Int64?,
    provider: String
  ) async -> TailScanResult {
    let startTime = CFAbsoluteTimeGetCurrent()
    return scanTail(
      data: data,
      fileSize: fileSize,
      baselineLastEntryTs: baselineLastEntryTs,
      baselineFileSize: baselineFileSize,
      provider: provider,
      startTime: startTime
    )
  }

  private func scanTail(
    data: Data,
    fileSize: Int64,
    baselineLastEntryTs: Double,
    baselineFileSize: Int64?,
    provider: String,
    startTime: CFAbsoluteTime
  ) -> TailScanResult {
    guard let tailString = String(data: data, encoding: .utf8) else {
      return TailScanResult(
        approxNewEntries: nil,
        confidence: .low,
        tailLastEntryTs: nil,
        scannedBytes: data.count,
        totalLinesScanned: 0,
        parseErrors: 1,
        timedOut: false
      )
    }

    let tailSize = min(maxTailBytes, Int(fileSize))
    var lines = tailString.split(separator: "\n", omittingEmptySubsequences: false)
    if fileSize > Int64(tailSize), !lines.isEmpty {
      lines.removeFirst()
    }

    var validNewEntries = 0
    var parseErrors = 0
    var totalLinesScanned = 0
    var tailLastEntryTs: Double?
    var timedOut = false

    for line in lines {
      if CFAbsoluteTimeGetCurrent() - startTime > Double(hardTimeoutMs) / 1000.0 {
        timedOut = true
        break
      }

      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      totalLinesScanned += 1

      guard let timestamp = parseTimestamp(from: trimmed, provider: provider) else {
        parseErrors += 1
        continue
      }

      let tsSeconds = timestamp.timeIntervalSince1970
      tailLastEntryTs = max(tailLastEntryTs ?? tsSeconds, tsSeconds)
      if tsSeconds > baselineLastEntryTs {
        validNewEntries += 1
      }
    }

    let errorRate = totalLinesScanned > 0
      ? Double(parseErrors) / Double(totalLinesScanned)
      : 1.0

    var approxNewEntries: Int? = validNewEntries > 0 ? validNewEntries : nil
    var confidence: TailScanResult.Confidence?

    if totalLinesScanned == 0 {
      confidence = .low
    } else if errorRate > 0.50 {
      confidence = .low
    } else if validNewEntries >= 5 && errorRate < 0.10 {
      confidence = .high
    } else if validNewEntries >= 1 && errorRate < 0.30 {
      confidence = .medium
    } else if let baselineFileSize {
      let growthBytes = fileSize - baselineFileSize
      if growthBytes >= 10 * 1024 {
        let estimate = max(1, min(50, Int(growthBytes / 1500)))
        approxNewEntries = estimate
        confidence = .medium
      } else {
        confidence = .low
      }
    } else {
      confidence = .low
    }

    if confidence == .low {
      approxNewEntries = nil
    }

    return TailScanResult(
      approxNewEntries: approxNewEntries,
      confidence: confidence,
      tailLastEntryTs: tailLastEntryTs,
      scannedBytes: data.count,
      totalLinesScanned: totalLinesScanned,
      parseErrors: parseErrors,
      timedOut: timedOut
    )
  }

  private func parseTimestamp(from line: String, provider: String) -> Date? {
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let timestampStr = json["timestamp"] as? String else {
      return nil
    }

    return iso8601FormatterWithFractional.date(from: timestampStr)
      ?? iso8601FormatterStandard.date(from: timestampStr)
  }
}
