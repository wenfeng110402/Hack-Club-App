# HackClubApp

HackClubApp is an iOS SwiftUI app focused on Hack Club identity, verification signals, and YSWS discovery.

## Features

- Hack Club Auth OAuth login flow using `ASWebAuthenticationSession`.
- Access token exchange and persisted login session state.
- Home dashboard with:
	- user display name and verification status summary
	- verification signal count and status messaging
	- profile cards for YSWS eligibility, Slack ID, identity ID, scopes, and more
- Long-press copy support for card values (for example Slack ID and identity ID).
- Lightweight "Copied!" toast feedback after copy actions.
- Haptic feedback for key interactions (tab switches, success/warning/error states, button taps).
- YSWS feed experience:
	- fetches project data from the YSWS RSS/XML feed
	- parses title, summary, deadline, and Slack channel
	- filters out expired projects and sorts active ones
	- pull-to-refresh support
	- opens project links directly from cards
- Dedicated Hackatime page entry from the Home tab (currently a placeholder login screen).
- Settings page with account info, app info page, and logout confirmation.
- Consistent dark glass-style UI design across tabs.

## Current Notes

- Hackatime OAuth/stats are not implemented yet.
- Some profile fields are placeholders and marked as unavailable or coming soon.
