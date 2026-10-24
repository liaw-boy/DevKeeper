cask "devkeeper" do
  version "1.3.0"
  sha256 "6708e1928e710f9d5b6f5e1dec10d677062d0dd3a5f0b18411089f2bf7773133"

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
