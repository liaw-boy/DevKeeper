import XCTest
@testable import DevKeeperCore

final class PythonLogicTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }
    
    func testLifecycleStatuses() {
        let now = date(2026, 10, 23)
        XCTAssertEqual(PythonLifecycle.status(forMinor: "3.9", now: now), .endOfLife("2025-10-31"))
        XCTAssertEqual(PythonLifecycle.status(forMinor: "3.10", now: now), .endOfLife("2026-10-01"))
        XCTAssertEqual(PythonLifecycle.status(forMinor: "3.11", now: now), .supported("2027-10"))
        XCTAssertEqual(PythonLifecycle.status(forMinor: "3.12", now: now), .supported("2028-10"))
        XCTAssertTrue(PythonLifecycle.isEndOfLife(minor: "3.7", now: now))
        // Versions newer than the table have no date yet and count as supported.
        XCTAssertFalse(PythonLifecycle.isEndOfLife(minor: "3.99", now: now))
    }
    
    func testEndingSoonWithinOneYear() {
        let now = date(2027, 6, 1)
        XCTAssertEqual(PythonLifecycle.status(forMinor: "3.11", now: now), .endingSoon("2027-10"))
    }
    
    private func interpreter(_ version: String, source: PythonSource = .uv, managed: Bool = false, pip: Bool = true) -> PythonInterpreter {
        PythonInterpreter(path: "/py/\(version)", version: version, source: source, isExternallyManaged: managed, hasPip: pip)
    }
    
    func testAutomaticChoicePrefersSupportedAndWritable() {
        let list = [interpreter("3.13.1", managed: true), interpreter("3.11.9"), interpreter("3.9.6", source: .system)]
        XCTAssertEqual(InterpreterChoice.automatic(from: list)?.version, "3.11.9")
    }
    
    func testAutomaticChoiceFallsBackToManagedThenOld() {
        XCTAssertEqual(InterpreterChoice.automatic(from: [interpreter("3.13.1", managed: true), interpreter("3.9.6", source: .system)])?.version, "3.13.1")
        XCTAssertEqual(InterpreterChoice.automatic(from: [interpreter("3.9.6", source: .system)])?.version, "3.9.6")
        XCTAssertNil(InterpreterChoice.automatic(from: [interpreter("3.12.1", pip: false)]))
    }
    
    func testMigrationTarget() {
        XCTAssertEqual(InterpreterChoice.migrationTarget(from: [interpreter("3.13.1")], uvAvailable: false), "/py/3.13.1")
        XCTAssertEqual(InterpreterChoice.migrationTarget(from: [interpreter("3.9.6", source: .system)], uvAvailable: true), PythonLifecycle.recommendedMinor)
        XCTAssertNil(InterpreterChoice.migrationTarget(from: [interpreter("3.9.6", source: .system)], uvAvailable: false))
    }
    
    func testAppleAndDistroBundledLocations() {
        XCTAssertTrue(PythonEnvironmentService.isAppleBundledLocation("/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/x"))
        XCTAssertTrue(PythonEnvironmentService.isAppleBundledLocation("/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/x"))
        XCTAssertTrue(PythonEnvironmentService.isAppleBundledLocation("/usr/lib/python3/dist-packages"))
        XCTAssertFalse(PythonEnvironmentService.isAppleBundledLocation("/Users/me/Library/Python/3.9/lib/python/site-packages"))
        XCTAssertFalse(PythonEnvironmentService.isAppleBundledLocation("/usr/local/lib/python3.11/dist-packages"))
        XCTAssertFalse(PythonEnvironmentService.isAppleBundledLocation(nil))
    }
    
    // MARK: dependency graph
    
    private func graph() -> PythonDependencyGraph {
        // tool -> lib -> leaf ; shared is needed by tool and other ; pip is base tooling
        let names = ["tool": "tool", "lib": "lib", "leaf": "leaf", "shared": "shared", "other": "other", "pip": "pip"]
        let requires: [String: Set<String>] = ["tool": ["lib", "shared"], "lib": ["leaf"], "other": ["shared"]]
        var requiredBy: [String: Set<String>] = [:]
        for (pkg, deps) in requires { for d in deps { requiredBy[d, default: []].insert(pkg) } }
        return PythonDependencyGraph(names: names, requires: requires, requiredBy: requiredBy)
    }
    
    func testOwningRoots() {
        let g = graph()
        XCTAssertEqual(g.owningRoots(of: "leaf"), ["tool"])
        XCTAssertEqual(g.owningRoots(of: "shared"), ["tool", "other"])
        XCTAssertEqual(g.owningRoots(of: "tool"), ["tool"])
    }
    
    func testRemovalClosureKeepsSharedDependencies() {
        let g = graph()
        let removed = g.removalClosure(seeds: ["tool"])
        XCTAssertEqual(removed, ["tool", "lib", "leaf"], "shared stays because 'other' still needs it")
        XCTAssertEqual(g.removalClosure(seeds: ["tool", "other"]), ["tool", "other", "lib", "leaf", "shared"])
    }
    
    func testBaseToolingIsNeverARootOrRemoved() {
        let g = graph()
        XCTAssertFalse(g.roots.contains("pip"))
        XCTAssertTrue(PythonDependencyGraph.baseTooling.contains("setuptools"))
        XCTAssertEqual(PythonDependencyGraph.normalize("Zope_Interface.X"), "zope-interface-x")
    }
}
