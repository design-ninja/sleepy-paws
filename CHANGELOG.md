# Changelog

All notable changes to Sleepy Paws are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-11-07

### Added

- Automatic updates with Sparkle: a daily check and Check for Updates… in the
  menu. Updates are signed with an EdDSA key and served from GitHub Releases.
- About shows the build number too, e.g. 0.1.1 (2).

## [0.1.0] - 2026-11-07

First public build.

### Added

- Menu bar countdown that only counts while the Mac is in use and resets at
  midnight; durations show as 29:59, or 4:29:59 from an hour up.
- Break screen on every display and Space, with a yawn, a fade in and out, and
  the Dock, menu bar, app switcher and Force Quit disabled.
- Parent PIN checked as soon as it is typed: green cells when it's right; a
  shake and the number of tries left when it's wrong; a 30-second wait after
  five wrong tries.
- Add time from the break screen in steps from 5 minutes to 8 hours, with the
  last choice remembered, or pause the timer until midnight. The menu bar can
  pause and resume too.
- *Forgot PIN?*: a macOS administrator's name and password count as the PIN.
- Media control at break time: pauses the Now Playing app and running Music,
  Spotify, TV, QuickTime and VLC, then keeps the Mac muted until the break
  ends.
- Tamper resistance: a KeepAlive launch agent that repairs itself, progress
  saved every few seconds and at shutdown, and two copies of the state where
  the stricter one wins.
- First-launch onboarding that creates the parent PIN.
- Settings in the style of System Settings: daily limit in hours and minutes
  (saving restarts today's countdown) and a Change PIN… sheet.
- About window with a link to the repository.
- Signed with Developer ID and notarized by Apple.

[Unreleased]: https://github.com/design-ninja/sleepy-paws/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/design-ninja/sleepy-paws/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/design-ninja/sleepy-paws/releases/tag/v0.1.0
