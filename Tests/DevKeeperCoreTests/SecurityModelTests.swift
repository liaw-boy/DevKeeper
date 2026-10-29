import XCTest
@testable import DevKeeperCore

final class SecurityModelTests: XCTestCase {
    private func vuln(_ name: String, eco: String = "PyPI", cur: String = "1.0.0", fixed: String? = "2.0.0",
                      id: String = "V1", env: PythonEnvironmentRef? = nil, severity: VulnerabilitySeverity = .high) -> VulnerabilityItem {
        VulnerabilityItem(id: id, cveId: "CVE-\(id)", packageName: name, ecosystem: eco, currentVersion: cur,
                          fixedVersion: fixed, severity: severity, summary: "", details: "", environment: env)
    }
    
    private func interpreterEnv(_ path: String) -> PythonEnvironmentRef {
        PythonEnvironmentRef(kind: .interpreter, pythonPath: path, label: path)
    }
    
    func testFixCommandsAreQuotedAndValidated() {
        let env = interpreterEnv("/opt/my py/bin/python3")
        let cmd = FixCommandBuilder.command(packageName: "anyio", ecosystem: "PyPI", targetVersion: "4.14.2", projectPath: nil, environment: env)
        XCTAssertEqual(cmd, "'/opt/my py/bin/python3' -m pip install \"anyio==4.14.2\"")
        XCTAssertEqual(FixCommandBuilder.command(packageName: "a$(id)", ecosystem: "npm", targetVersion: "1.0", projectPath: nil), "")
        XCTAssertEqual(FixCommandBuilder.command(packageName: "x", ecosystem: "PyPI", targetVersion: "1; ls", projectPath: nil), "")
        XCTAssertEqual(FixCommandBuilder.command(packageName: "lodash", ecosystem: "npm", targetVersion: "4.17.21", projectPath: nil), "npm install -g lodash@4.17.21")
        XCTAssertEqual(FixCommandBuilder.command(packageName: "go", ecosystem: "Go", targetVersion: nil, projectPath: nil), "")
        XCTAssertEqual(FixCommandBuilder.command(packageName: "x", ecosystem: "PyPI", targetVersion: "1.0", projectPath: "/proj"), "", "project dependencies are not fixed automatically")
    }
    
    func testUvToolFixUpgradesOnlyThePackage() {
        let env = PythonEnvironmentRef(kind: .uvTool, pythonPath: "/t/bin/python", toolName: "big-tool", label: "uv tool")
        let cmd = FixCommandBuilder.command(packageName: "pillow", ecosystem: "PyPI", targetVersion: "13.0.0", projectPath: nil, environment: env)
        XCTAssertEqual(cmd, "uv pip install --python '/t/bin/python' \"pillow==13.0.0\"")
        XCTAssertFalse(cmd.contains("uv tool upgrade"))
    }
    
    func testGroupMergesEnvironmentsAndKeepsOneTargetEach() {
        let a = interpreterEnv("/py/a"), b = interpreterEnv("/py/b")
        let items = [vuln("anyio", cur: "4.12.1", env: a), vuln("anyio", cur: "4.13.0", env: b), vuln("anyio", cur: "4.13.0", id: "V2", env: b)]
        let groups = PackageVulnerabilityGroup.grouped(from: items)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].fixTargets.count, 2)
        XCTAssertEqual(groups[0].currentVersion, "4.12.1")
        XCTAssertEqual(groups[0].targetSafeVersion, "2.0.0")
        XCTAssertEqual(groups[0].cveList.count, 2)
        XCTAssertEqual(groups[0].fixCommands.count, 2)
    }
    
    func testGroupsAreSortedBySeverity() {
        let items = [vuln("low-pkg", severity: .low), vuln("crit-pkg", id: "V2", severity: .critical), vuln("med-pkg", id: "V3", severity: .medium)]
        XCTAssertEqual(PackageVulnerabilityGroup.grouped(from: items).map { $0.packageName }, ["crit-pkg", "med-pkg", "low-pkg"])
    }
    
    func testBuiltInExceptionOnlyForOSPythonBaseTooling() {
        let os = PythonInterpreter(path: "/usr/bin/python3", version: "3.9.6", source: .system, isExternallyManaged: false, hasPip: true)
        let brew = PythonInterpreter(path: "/opt/py", version: "3.12.1", source: .homebrew, isExternallyManaged: true, hasPip: true)
        let envOS = interpreterEnv("/usr/bin/python3"), envBrew = interpreterEnv("/opt/py")
        XCTAssertTrue(AuditEngine.isBuiltInException(vuln("pip", env: envOS), interpreters: [os, brew]))
        XCTAssertTrue(AuditEngine.isBuiltInException(vuln("Setuptools", env: envOS), interpreters: [os, brew]))
        XCTAssertFalse(AuditEngine.isBuiltInException(vuln("requests", env: envOS), interpreters: [os, brew]), "user packages are still audited")
        XCTAssertFalse(AuditEngine.isBuiltInException(vuln("pip", env: envBrew), interpreters: [os, brew]))
        XCTAssertFalse(AuditEngine.isBuiltInException(vuln("pip"), interpreters: [os, brew]))
    }
    
    func testOsvUrlsAreRestricted() {
        XCTAssertNotNil(VulnerabilityItem.osvUrl(for: "GHSA-6q48-6c7w-9gw2"))
        XCTAssertNil(VulnerabilityItem.osvUrl(for: "../../etc/passwd"))
        XCTAssertNil(VulnerabilityItem.osvUrl(for: ""))
    }
}

final class AptParsingTests: XCTestCase {
    func testParseUpgradable() {
        let output = """
        Listing... Done
        curl/jammy-updates,jammy-security 7.81.0-1ubuntu1.18 amd64 [upgradable from: 7.81.0-1ubuntu1.16]
        libssl3/jammy-updates 3.0.2-0ubuntu1.18 amd64 [upgradable from: 3.0.2-0ubuntu1.15]
        weird line without marker
        """
        let parsed = AptService.parseUpgradable(output)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].name, "curl")
        XCTAssertEqual(parsed[0].newVersion, "7.81.0-1ubuntu1.18")
        XCTAssertEqual(parsed[0].currentVersion, "7.81.0-1ubuntu1.16")
        XCTAssertEqual(parsed[1].name, "libssl3")
    }
    
    func testParseIgnoresInvalidNames() {
        XCTAssertTrue(AptService.parseUpgradable("a;b/x 1.0 amd64 [upgradable from: 0.9]").isEmpty)
    }
}
