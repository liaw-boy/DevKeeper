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
