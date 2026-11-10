#!/usr/bin/env bash
# Clean replacement of IBA KeyMorph on macOS: quits the running app, moves every older copy to the Trash,
# installs the new "IBA KeyMorph.app" into /Applications and makes macOS show its new icon.
#
#   ./update-keymorph.sh ~/Downloads/IBA-KeyMorph-1.0.5-macOS.zip     # or the unpacked "IBA KeyMorph.app"
#   ./update-keymorph.sh --dry-run ~/Downloads/IBA-KeyMorph-1.0.5-macOS.zip    # only says what it would do
#   ./update-keymorph.sh --refresh-dock ...                                      # also restarts the Dock and Finder
#
# Why it exists: the store gives a plain .zip with the app, so nothing removes the previous copy. Finder's
# "Replace" works only when the old app has the same name and is closed; a copy that stayed in Downloads, on the
# Desktop or under another name ("IBA KeyMorph 2.app") is still known to Launch Services and keeps old icons.
#
# Safe by design: an old copy is moved to the Trash (not deleted) and only when its Info.plist says it is
# IBA KeyMorph (bundle id com.iba.keymorph). The bundle id and the name "IBA KeyMorph.app" have never changed
# (git history of macos/build-app.sh and macos/Resources/Info.plist), so the search is by bundle id first and by
# name patterns second. Settings (UserDefaults com.iba.keymorph) and the log are kept.
set -euo pipefail

BUNDLE_ID="com.iba.keymorph"
APP_NAME="IBA KeyMorph.app"
DEST_DIR="${KEYMORPH_APPLICATIONS_DIR:-/Applications}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

DRY=0
DOCK=0
SOURCE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --refresh-dock) DOCK=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) SOURCE="$arg" ;;
  esac
done
[ -n "$SOURCE" ] || { echo "Укажите .zip из магазина или распакованный \"$APP_NAME\" (см. --help)." >&2; exit 2; }
[ -e "$SOURCE" ] || { echo "Нет такого файла: $SOURCE" >&2; exit 2; }

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

plist_id() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }
plist_version() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || true; }

# 1. The new app: unpack the zip into a temporary folder and check what is inside.
WORK="$(mktemp -d /tmp/keymorph-update.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
case "$SOURCE" in
  *.zip) ditto -x -k "$SOURCE" "$WORK"; NEW="$WORK/$APP_NAME" ;;
  *.app) NEW="$SOURCE" ;;
  *) echo "Нужен .zip или .app" >&2; exit 2 ;;
esac
[ -d "$NEW" ] || { echo "В архиве нет \"$APP_NAME\"." >&2; exit 1; }
[ "$(plist_id "$NEW")" = "$BUNDLE_ID" ] || { echo "Это не IBA KeyMorph (bundle id $(plist_id "$NEW"))." >&2; exit 1; }
say "Новая версия: $(plist_version "$NEW")"

# 2. Quit the running copy (a menu-bar app has no window, so ask it politely first, then by process name).
if pgrep -x IBAKeyMorph >/dev/null 2>&1; then
  say "Закрываю работающий IBA KeyMorph…"
  run osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  if [ "$DRY" = 0 ]; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x IBAKeyMorph >/dev/null 2>&1 || break; sleep 0.5; done
    pkill -x IBAKeyMorph 2>/dev/null || true
  fi
fi

# 3. Find every older copy: by bundle id (Spotlight / Launch Services) and by name in the usual places.
CANDIDATES="$WORK/candidates.txt"
: > "$CANDIDATES"
mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null >> "$CANDIDATES" || true
"$LSREGISTER" -dump 2>/dev/null | sed -n 's/^path: *\(.*\.app\) (0x[0-9a-f]*)$/\1/p' | grep -i "keymorph" >> "$CANDIDATES" || true
for dir in "$DEST_DIR" "$HOME/Applications" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" /Applications/Utilities; do
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 2 -type d \( -iname "*keymorph*.app" -o -iname "IBA KeyMorph*.app" \) 2>/dev/null >> "$CANDIDATES" || true
done

NEW_REAL="$(cd "$NEW" && pwd -P)"
TRASH="$HOME/.Trash"
REMOVED=0
while IFS= read -r old; do
  [ -n "$old" ] && [ -d "$old" ] || continue
  real="$(cd "$old" && pwd -P)"
  [ "$real" = "$NEW_REAL" ] && continue
  case "$real" in /System/*|/Library/*|/private/tmp/keymorph-update.*|/tmp/keymorph-update.*) continue ;; esac
  [ "$(plist_id "$real")" = "$BUNDLE_ID" ] || continue
  say "Старая копия ($(plist_version "$real")): $real → Корзина"
  if [ "$DRY" = 0 ]; then
    target="$TRASH/$(basename "$real" .app) $(date +%Y%m%d-%H%M%S)-$REMOVED.app"
    mv "$real" "$target" 2>/dev/null || { echo "  не удалось переместить (нужны права): $real" >&2; continue; }
    "$LSREGISTER" -u "$real" >/dev/null 2>&1 || true
  fi
  REMOVED=$((REMOVED + 1))
done < <(sort -u "$CANDIDATES")
say "Старых копий убрано: $REMOVED"

# 4. Install the new one (ditto keeps the signature, the notarization ticket and permissions).
TARGET="$DEST_DIR/$APP_NAME"
if [ -e "$TARGET" ] && [ "$(cd "$TARGET" && pwd -P)" != "$NEW_REAL" ]; then
  # Same name as the new app but not found above (for example the bundle id could not be read): keep it in the Trash too.
  say "Занято $TARGET — переношу в Корзину"
  run mv "$TARGET" "$TRASH/IBA KeyMorph $(date +%Y%m%d-%H%M%S)-old.app"
fi
say "Устанавливаю $TARGET"
run ditto "$NEW" "$TARGET"

# 5. Make macOS notice the new bundle and its icon.
run xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
run touch "$TARGET"
run "$LSREGISTER" -f -R "$TARGET"
if [ "$DOCK" = 1 ]; then
  say "Перезапускаю Dock и Finder (значки перерисуются)…"
  run killall Dock 2>/dev/null || true
  run killall Finder 2>/dev/null || true
fi

# 6. Start the new version.
run open "$TARGET"
say "Готово. Если значок остался старым: ./update-keymorph.sh --refresh-dock …, затем «Выйти из системы» и вход снова."
say "Доступ в «Универсальном доступе» после обновления нужно подтвердить: окно IBA KeyMorph → «Выдать доступ…»."
