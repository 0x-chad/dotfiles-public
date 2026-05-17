#!/bin/bash
# macOS defaults - run once on new machine setup
# Some changes require logout/restart to take effect

echo "=== Configuring macOS defaults ==="

# Close System Preferences to prevent overriding
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null

###############################################################################
# Keyboard
###############################################################################

# Fast key repeat
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable press-and-hold for keys (enables key repeat everywhere)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Full keyboard access for all controls (Tab in dialogs)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

###############################################################################
# Trackpad & Mouse
###############################################################################

# Enable tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Tracking speed (0 to 3, 3 is fastest)
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.5

###############################################################################
# Finder
###############################################################################

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Use list view in all Finder windows by default
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

###############################################################################
# Dock
###############################################################################

# Set Dock size
defaults write com.apple.dock tilesize -int 48

# Auto-hide the Dock
defaults write com.apple.dock autohide -bool true

# Remove the auto-hiding Dock delay
defaults write com.apple.dock autohide-delay -float 0

# Speed up Dock hide/show animation
defaults write com.apple.dock autohide-time-modifier -float 0.3

# Don't show recent applications in Dock
defaults write com.apple.dock show-recents -bool false

###############################################################################
# Screenshot
###############################################################################

# Save screenshots to Desktop
defaults write com.apple.screencapture location -string "${HOME}/Desktop"

# Save screenshots in PNG format
defaults write com.apple.screencapture type -string "png"

# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true

###############################################################################
# Safari
###############################################################################

# Enable Develop menu and Web Inspector
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true

###############################################################################
# Terminal
###############################################################################

# Only use UTF-8 in Terminal.app
defaults write com.apple.terminal StringEncodings -array 4

###############################################################################
# Keyboard Shortcuts
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/macos-keyboard-shortcuts.plist" ]]; then
  echo "Restoring keyboard shortcuts..."
  defaults import com.apple.symbolichotkeys "$SCRIPT_DIR/macos-keyboard-shortcuts.plist"
fi

###############################################################################
# Kill affected applications
###############################################################################

echo "Restarting affected apps..."
for app in "Finder" "Dock" "SystemUIServer"; do
  killall "${app}" &> /dev/null
done

echo ""
echo "=== Done! ==="
echo "Note: Some changes require logout/restart to take effect."
