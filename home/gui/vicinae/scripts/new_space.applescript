#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title New Space
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🚀

log "Creating"

my openSpace()
on openSpace()
	-- Opens Mission Control
	tell application "Mission Control" to launch
	delay 0.25
	tell application "System Events"
		-- Creates a New Desktop Space
		tell group 2 of group 1 of group 1 of process "Dock"
			click (every button whose value of attribute "AXDescription" is "add desktop")
		end tell
		delay 0.15
		-- Switches to the New Desktop Space
		key code 124 using {control down} # -> + ctrl
		delay 0.75
		-- Exit out of Mission Control
		key code 53 # Esc key on US English Keyboard
	end tell
end openSpace
