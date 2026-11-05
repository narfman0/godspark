#!/usr/bin/env bash
# Fetch the interface's display fonts into assets/fonts/ (git-ignored: fonts are art and are
# never committed). The game runs without them: UiTheme falls back to the engine's font.
#
# Fonts (both SIL Open Font License 1.1, from Google Fonts' GitHub repository; the licence
# text is fetched next to each font as <name>.OFL.txt):
#   IM Fell English SC  (Igino Marini)   titles and banners: old print, hand-inked
#   Patrick Hand        (Patrick Wagesreiter)  body and HUD text: a clean, readable hand
#
#   tools/fetch_fonts.sh          # skips files already present
set -euo pipefail
cd "$(dirname "$0")/.."
dir=assets/fonts
mkdir -p "$dir"
touch "$dir/.gdignore"     # loaded at runtime (FontFile.load_dynamic_font), never imported
base=https://raw.githubusercontent.com/google/fonts/main/ofl
fetch() {   # url out
	if [[ -s "$2" ]]; then echo "have $2"; return 0; fi
	if curl -fsSL --retry 2 -o "$2.part" "$1"; then mv "$2.part" "$2"; echo "got  $2"; else rm -f "$2.part"; echo "FAILED $1"; return 1; fi
}
status=0
fetch "$base/imfellenglishsc/IMFeENsc28P.ttf" "$dir/IMFellEnglishSC.ttf" || status=1
fetch "$base/imfellenglishsc/OFL.txt" "$dir/IMFellEnglishSC.OFL.txt" || status=1
fetch "$base/patrickhand/PatrickHand-Regular.ttf" "$dir/PatrickHand.ttf" || status=1
fetch "$base/patrickhand/OFL.txt" "$dir/PatrickHand.OFL.txt" || status=1
exit $status
