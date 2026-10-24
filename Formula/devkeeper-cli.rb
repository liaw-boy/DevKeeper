class DevkeeperCli < Formula
  desc "Command-line package and vulnerability audit tool with a local web interface"
  homepage "https://github.com/liaw-boy/DevKeeper"
  url "https://github.com/liaw-boy/DevKeeper/releases/download/v1.3.0/devkeeper-cli-linux-x86_64.tar.gz"
  sha256 "a00c9971f51d338e42d4b8a378b93c16fb53570daf434633090cda84836a040c"

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
