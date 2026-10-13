import XCTest
@testable import VerbVoxCore

/// Where the built-in engine keeps its downloaded models.
final class BackendPathsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "verbvox-backendpaths-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testModelsLiveInTheDefaultDataFolder() {
        XCTAssertEqual(BackendPaths.modelsDir(defaults),
                       BackendPaths.defaultRoot.appendingPathComponent("models", isDirectory: true))
    }

    func testModelsFolderCanBeOverridden() {
        defaults.set("/tmp/verbvox-models", forKey: "modelsDir")
        XCTAssertEqual(BackendPaths.modelsDir(defaults).path, "/tmp/verbvox-models")
    }
}
