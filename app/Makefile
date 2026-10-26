.PHONY: build app run icon shots clean

build:
	swift build -c release

app:
	./Scripts/build-app.sh release

run: app
	pkill -x TiboDog || true
	open build/TiboDog.app

install: app
	rm -rf /Applications/TiboDog.app
	cp -R build/TiboDog.app /Applications/
	open /Applications/TiboDog.app

icon:
	swift Scripts/make-icon.swift

shots: build
	TIBODOG_MOCK=1 TIBODOG_SNAPSHOT=$(CURDIR)/docs/collapsed.png .build/release/TiboDog
	TIBODOG_MOCK=1 TIBODOG_EXPANDED=1 TIBODOG_SNAPSHOT=$(CURDIR)/docs/expanded.png .build/release/TiboDog

clean:
	rm -rf .build build
