# Native typing test attribution

This module is an original native QML implementation for end4-pC. Its test
configuration, input behavior, caret options, theme color model, and local
result concepts were informed by the GPL-3.0-licensed Monkeytype project:

- Project: https://github.com/monkeytypegame/monkeytype
- Copyright: Monkeytype contributors
- License: GNU General Public License v3.0

Two word lists under `defaults/typingTest/languages/` are Monkeytype data files
copied verbatim from `frontend/static/languages/`, and carry that project's
license:

- `english_10k.json`
- `english_commonly_misspelled.json` (which Monkeytype in turn sourced from
  https://en.wikipedia.org/wiki/Wikipedia:Lists_of_common_misspellings)

`quotes_english.json` is an original curated pack, not Monkeytype's quote
collection. The theme palettes in `TypingThemeCatalog.qml` reproduce the color
values of Monkeytype's built-in themes.

No Monkeytype web application, account service, Firebase code, multiplayer
service, leaderboard, or moderation backend is embedded in this module.
