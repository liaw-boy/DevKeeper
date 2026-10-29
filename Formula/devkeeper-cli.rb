class DevkeeperCli < Formula
  desc "Command-line package and vulnerability audit tool with a local web interface"
  homepage "https://github.com/liaw-boy/DevKeeper"
  url "https://github.com/liaw-boy/DevKeeper/releases/download/v1.4.0/devkeeper-cli-linux-x86_64.tar.gz"
  sha256 "8281a646ac6c3a544f81d1a19d8221e4330e148bfd0797895e819feb2a3c152a"

  # Only a prebuilt Linux x86_64 binary is published for now.
  depends_on arch: :x86_64
  depends_on :linux

  def install
    bin.install "devkeeper-cli"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/devkeeper-cli version")
  end
end
