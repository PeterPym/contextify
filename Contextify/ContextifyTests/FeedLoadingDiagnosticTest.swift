import XCTest
@testable import Contextify
@testable import ContextifyCore

/// Diagnostic test to understand why UI shows empty entries
final class FeedLoadingDiagnosticTest: XCTestCase {

    @MainActor
    func testLoadRealDatabaseAndInspect() async throws {
        print("\n========== FEED LOADING DIAGNOSTIC ==========\n")

        // Use the real database
        let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

        // List all projects
        let projects = try orchestrator.listProjects()
        print("📁 Projects in database: \(projects.count)")
        for project in projects {
            print("  - \(project.name ?? "unnamed"): \(project.rootPath)")
        }

        guard let project = projects.first else {
            XCTFail("No projects in database")
            return
        }

        print("\n🎯 Using project: \(project.name ?? project.id)")

        // Get transcripts
        let transcripts = try orchestrator.getTranscripts(forProject: project.id)
        print("\n📚 Transcripts: \(transcripts.count)")
        for transcript in transcripts.prefix(3) {
            print("  - \(transcript.filePath)")
            print("    Provider: \(transcript.provider)")
            print("    Status: \(transcript.status)")
        }

        // Get entries
        let allEntries = try orchestrator.getRecentEntries(forProject: project.id, limit: 50)
        print("\n📝 Entries: \(allEntries.count)")
        for entry in allEntries.prefix(5) {
            print("  - ID: \(entry.id)")
            print("    Kind: \(entry.kind)")
            print("    Content length: \(entry.content.count)")
            print("    Content preview: \(String(entry.content.prefix(60)))...")
            print("    Has windowSha256: \(entry.windowSha256 != nil)")
        }

        // Get feed with cache
        let feed = try orchestrator.getRecentFeed(
            forProject: project.id,
            limit: 50,
            generatorSignature: timelineGeneratorSignature()
        )

        print("\n📊 Feed (entries + cache): \(feed.count)")
        var withCache = 0
        var withoutCache = 0

        for (entry, cache) in feed.prefix(10) {
            if let cache = cache {
                withCache += 1
                print("  ✅ Entry \(entry.id) HAS cache:")
                print("     Present: \(String(cache.presentForm.prefix(60)))...")
                print("     Selected: \(cache.selectedForm)")
            } else {
                withoutCache += 1
                print("  ❌ Entry \(entry.id) NO cache")
                print("     Content: \(String(entry.content.prefix(60)))...")
            }
        }

        print("\n📈 Cache stats: \(withCache) with cache, \(withoutCache) without")

        // Now test the mapping
        print("\n🔄 Testing toTimelineEntry mapping...")

        let monitor = ConversationMonitor.shared

        // Manually map a few entries
        for (entry, cache) in feed.prefix(3) {
            // We need to access the private method, so let's just simulate what it does
            let summary: String
            let action: String
            if let cache = cache {
                if cache.userEdited == 1, let userText = cache.userText, !userText.isEmpty {
                    summary = userText
                } else {
                    summary = cache.selectedForm == "present" ? cache.presentForm : cache.pastForm
                }
                action = "none"
            } else {
                summary = String(entry.content.prefix(100)) + (entry.content.count > 100 ? "…" : "")
                action = "generating"
            }

            print("\n  Entry \(entry.id):")
            print("    Summary length: \(summary.count)")
            print("    Summary: \(String(summary.prefix(80)))...")
            print("    Action: \(action)")
            print("    Detail length: \(entry.content.count)")
        }

        print("\n========== END DIAGNOSTIC ==========\n")

        // Assert something so test framework knows we ran
        XCTAssertGreaterThan(feed.count, 0, "Feed should have entries")
    }
}
