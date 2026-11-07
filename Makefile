# iPhone settings come from config.local.env (copy config.example.env); the simulator build needs none.
-include config.local.env
export EARSHOT_TEAM_ID EARSHOT_BUNDLE_PREFIX EARSHOT_DEVICE
EARSHOT_BUNDLE_PREFIX ?= dev.earshot.local

# iPhone: build for the simulator (compile check) / build, sign and install on the phone (scripts/install-phone.sh).
.PHONY: ios-build ios-install ios-resign-job
ios-build:
	xcodegen generate -q && xcodebuild -project Earshot.xcodeproj -scheme Earshot \
	  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/sim CODE_SIGNING_ALLOWED=NO build -quiet

ios-install:
	scripts/install-phone.sh --force

ios-resign-job:
	scripts/install-resign-job.sh


.PHONY: mac-test mac-sync mac-install mac-config
mac-test:
	python3 -m unittest mac/test_earshot.py -v

mac-sync:
	python3 mac/earshot.py sync

mac-install:
	bash mac/install-launchd.sh

mac-config:
	python3 mac/earshot.py config
