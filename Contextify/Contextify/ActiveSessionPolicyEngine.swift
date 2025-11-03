import Foundation

/// Session identifier combining session ID and provider
public struct SessionKey: Equatable, Sendable, Hashable {
  public let sessionId: String
  public let provider: TimelineSourceContext.Provider

  public init(sessionId: String, provider: TimelineSourceContext.Provider) {
    self.sessionId = sessionId
    self.provider = provider
  }
}

/// Follow mode for active session tracking
public enum FollowMode: Equatable, Sendable {
  case automatic
  case manual(sessionId: String, provider: TimelineSourceContext.Provider)

  public var isAutomatic: Bool {
    if case .automatic = self { return true }
    return false
  }

  public var pinnedKey: SessionKey? {
    if case .manual(let sid, let prov) = self {
      return SessionKey(sessionId: sid, provider: prov)
    }
    return nil
  }
}

/// Reason for session switch
public enum SwitchReason: String, Sendable {
  case newerWrite
  case manualSelection
  case unpinToAuto
  case projectChange
  case pinnedMissing
}

/// Decision from policy engine
public struct Decision: Equatable, Sendable {
  public let nextActive: SessionKey?
  public let shouldEmitMessage: Bool
  public let reason: SwitchReason?

  public init(nextActive: SessionKey?, shouldEmitMessage: Bool, reason: SwitchReason?) {
    self.nextActive = nextActive
    self.shouldEmitMessage = shouldEmitMessage
    self.reason = reason
  }
}

/// Pure policy engine for active session decisions
/// Handles automatic follow mode, manual pinning, and global cooldown
public struct ActiveSessionPolicyEngine: Sendable {
  public struct Inputs: Equatable, Sendable {
    public let followMode: FollowMode
    public let lastActiveKey: SessionKey?
    public let newestCandidate: SessionKey?
    public let now: Date
    public let lastSwitchAt: Date?
    public let cooldown: TimeInterval

    public init(
      followMode: FollowMode,
      lastActiveKey: SessionKey?,
      newestCandidate: SessionKey?,
      now: Date,
      lastSwitchAt: Date?,
      cooldown: TimeInterval
    ) {
      self.followMode = followMode
      self.lastActiveKey = lastActiveKey
      self.newestCandidate = newestCandidate
      self.now = now
      self.lastSwitchAt = lastSwitchAt
      self.cooldown = cooldown
    }
  }

  public init() {}

  /// Decide next active session based on policy and cooldown
  /// Global cooldown suppresses message emission (but still switches session)
  public func decide(inputs: Inputs) -> Decision {
    // Determine target session based on follow mode
    let target: SessionKey? = {
      switch inputs.followMode {
      case .automatic:
        return inputs.newestCandidate
      case .manual(let sid, let prov):
        return SessionKey(sessionId: sid, provider: prov)
      }
    }()

    // No target available
    guard let target else {
      return Decision(nextActive: nil, shouldEmitMessage: false, reason: nil)
    }

    // Already at target
    guard inputs.lastActiveKey != target else {
      return Decision(nextActive: nil, shouldEmitMessage: false, reason: nil)
    }

    // Global cooldown: suppress message emission if ANY switch occurred recently
    if let lastSwitch = inputs.lastSwitchAt,
       inputs.now.timeIntervalSince(lastSwitch) < inputs.cooldown {
      // Still switch session, but don't emit message
      return Decision(nextActive: target, shouldEmitMessage: false, reason: .newerWrite)
    }

    // Switch and emit message
    return Decision(nextActive: target, shouldEmitMessage: true, reason: .newerWrite)
  }
}
