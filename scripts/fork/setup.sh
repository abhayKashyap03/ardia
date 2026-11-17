#!/bin/bash
set -euo pipefail

usage="usage: bash setup.sh [--remigrate]
One-time setup of Ardia Fork as your daily browser: builds your fork into /Applications/Ardia Fork.app signed with your
Xcode team, copies your profile from the installed Ardia (tabs, history, passwords, cookies, extensions, settings),
and installs a daily launchd check that runs the weekly sync and update (~/.ardia-fork/update.sh).
--remigrate  copy the original Ardia's data again, keeping the fork's current data as a dated backup
Set ARDIA_TEAM_ID to pick a team when Xcode is signed in to more than one."

remigrate=0
for arg in "$@"; do
  case "$arg" in
    --remigrate) remigrate=1 ;;
    -h|--help) echo "$usage"; exit 0 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done

root="$HOME/.ardia-fork"
src="$root/src"
app="/Applications/Ardia Fork.app"
fork_id="com.abhaykashyap.ardia"
agent_label="com.abhaykashyap.ardia-fork.update"
agent="$HOME/Library/LaunchAgents/$agent_label.plist"
support="$HOME/Library/Application Support"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

say "Checking tools"
for tool in xcodebuild pod node pnpm git; do
  command -v "$tool" >/dev/null || die "missing $tool (needs Xcode 26+, CocoaPods, Node 24, pnpm 11)"
done

say "Finding your Xcode team"
mkdir -p "$root"
team=${ARDIA_TEAM_ID:-}
if [ -z "$team" ]; then
  team=$(defaults export com.apple.dt.Xcode - 2>/dev/null | /usr/bin/python3 -c '
import plistlib, sys
prefs = plistlib.loads(sys.stdin.buffer.read())
teams = [t for ts in prefs.get("IDEProvisioningTeamByIdentifier", {}).values() for t in ts]
teams += [t for ts in prefs.get("IDEProvisioningTeams", {}).values() for t in ts]
teams.sort(key=lambda t: 0 if t.get("isFreeProvisioningTeam") or "Personal" in str(t.get("teamType", "")) else 1)
print(teams[0]["teamID"] if teams else "")' 2>/dev/null || true)
fi
if [ -z "$team" ]; then
  team=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)
fi
if [ -n "$team" ]; then
  echo "$team" >"$root/team"
  echo "team $team"
else
  rm -f "$root/team"
  echo "No Xcode team found (Xcode › Settings › Accounts). Building without one: Touch ID passkeys stay off until you add it and run this again."
fi

say "Getting your fork"
if [ ! -d "$src/.git" ]; then
  git clone --filter=blob:none https://github.com/abhayKashyap03/ardia "$src"
fi
git -C "$src" remote get-url upstream >/dev/null 2>&1 || git -C "$src" remote add upstream https://github.com/mantrakp04/ardia
git -C "$src" config remote.upstream.promisor true
git -C "$src" config remote.upstream.partialclonefilter blob:none
git -C "$src" fetch -q origin main
git -C "$src" show origin/main:scripts/fork/update.sh >"$root/update.sh"
chmod +x "$root/update.sh"

say "Building Ardia Fork (the first build takes a while)"
"$root/update.sh" --force || true
[ -d "$app" ] || die "the build didn't produce $app; see the newest log in $root/logs"

say "Copying your Ardia data"
original_id=com.ardia.browser
if [ ! -d "$support/$original_id" ] && [ -d "$support/com.netnyahoo.browser" ]; then original_id=com.netnyahoo.browser; fi
if [ -f "$root/migrated" ] && [ "$remigrate" = 0 ]; then
  echo "already copied on $(cat "$root/migrated"); use --remigrate to copy again"
elif [ ! -d "$support/$original_id" ]; then
  echo "no data from the original Ardia at $support/$original_id; the fork starts fresh"
else
  osascript -e "tell application id \"$original_id\" to quit" >/dev/null 2>&1 || true
  osascript -e "tell application id \"$fork_id\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    pgrep -f "/Contents/MacOS/Ardia( |$)" >/dev/null || break
    sleep 1
  done
  pgrep -f "/Contents/MacOS/Ardia( |$)" >/dev/null && die "Ardia is still running; quit it (⌘Q) and run this again"
  if [ -d "$support/$fork_id" ]; then
    mv "$support/$fork_id" "$support/$fork_id.before-$(date +%Y%m%d-%H%M%S)"
  fi
  ditto "$support/$original_id" "$support/$fork_id"
  if defaults export "$original_id" "$root/original-defaults.plist" 2>/dev/null; then
    defaults import "$fork_id" "$root/original-defaults.plist"
    for key in SUEnableAutomaticChecks SUAutomaticallyUpdate SUFeedURL SULastCheckTime SUHasLaunchedBefore ACUpdateFeedURL; do
      defaults delete "$fork_id" "$key" >/dev/null 2>&1 || true
    done
    rm -f "$root/original-defaults.plist"
  fi
  date "+%Y-%m-%d %H:%M" >"$root/migrated"
  echo "copied $(du -sh "$support/$fork_id" | cut -f1) from $support/$original_id"
fi

say "Installing the daily update check"
mkdir -p "$HOME/Library/LaunchAgents"
cat >"$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$agent_label</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$root/update.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>StandardOutPath</key><string>$root/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$root/logs/launchd.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)/$agent_label" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$agent"
echo "runs daily at 3:30 and at login; syncs and rebuilds weekly, installs a waiting build whenever the app is closed"

say "Opening Ardia Fork"
open "$app"
sleep 3
open "x-apple.systempreferences:com.apple.Desktop-Settings.extension" || true

cat <<DONE

Done. Two things only you can do:
  1. When macOS asks whether Ardia Fork may use "Ardia Safe Storage" in your keychain, enter your Mac password
     and click Always Allow. That item unlocks your saved passwords and cookies.
  2. In the System Settings window that just opened: Default web browser › Ardia Fork.

The original Ardia and its data ($support/$original_id) are untouched. Delete them once you're happy.
Logs: $root/logs   Update now: ~/.ardia-fork/update.sh --force
DONE
