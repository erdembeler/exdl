cask "exdl" do
  version "1.0.0"
  sha256 "80adaf02c96667f677c826afb8150c42b93db8856623be19323df077eeba71cd"

  url "https://github.com/erdembeler/exdl/releases/download/v#{version}/EXdl-#{version}.dmg"
  name "EXdl"
  desc "External disk app installer and smart launcher for macOS"
  homepage "https://github.com/erdembeler/exdl"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "EXdl.app"

  zap trash: [
    "~/Library/Preferences/com.erdem.EXdl.plist",
    "~/Library/Saved Application State/com.erdem.EXdl.savedState",
  ]
end
