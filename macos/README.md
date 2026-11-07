# Earshot for Mac

A menu bar app that replaces Audio Hijack for recording calls and meetings on the Mac, built on
[Cicada](https://github.com/wquguru/cicada) (Apache-2.0; the commit we started from is in `UPSTREAM`,
its license in `LICENSE-cicada`). We don't follow upstream: its update checks are switched off.

What Earshot adds to Cicada:

| | Where |
|---|---|
| Hear only chosen apps (腾讯会议, 微信, 微信 2, 飞书, 抖音, QuickTime by default), helpers included | `AppCapture.swift`, `SystemAudioTap.swift`; Settings › General › 录哪些 App (`captureApps`) |
| After stopping by itself, start again on the next call or when a chosen non-call app plays | `AppModel.watchEnd` (`rearmed`) |
| 微信 counts as a call when it reads the mic and plays at once (a voice message only reads it) | `MicUsers.currentCalls`, `AppCapture.inCall` |
| Microphone on for the length of a call, recorded to `room.m4a` on the meeting's timeline | `AppModel.followCallMic`, `SessionStore.roomAudioURL` |
| 腾讯会议 mute followed by watching clicks on its mic button (ported from the TencentAudioHijackSync helper); while muted the mic track is digital silence | `TencentMute.swift`, `AudioRouter.setSilenced` |
| Chinese UI on every Mac: only `zh-Hans.lproj` ships | `scripts/build.sh` |
| Open at login on by default (release build, once) | `AppModel.launch` |
| Finished recordings exported to `icloud_dir` (from `~/.config/earshot/config.json`) as scene `mac`, for `mac/earshot.py` | `EarshotExport.swift`, `docs/CONTRACT.md` |

Everything else (live subtitles, notes, records window, on-device recognition) is Cicada's.

## Build and check

```sh
scripts/build.sh                 # dev build: build/Earshot.app, bundle id dev.earshot.mac.dev, own settings
RELEASE=1 scripts/build.sh       # bundle id dev.earshot.mac
scripts/test.sh                  # unit tests
swiftc -O tools/lsctl.swift -o build/lsctl   # remote control of a dev build; commands in tools/README.md
```

Debug commands added: `tencentMute:<on|off>` (as if the mic icon was clicked), `tencentTap` (open the click watch now). Dev build log: `/tmp/earshot-mac-dev-debug.log`. Per-app capture can be tried without a meeting app:
`defaults write dev.earshot.mac.dev captureApps -array /usr/bin/afplay`, relaunch, `afplay Resources/sample/sample.m4a`.
`EARSHOT_ICLOUD_DIR=<folder>` (via `open --env`) sends exports somewhere other than the configured folder.

## Known limits

- After stopping by itself, the first 1–2 seconds of the next call or playback can be missed (checked every 2 s).
- 腾讯会议 mute is followed through clicks on its mic icon only: its keyboard shortcut or the host muting you is not seen. Other apps' mute isn't followed.
