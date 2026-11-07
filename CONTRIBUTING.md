# Contributing

Small, focused pull requests are welcome.

1. `cp config.example.env config.local.env` and fill it in (only needed to install on a phone).
2. `make ios-build` — compiles the app and both extensions for the simulator, no signing needed.
3. `make mac-test` — offline tests of the Mac side; they never call devicectl, iCloud, a transcriber or codex.
4. If you change files the phone and the Mac exchange, update `docs/CONTRACT.md` in the same PR.

Keep the iPhone app free of network code, and keep test fixtures synthetic.
