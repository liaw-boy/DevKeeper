import XCTest
@testable import DevKeeperCore

final class FixSafetyTests: XCTestCase {
    func testParsesPipAndUVConflictLines() {
        let pip = """
        demo-app 0.5.0 has requirement filelock<4,>=3.13, but you have filelock 4.2.4.
        wheel 0.48.0 requires packaging, which is not installed.
        """
        let uv = """
        Checked 154 packages in 1ms
        Found 1 incompatibility
        The package `demo-lib` requires `filelock>=3.16.1,<4.0`, but `4.2.4` is installed
        """
        XCTAssertEqual(DependencyCheck.conflicts(in: pip).count, 2)
        XCTAssertEqual(DependencyCheck.conflicts(in: uv), ["The package `demo-lib` requires `filelock>=3.16.1,<4.0`, but `4.2.4` is installed"])
        XCTAssertTrue(DependencyCheck.conflicts(in: "No broken requirements found.").isEmpty)
        XCTAssertTrue(DependencyCheck.conflicts(in: "Checked 17 packages in 0.4ms\nAll installed packages are compatible").isEmpty)
    }
    
    func testOnlyNewConflictsCountAsCausedByTheUpgrade() {
        let before = DependencyCheck.conflicts(in: "The package `demo-suite` requires `setuptools>=76.0.0,<80.0.0`, but `84.0.0` is installed")
        let after = DependencyCheck.conflicts(in: """
        The package `demo-suite` requires `setuptools>=76.0.0,<80.0.0`, but `84.0.0` is installed
        The package `demo-tool` requires `libbaz>=3.1.1,<4`, but `4.1.3` is installed
        """)
        XCTAssertEqual(after.subtracting(before), ["The package `demo-tool` requires `libbaz>=3.1.1,<4`, but `4.1.3` is installed"])
    }
    
    func testPythonFixesPinTheMinimumSafeVersion() {
        let env = PythonEnvironmentRef(kind: .uvTool, pythonPath: "/t/bin/python", toolName: "t", label: "uv tool：t")
        let cmd = FixCommandBuilder.command(packageName: "filelock", ecosystem: "PyPI", targetVersion: "3.20.1", projectPath: nil, environment: env)
        XCTAssertEqual(cmd, "uv pip install --python '/t/bin/python' \"filelock==3.20.1\"")
        XCTAssertFalse(cmd.contains(">="))
        XCTAssertFalse(cmd.contains("--upgrade"))
    }
    
    func testHistoryRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("fix-history.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = FixHistory.Entry(date: date, packageName: "filelock", ecosystem: "PyPI", environment: "uv tool：t",
                                     pythonPath: "/t/bin/python", fromVersion: "3.19.0", toVersion: "3.19.0",
                                     result: "rolledBack", detail: "x")
        let second = FixHistory.Entry(date: date, packageName: "lodash", ecosystem: "npm", environment: "全域",
                                      pythonPath: nil, fromVersion: "4.17.20", toVersion: "4.17.21", result: "fixed", detail: nil)
        FixHistory.record(first, to: url)
        FixHistory.record(second, to: url)
        XCTAssertEqual(FixHistory.load(from: url), [first, second])
    }
}
