# Voice Overlay: agent guide

Read README.md and this file before changing the project. Voice Overlay is a standalone Swift/AppKit macOS dictation app.

## Product direction

Develop Voice Overlay as a solid local-first competitor and open-source alternative to Wispr Flow for everyday Mac dictation. Preserve the core workflow: focus a text field, hold a shortcut, speak, and insert the transcript without switching apps.

Prioritize reliable dictation, Hindi/English recognition, predictable hotkeys, focus preservation, simple setup and local audio processing. Describe implemented features separately from planned ones. Do not claim Wispr Flow feature parity, better accuracy, lower memory usage or greater speed without a reproducible comparison of both apps on the same hardware and input. English recognition is not translation or automatic rewriting.

## Setup and verification

Requirements: macOS 14+, Swift 6.0+ and a compatible macOS SDK. No external Swift packages, API keys or cloud account are needed to build or run unit tests.

Live transcription additionally needs NVIDIA NeMo-Speech.cpp and the Nemotron 3.5 ASR model. The tested runtime version is 0.1.0. Follow README.md for installation, model download and Microphone/Accessibility permissions. Do not download weights merely to run unit tests.

Run from the repository root:

```sh
swift --version
xcode-select -p
swift build
swift run VoiceOverlayTestRunner
./scripts/package-app.sh
codesign --verify --deep --strict dist/VoiceOverlay.app
```

Use `swift run VoiceOverlayTestRunner`, not `swift test`: the project uses an executable assertion-based test runner. Packaging runs the tests, builds the release executable and recreates dist/VoiceOverlay.app with ad-hoc signing. It does not create a notarized public installer.

After the runtime is installed, check it using the explicit path:

```sh
NEMO="$HOME/Library/Application Support/NeMoSpeech/bin/nemo-speech"
"$NEMO" --version
"$NEMO" doctor
```

A Finder-launched app may have a different PATH from Terminal. Installation and launch instructions are in README.md.

## Architecture

- Sources/VoiceOverlay/: AppKit entry point, non-activating floating mic, menu bar, hotkeys, microphone recording and native text insertion.
- AppDelegate.swift wires the controller and language shortcuts together.
- AVRecorder.swift records 16 kHz mono 16-bit PCM WAV audio.
- MacPaster.swift preserves the target application, writes the clipboard, tries Accessibility insertion and falls back to Command-V. It currently leaves the transcript on the clipboard.
- Sources/VoiceOverlayCore/: protocol-based recording/transcription/paste state machine, runtime locator, subprocess runner, transcript cleanup and WAV preparation.
- OverlayController.swift owns best-effort cleanup of raw and prepared audio after transcription attempts.
- NemoSpeechTranscriber.swift invokes the local runtime with an argument array. Auto language adds no language flag; English uses --language en.
- CommandRunning.swift captures stdout/stderr in a private temporary directory to avoid pipe-buffer deadlocks.
- AudioPrep.swift trims silence and normalizes quiet audio. Int16 samples must be promoted to Int before abs to avoid Int16.min overflow.
- Tests/VoiceOverlayTestRunner/main.swift contains assertions, protocol doubles and regression tests for audio cleanup, full-scale PCM and large subprocess output.
- Resources/ contains app identity, version metadata and entitlements. scripts/package-app.sh builds the local app bundle.

## Working rules

1. Preserve the non-activating overlay and destination application's focus. Keep UI/state mutations on MainActor and transcription off the main thread.
2. Add a failing regression test before fixing production behavior, then make the smallest fix and rerun the suite. Generate audio fixtures; never use private recordings or clipboard contents.
3. Test recorders must own unique temporary directories and recording URLs. Never return a shared path that cleanup could delete. Remove only files/directories owned by the current test.
4. Pass executable paths and arguments separately to Process. Do not interpolate recording paths into shell commands or reintroduce wait-before-drain pipes.
5. Preserve cleanup of raw/prepared audio on success and failure. Crashes or removal errors can leave files; do not promise secure erasure or guaranteed zero retention.
6. Keep privacy claims accurate: the latest transcript is kept in memory and on the clipboard. Operational logs contain target app names, paths, events and transcript lengths, not transcript text. Do not add uploads, telemetry or retained history without approval.
7. Keep generated builds, recordings, weights, runtime binaries, logs, secrets and signing credentials out of Git. Inspect staged filenames and respect .gitignore.
8. Use home-directory APIs rather than developer-specific absolute paths. Preserve com.adarsh.voiceoverlay unless a new identity is requested; changing identity, location or signing can invalidate permission grants.
9. Keep changes scoped and preserve existing uncommitted work. Building dist/ is not permission to replace, launch or quit the user's installed app or alter its LaunchAgent.
10. Do not create a remote, push, publish releases or change global Git authentication without explicit permission. Use the GitHub account chosen by the maintainer, not whichever account happens to be logged in. Prefer repository-scoped identity/authentication.

## Handoff checks

For code changes, run the executable suite, packaging and signature verification. Use a fresh source-only checkout for release preparation. Run git diff --check and inspect staged files for credentials, private data and generated artifacts.

Mock-based tests do not verify live microphone permissions, every application's paste behavior, all languages, every Mac architecture or speech accuracy. Run those checks separately with consent and report what actually ran. Keep README shortcuts, setup instructions, product status and limitations aligned with the implementation.

## Licensing and release scope

Original app code uses Apache-2.0 (LICENSE and NOTICE). The separately installed NVIDIA runtime and model retain their own licenses; see THIRD_PARTY_NOTICES.md. Do not vendor binaries or weights without reviewing their exact revisions and redistribution obligations.

The current app is an early source-built developer release. Public Mac distribution still needs signing/notarization, installation/onboarding and manual permission/hotkey/paste testing. Do not imply NVIDIA or Wispr endorsement or unverified production readiness.
