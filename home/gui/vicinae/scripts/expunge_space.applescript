#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Expunge Space
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💥

log "Expunging"

my closeSpace()
on closeSpace()
	-- Open Mission Control
	tell application "Mission Control" to launch
	delay 0.25
	-- Remove the last desktop space
	tell application "System Events"
		tell list 1 of group 2 of group 1 of group 1 of process "Dock"
			set buttonNames to the name of UI elements
			set buttonNames to the reverse of buttonNames
			set i to the length of buttonNames
			repeat with buttonName in buttonNames
				if contents of buttonName is equal to ("Desktop " & i as text) then
					if i is greater than 1 then
						perform action "AXRemoveDesktop" of button i
						exit repeat
					end if
				else
					set i to i - 1
				end if
			end repeat
		end tell
		delay 0.75
		-- Exit Mission Control
		key code 53 # Esc key on US English Keyboard
	end tell
end closeSpace
