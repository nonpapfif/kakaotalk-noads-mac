#!/bin/sh
set -eu
source_app=$1
target=$2
expected_executable=$3
expected_helper=$4
expected_version=${5:?Expected payload version}
expected_build=${6:?Expected payload build}
parent=$(/usr/bin/dirname "$target")
[ "$(/usr/bin/basename "$target")" = 'KakaoTalk.app' ] || exit 2
[ -d "$parent" ] && [ ! -L "$target" ] || exit 2
expected_id=local.elsholtzia.KakaoTalkReconnectExperiment
plist="$source_app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "$expected_id" ] || exit 2
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$expected_version" ] || exit 2
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$expected_build" ] || exit 2
verify_app() {
    /usr/bin/codesign --verify --deep --strict "$1" || return 1
    actual=$(/usr/bin/shasum -a 256 "$1/Contents/MacOS/KakaoTalk") || return 1
    [ "${actual%% *}" = "$expected_executable" ] || return 1
    actual=$(/usr/bin/shasum -a 256 "$1/Contents/Frameworks/SessionReconnect.dylib") || return 1
    [ "${actual%% *}" = "$expected_helper" ] || return 1
}
verify_app "$source_app"
if [ -e "$target" ]; then
    old_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")
    case "$old_id" in
        com.kakao.KakaoTalkMac|local.elsholtzia.KakaoTalkNoAds|local.elsholtzia.KakaoTalkReconnectExperiment) ;;
        *) echo 'Refusing to replace an unexpected application.' >&2; exit 2 ;;
    esac
    if verify_app "$target" >/dev/null 2>&1; then
        echo 'BACKUP=none; matching application already installed'
        exit 0
    fi
fi
identifier=$(/usr/bin/uuidgen)
staging="$parent/.KakaoTalk-install-$identifier.app"
backup_dir="$parent/KakaoTalk Backups"
backup="$backup_dir/KakaoTalk-$(/bin/date +%Y%m%d-%H%M%S)-$identifier.app"
old_moved=0
new_moved=0
committed=0
cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$committed" -eq 0 ] && [ "$old_moved" -eq 1 ]; then
        if [ "$new_moved" -eq 1 ] && [ -e "$target" ]; then
            /bin/mv "$target" "$staging" || exit 1
        fi
        /bin/mv "$backup" "$target" || exit 1
        echo 'Previous application restored.' >&2
    elif [ "$committed" -eq 0 ] && [ "$new_moved" -eq 1 ]; then
        /bin/mv "$target" "$staging" || exit 1
    fi
    if [ -d "$staging" ]; then /bin/rm -rf "$staging"; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
/bin/mkdir "$staging" || exit 77
/usr/bin/ditto --norsrc "$source_app" "$staging"
verify_app "$staging"
if [ -e "$target" ]; then
    /bin/mkdir -p "$backup_dir" || exit 77
    /bin/mv "$target" "$backup" || exit 77
    old_moved=1
fi
/bin/mv "$staging" "$target"
new_moved=1
verify_app "$target"
committed=1
if [ "$old_moved" -eq 1 ]; then echo "BACKUP=$backup"; else echo 'BACKUP=none'; fi
