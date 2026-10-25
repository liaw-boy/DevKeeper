import XCTest
@testable import DevKeeperCore

final class UpgradeCommandTests: XCTestCase {
    func testBrewUpgradesOnlyListedPackages() {
        XCTAssertEqual(BrewService.upgradeCommands(formulae: ["jq", "openssl@3"], casks: ["iterm2"]),
                       ["brew upgrade --formula jq openssl@3", "brew upgrade --cask iterm2"])
        XCTAssertEqual(BrewService.upgradeCommands(formulae: [], casks: []), [])
        XCTAssertNil(BrewService.upgradeCommands(formulae: ["jq; rm -rf ~"], casks: []))
    }
    
    func testNpmUpgradeAllCommand() {
        XCTAssertEqual(NpmService.upgradeAllCommand(packages: ["typescript", "@scope/cli"]),
                       "npm install -g typescript@latest @scope/cli@latest")
        XCTAssertNil(NpmService.upgradeAllCommand(packages: []))
        XCTAssertNil(NpmService.upgradeAllCommand(packages: ["x$(id)"]))
    }
}
