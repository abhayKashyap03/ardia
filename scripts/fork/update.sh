#!/bin/bash
set -uo pipefail

usage="usage: update.sh [--force] [--install-only]
Keeps /Applications/Ardia Fork.app current. Once a week it merges mantrakp04/ardia into your fork's main and pushes it,
rebuilds the daily branch on the newest upstream commit whose engine has a download, replays your fork's own commits on
top, builds it signed with your Xcode team, and installs it while the app is closed. Every run installs a waiting build.
Merges and cherry-picks commit with your global git name and email.
--force         sync and rebuild now
--install-only  only install a build that is waiting for the app to close"

root="$HOME/.ardia-fork"
src="$root/src"
app="/Applications/Ardia Fork.app"
pending="$root/pending/Ardia Fork.app"
derived="$root/derived"
force=0 install_only=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    --install-only) install_only=1 ;;
    -h|--help) echo "$usage"; exit 0 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done

mkdir -p "$root/logs" "$root/pending"
log="$root/logs/update-$(date +%Y%m%d-%H%M%S).log"
if [ -t 1 ]; then exec > >(tee -a "$log") 2>&1; else exec >>"$log" 2>&1; fi
ls -1t "$root"/logs/update-*.log 2>/dev/null | tail -n +21 | while read -r old; do rm -f "$old"; done

login_path=$(/bin/zsh -ic 'print -r -- "__PATH__$PATH"' 2>/dev/null | grep '^__PATH__' | tail -1 | sed 's/^__PATH__//')
export PATH="${login_path:+$login_path:}$HOME/.homebrew/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export GIT_TERMINAL_PROMPT=0 LANG=en_US.UTF-8

notify() {
  echo "notice: $1"
  osascript -e "display notification \"${1//\"/\\\"}\" with title \"Ardia Fork\"" >/dev/null 2>&1 || true
}
running() { pgrep -f "Ardia Fork.app/Contents/MacOS/" >/dev/null; }
version_of() { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?"; }

install_pending() {
  [ -d "$pending" ] || return 0
  if running; then
    notify "Version $(version_of "$pending") is ready. Quit Ardia Fork and it installs on the next check (or run ~/.ardia-fork/update.sh --install-only)."
    return 0
  fi
  rm -rf "$app.old"
  [ -d "$app" ] && mv "$app" "$app.old"
  if mv "$pending" "$app" 2>/dev/null || { ditto "$pending" "$app" && rm -rf "$pending"; }; then
    rm -rf "$app.old"
    notify "Installed Ardia Fork $(version_of "$app")."
  else
    rm -rf "$app"
    [ -d "$app.old" ] && mv "$app.old" "$app"
    notify "Couldn't install the new build into /Applications. Log: $log"
  fi
}

signature_expires_soon() {
  local profile="$app/Contents/embedded.provisionprofile" expiry
  [ -f "$profile" ] || return 1
  expiry=$(security cms -D -i "$profile" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null) || return 0
  expiry=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" +%s 2>/dev/null) || return 0
  [ $((expiry - $(date +%s))) -lt $((3 * 86400)) ]
}

install_pending
[ "$install_only" = 1 ] && exit 0

last_sync=$(cat "$root/last-sync" 2>/dev/null || echo 0)
if [ "$force" = 0 ] && [ $(($(date +%s) - last_sync)) -lt $((6 * 86400)) ] && ! signature_expires_soon; then
  echo "nothing due (last sync $(date -r "$last_sync" 2>/dev/null))"
  exit 0
fi

cd "$src" || { notify "The build checkout at $src is missing; run setup.sh again."; exit 1; }
git rebase --abort >/dev/null 2>&1; git cherry-pick --abort >/dev/null 2>&1; git merge --abort >/dev/null 2>&1
git fetch -q origin && git fetch -q upstream main || { notify "Couldn't reach GitHub; will try again tomorrow."; exit 1; }

git checkout -q -f -B main origin/main
if git merge -q --no-edit upstream/main; then
  if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    git push -q origin main || notify "Merged upstream into main but couldn't push it to your fork (check git's GitHub sign-in)."
  fi
else
  git merge --abort
  git checkout -q -f -B main origin/main
  notify "Upstream changes conflict with your fork's main. Building from your last synced main; merge upstream by hand when you can."
fi

table=$(git show upstream/main:packages/ardiacore/prebuilt-engines.tsv | awk '{ print $1 }')
base=""
for commit in $(git rev-list --first-parent upstream/main | head -800); do
  key=$(engine/engine-key.sh "$commit" 2>/dev/null) || continue
  if grep -qx "$key" <<<"$table"; then base=$commit; break; fi
done
[ -n "$base" ] || { notify "No upstream commit with a downloadable engine; kept the current app."; exit 1; }

mine=$(git rev-list --reverse --no-merges upstream/main..main)
want=$(echo "$base $mine $(cat "$root/team" 2>/dev/null)" | shasum -a 256 | cut -c1-16)
if [ "$force" = 0 ] && [ "$(cat "$root/built" 2>/dev/null)" = "$want" ] && [ -d "$app" ] && ! signature_expires_soon; then
  date +%s >"$root/last-sync"
  echo "already built $(git log -1 --format='%h %s' "$base")"
  exit 0
fi

git checkout -q -f -B daily "$base"
for commit in $mine; do
  if ! git cherry-pick "$commit" >/dev/null; then
    git cherry-pick --abort
    notify "Your change \"$(git log -1 --format=%s "$commit")\" doesn't apply on the newest buildable Ardia; kept the current app."
    exit 1
  fi
done
git push -q -f origin daily || true

pnpm install --frozen-lockfile || { notify "pnpm install failed; kept the current app. Log: $log"; exit 1; }
(cd apps/browser/macos && pod install) || { notify "pod install failed; kept the current app. Log: $log"; exit 1; }

build() {
  xcodebuild -workspace apps/browser/macos/Ardia.xcworkspace -scheme Ardia-macOS -configuration Release \
    -derivedDataPath "$derived" -destination 'platform=macOS,arch=arm64' -quiet "$@" build
}
team=$(cat "$root/team" 2>/dev/null || true)
signed=1
if [ -z "$team" ] || ! build -allowProvisioningUpdates ARDIA_TEAM_ID="$team"; then
  signed=0
  build -xcconfig apps/browser/macos/AdHoc.xcconfig || { notify "The build failed; kept the current app. Log: $log"; exit 1; }
fi

rm -rf "$pending"
ditto "$derived/Build/Products/Release/Ardia.app" "$pending" || { notify "Couldn't copy the build; kept the current app."; exit 1; }
echo "$want" >"$root/built"
date +%s >"$root/last-sync"
cp scripts/fork/update.sh "$root/update.sh.new" && mv "$root/update.sh.new" "$root/update.sh" && chmod +x "$root/update.sh"
[ "$signed" = 0 ] && notify "Built without your Xcode team (signing failed), so Touch ID passkeys are off in this build. Log: $log"
install_pending
echo "built $(git log -1 --format='%h %s' "$base") with $(echo "$mine" | grep -c .) fork commits"
