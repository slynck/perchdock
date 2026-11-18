import Foundation
import Testing
@testable import PerchDock

/// Folder stack ordering, filtering and limits, using isolated files with fixed dates.
@MainActor
@Suite("Folder stack entries")
struct StackServiceTests {
    /// Files are ordered by recency, independently of their names and creation order.
    @Test("Newest files come first")
    func newestFirst() throws {
        try withTemporaryFolder { objFolder in
            let objOldest = try file(in: objFolder, strName: "a-oldest.txt", intAddedOrder: 1)
            let objNewest = try file(in: objFolder, strName: "m-newest.txt", intAddedOrder: 3)
            let objMiddle = try file(in: objFolder, strName: "z-middle.txt", intAddedOrder: 2)

            // Enumeration may spell /var as /private/var, so compare standardized file URLs.
            let arrObjEntries = StackService.newestEntries(in: objFolder).map(\.standardizedFileURL)
            #expect(arrObjEntries == [objNewest, objMiddle, objOldest])
        }
    }

    /// An older file added more recently wins over a recently modified file added earlier.
    @Test("Date added takes precedence over modification date")
    func addedDateWins() throws {
        try withTemporaryFolder { objFolder in
            let objRecentlyModified = try file(
                in: objFolder, strName: "modified.txt", intAddedOrder: 1, intModifiedOrder: 3)
            let objRecentlyAdded = try file(
                in: objFolder, strName: "added.txt", intAddedOrder: 3, intModifiedOrder: 1)

            let arrObjEntries = StackService.newestEntries(in: objFolder).map(\.standardizedFileURL)
            #expect(arrObjEntries == [objRecentlyAdded, objRecentlyModified])
        }
    }

    /// A hidden file must be excluded even when it is the newest entry.
    @Test("Hidden files are skipped")
    func skipsHiddenFiles() throws {
        try withTemporaryFolder { objFolder in
            let objVisible = try file(in: objFolder, strName: "visible.txt", intAddedOrder: 1)
            _ = try file(in: objFolder, strName: ".hidden.txt", intAddedOrder: 2)

            let arrObjEntries = StackService.newestEntries(in: objFolder).map(\.standardizedFileURL)
            #expect(arrObjEntries == [objVisible])
        }
    }

    /// The cap keeps the newest twenty files, rather than an arbitrary twenty directory entries.
    @Test("Only the newest 20 of 25 files are returned")
    func keepsNewestTwenty() throws {
        try withTemporaryFolder { objFolder in
            for intIndex in 0..<25 {
                _ = try file(in: objFolder, strName: "file-\(intIndex).txt", intAddedOrder: intIndex)
            }
            let arrObjExpected = (5..<25).reversed().map { objFolder.appendingPathComponent("file-\($0).txt") }

            let arrObjEntries = StackService.newestEntries(in: objFolder).map(\.standardizedFileURL)
            #expect(arrObjEntries == arrObjExpected)
        }
    }

    /// A directory with no files produces no stack tiles.
    @Test("An empty folder returns no entries")
    func emptyFolder() throws {
        try withTemporaryFolder { objFolder in
            #expect(StackService.newestEntries(in: objFolder).isEmpty)
        }
    }

    /// A deleted or unavailable folder is handled like an empty folder.
    @Test("A missing folder returns no entries")
    func missingFolder() throws {
        try withTemporaryFolder { objFolder in
            let objMissing = objFolder.appendingPathComponent("missing", isDirectory: true)
            #expect(StackService.newestEntries(in: objMissing).isEmpty)
        }
    }

    /// Creates a unique directory and removes it even when the test body throws.
    /// - Parameter fnTest: Assertions and fixture creation within the temporary directory.
    private func withTemporaryFolder(_ fnTest: (URL) throws -> Void) throws {
        let objFolder = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("perchdock-stack-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: objFolder, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: objFolder) }
            catch { Issue.record(error) }
        }
        try fnTest(objFolder)
    }

    /// Writes a file with independent, fixed date-added and modification timestamps.
    /// - Parameters:
    ///   - objFolder: Directory that owns the file.
    ///   - strName: File name, including any leading dot.
    ///   - intAddedOrder: Seconds after the fixed reference date when the file was added.
    ///   - intModifiedOrder: Modification offset; defaults to the added offset.
    /// - Returns: The file's URL.
    private func file(
        in objFolder: URL, strName: String, intAddedOrder: Int, intModifiedOrder: Int? = nil
    ) throws -> URL {
        let objUrl = objFolder.appendingPathComponent(strName)
        let objReference = Date(timeIntervalSince1970: 1_700_000_000)
        let objModified = objReference.addingTimeInterval(Double(intModifiedOrder ?? intAddedOrder))
        let objAdded = objReference.addingTimeInterval(Double(intAddedOrder))
        try Data("fixture".utf8).write(to: objUrl)
        try FileManager.default.setAttributes([.modificationDate: objModified], ofItemAtPath: objUrl.path)
        // APFS supplies a date-added value, so changing only modification time would not control the sort.
        try (objUrl as NSURL).setResourceValue(objAdded, forKey: .addedToDirectoryDateKey)
        return objUrl
    }
}
