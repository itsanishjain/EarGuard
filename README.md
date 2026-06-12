# EarGuard

EarGuard is a macOS menu-bar app that tracks listening time only while audio is actively rendering to a headphone-class output device. It also records average system volume percentage and warns after sustained loud listening.

## Build

```sh
swift build -c release
```

## Run During Development

```sh
swift run EarGuard
```

## Build an App Bundle

```sh
make app
open build/EarGuard.app
```

## Install

```sh
make install
open /Applications/EarGuard.app
```

History is stored at:

```text
~/Library/Application Support/EarGuard/history.json
```

EarGuard uses public CoreAudio APIs. It cannot detect whether third-party earbuds are physically in-ear, and it reports volume as system volume percent, not measured dB SPL.
