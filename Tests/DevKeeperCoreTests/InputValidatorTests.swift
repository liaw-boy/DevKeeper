import XCTest
@testable import DevKeeperCore

final class InputValidatorTests: XCTestCase {
    func testPackageNamesAcceptNormalNames() {
        for name in ["requests", "lodash", "@scope/pkg", "python-dateutil", "zope.interface", "a+b"] {
            XCTAssertTrue(InputValidator.isValidPackageName(name), name)
        }
    }
    
    func testPackageNamesRejectShellMetacharacters() {
        for name in ["foo; rm -rf ~", "x$(id)", "`id`", "a b", "-rf", "a|b", "a&b", "a>b", "foo\n", "", "a\"b", "a'b"] {
            XCTAssertFalse(InputValidator.isValidPackageName(name), name.debugDescription)
        }
    }
    
    func testVersions() {
        XCTAssertTrue(InputValidator.isValidVersion("3.13"))
        XCTAssertTrue(InputValidator.isValidVersion("1.2.3rc1"))
        XCTAssertFalse(InputValidator.isValidVersion("3.13\n"))
        XCTAssertFalse(InputValidator.isValidVersion("1.0; ls"))
        XCTAssertFalse(InputValidator.isValidVersion("-1"))
    }
    
    func testRepoComponentsRejectPathTricks() {
        XCTAssertTrue(InputValidator.isValidRepoComponent("my.repo-1"))
        for bad in ["..", ".", "a/b", "x y", "", "a;b"] {
            XCTAssertFalse(InputValidator.isValidRepoComponent(bad), bad)
        }
    }
    
    func testHttpsURLChecksSchemeAndHost() {
        let hosts = ["github.com"]
        XCTAssertNotNil(InputValidator.httpsURL("https://github.com/a/b", allowedHosts: hosts))
        XCTAssertNotNil(InputValidator.httpsURL("https://objects.github.com/x", allowedHosts: hosts))
        for bad in ["http://github.com/a", "file:///etc/passwd", "https://evil.com/?github.com",
                    "https://github.com.evil.com/x", "javascript:alert(1)", "https://evilgithub.com/"] {
            XCTAssertNil(InputValidator.httpsURL(bad, allowedHosts: hosts), bad)
        }
        XCTAssertNotNil(InputValidator.httpsURL("https://example.org/x"))
    }
    
    func testShellQuotedEscapesSingleQuotes() {
        XCTAssertEqual(InputValidator.shellQuoted("/a b/it's"), "'/a b/it'\\''s'")
        XCTAssertEqual(InputValidator.shellQuoted("plain"), "'plain'")
    }
}

final class TrailingNewlineTests: XCTestCase {
    /// `$` can match before a trailing newline on some platforms; validators must reject it everywhere.
    func testValidatorsRejectTrailingAndEmbeddedNewlines() {
        for value in ["foo\n", "foo\r\n", "foo\nbar", "\nfoo", "3.13\n"] {
            XCTAssertFalse(InputValidator.isValidPackageName(value), value.debugDescription)
            XCTAssertFalse(InputValidator.isValidVersion(value), value.debugDescription)
            XCTAssertFalse(InputValidator.isValidRepoComponent(value), value.debugDescription)
        }
        XCTAssertNil(VulnerabilityItem.osvUrl(for: "GHSA-12\n34"))  // embedded newline; surrounding whitespace is trimmed on purpose
        XCTAssertFalse(InputValidator.fullyMatches("3.13\n", pattern: #"3\.\d+"#))
        XCTAssertTrue(InputValidator.fullyMatches("3.13", pattern: #"3\.\d+"#))
    }
}
