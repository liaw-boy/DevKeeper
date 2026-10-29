cask "devkeeper" do
  version "1.4.0"
  sha256 "82159c25f1c14ef94e4ea3d17a46251064ec339a34e01249b9770155a888a081"

  url "https://github.com/liaw-boy/DevKeeper/releases/download/v#{version}/DevKeeper.dmg"
  name "DevKeeper"
  desc "Developer package manager and vulnerability auditor"
  homepage "https://github.com/liaw-boy/DevKeeper"

  depends_on macos: ">= :sonoma"

  app "DevKeeper.app"

  zap trash: [
    "~/Library/Preferences/com.devkeeper.macos.plist",
  ]

  caveats <<~EOS
    DevKeeper is ad-hoc signed and not notarized, so macOS blocks it the first time.
    Open it once, then go to System Settings > Privacy & Security and choose "Open Anyway".
  EOS
end
