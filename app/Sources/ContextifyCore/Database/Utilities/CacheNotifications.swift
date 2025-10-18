//
//  CacheNotifications.swift
//  ContextifyCore
//
//  Standardized notification names for cache updates
//

import Foundation

public extension NSNotification.Name {
    /// Posted when timeline entry cache is updated
    /// - Object: CacheKey struct
    /// - UserInfo: None
    static let timelineCacheUpdated = NSNotification.Name("TimelineCacheUpdated")

    /// Posted when transcript metadata is updated
    /// - Object: String (transcript_id)
    /// - UserInfo: None
    static let transcriptMetadataUpdated = NSNotification.Name("TranscriptMetadataUpdated")

    /// Posted when transcript file is updated (for file watcher)
    /// - Object: String (transcript_id)
    /// - UserInfo: ["projectId": String]
    static let transcriptFileUpdated = NSNotification.Name("TranscriptFileUpdated")
}
