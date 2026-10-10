# AC-Proximity-Mirror

A Lua app for Assetto Corsa that shows a virtual rear-view mirror only when opponent cars are within a configurable distance.

This was built as a simple personal feature request: I wanted a mirror that appears only when nearby cars are close enough to matter, instead of staying visible all the time.

This project takes no credit for the original idea or underlying implementation; it was developed with AI assistance. The goal here is to provide a working, configurable mirror app and to acknowledge the people whose work made it possible.

## Features

- Shows the game's virtual rear-view mirror only when nearby opponents are within range
- Smooth fade-in and fade-out behavior
- Distance-based activation with configurable trigger thresholds
- Optional rear-only detection (ignoring cars in front of you)
- Hover and visibility controls
- Adjustable mirror appearance, framing, opacity, and color scheme
- Built-in settings window for tuning behavior
- Includes a tonemapping workaround for the washed-out rendering issue seen with Pure

## Why this exists

The motivation for this app was simple: I wanted a rear-view mirror that would only appear when cars were close enough to matter, without keeping the mirror visible at all times.

## Credits

- Special thanks to the creator of Pure for identifying the washed-out render bug and the tonemapping fix used here.
- This project builds on the work from the AC Virtual Mirror in-game app by @piereligio and its creator: https://github.com/piereligio/AC-Virtual-Mirror-ingame-app
- The underlying mirror rendering logic is inspired by and adapted from that reference project.

## Installation

1. Copy the repository contents into your Assetto Corsa Lua app folder used by Custom Shaders Patch (CSP).
2. Ensure the app is enabled in the CSP app list.
3. Open the mirror window from the app UI and adjust the settings to your preference.

Files included in this repo:

- `ProximityMirror.lua` — main Lua app logic
- `manifest.ini` — CSP app metadata and window configuration
- `icon.png` — app icon

## Configuration

The app exposes several settings via the settings UI, including:

- trigger distance
- fade-in / fade-out smoothing
- linger time after cars leave range
- rear-only filtering
- hover behavior
- opacity and frame options
- color scheme
- tonemapping values for Pure

## Notes

This project is intentionally lightweight and focused on the core behavior: a mirror that appears only when nearby opponents are close enough to matter.

## License

This project does not currently include a license file. If you plan to redistribute or modify it, please confirm the licensing status of the underlying referenced project and any assets before publishing modified builds.
