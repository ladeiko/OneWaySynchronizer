
.PHONY: test

test:
	pod repo update
	pod install
	xcodebuild test -quiet -scheme OneWaySynchronizerDemo -workspace ./OneWaySynchronizerDemo.xcworkspace/ -destination 'platform=iOS Simulator,name=iPhone 8' || exit 1
