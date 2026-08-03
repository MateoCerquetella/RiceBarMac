# Application Experience Delta

## ADDED Requirements

### Requirement: Built-in presentation is emoji-free

Tracked application source, built-in menu-bar defaults, settings choices, menu
labels, alerts, and About copy MUST contain no emoji characters. Clear ASCII text
or platform-native non-emoji presentation MUST replace the removed glyphs. The
application MUST continue to decode existing user-provided icon strings without
rewriting them merely because they contain emoji.

#### Scenario: Fresh configuration is created

- **WHEN** RiceBarMac creates configuration with no prior menu-bar icon setting
- **THEN** it chooses the documented ASCII default and displays a usable status
  item without an emoji glyph

#### Scenario: Existing configuration contains a custom emoji

- **WHEN** a compatible existing configuration supplies its own icon string
- **THEN** decoding remains successful and the value is preserved as user data

#### Scenario: Repository presentation is scanned

- **WHEN** every tracked text file is checked with the release emoji scanner
- **THEN** no emoji code point is found in application strings, tests, or docs
