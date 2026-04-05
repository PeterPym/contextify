// SPDX-License-Identifier: MIT
// CloudCommandBridge.swift - Public entry point for CloudCommand from external modules

import ArgumentParser

/// Public entry point that lets ContextifyQueryCLI dispatch to CloudCommand
/// without CloudCommand itself needing public access modifiers.
public enum CloudCommandBridge {
  /// Run the cloud command with the given arguments.
  /// Arguments should NOT include the binary name or "cloud" prefix.
  /// Example: for `contextify cloud status`, pass `["status"]`.
  public static func run(_ arguments: [String]) {
    CloudCommand.main(arguments)
  }
}
