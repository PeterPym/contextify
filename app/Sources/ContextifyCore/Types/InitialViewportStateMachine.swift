import Foundation

/// Tracks the lifecycle of the initial viewport snapshot handshake.
/// The state machine ensures fallback timers only fire once per `(project, session)` load.
public struct InitialViewportStateMachine {
  public struct Context: Equatable {
    public let projectId: String
    public let sessionId: String?

    public init(projectId: String, sessionId: String?) {
      self.projectId = projectId
      self.sessionId = sessionId
    }
  }

  public enum State: Equatable {
    case idle
    case awaiting(Context)
    case snapshotAccepted(Context)
  }

  public init() {}

  private(set) var state: State = .idle

  /// Returns `true` if we just entered the `.awaiting` state for a new context.
  @discardableResult
  public mutating func beginAwaiting(projectId: String, sessionId: String?) -> Bool {
    let context = Context(projectId: projectId, sessionId: sessionId)
    switch state {
    case .awaiting(context), .snapshotAccepted(context):
      return false
    default:
      state = .awaiting(context)
      return true
    }
  }

  /// Returns `true` when a snapshot for the provided context transitions the state to `.snapshotAccepted`.
  @discardableResult
  public mutating func acceptSnapshot(projectId: String, sessionId: String?) -> Bool {
    let context = Context(projectId: projectId, sessionId: sessionId)
    if case .snapshotAccepted(context) = state {
      return false
    }
    state = .snapshotAccepted(context)
    return true
  }

  public mutating func reset() {
    state = .idle
  }

  public var isAwaiting: Bool {
    if case .awaiting = state { return true }
    return false
  }

  public var isSnapshotAccepted: Bool {
    if case .snapshotAccepted = state { return true }
    return false
  }

  public var awaitingContext: Context? {
    if case .awaiting(let background) = state {
      return background
    }
    return nil
  }

  public var activeContext: Context? {
    switch state {
    case .awaiting(let context), .snapshotAccepted(let context):
      return context
    default:
      return nil
    }
  }
}
