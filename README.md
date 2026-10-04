# Voice Overlay

**An open-source, local-first alternative to Wispr Flow for macOS.**

Hold a shortcut, speak, and insert the transcript into the app you are using without switching windows.

Voice Overlay is a native Swift/AppKit app that runs [NVIDIA NeMo-Speech.cpp](https://github.com/NVIDIA/NeMo-Speech.cpp) on your computer. The default speech model is **Nemotron 3.5 ASR**. It does not require a cloud transcription API or API key.

**Status:** early developer release, built from source. The packaging script creates an ad-hoc-signed app for local testing, not a Developer ID-signed or notarized public installer. No affiliation with NVIDIA is implied.

## A solid competitor to Wispr Flow

Voice Overlay is being built as a solid local-first competitor to Wispr Flow for everyday Mac dictation. It covers the core workflow: speak, transcribe, and insert text into a compatible app. Its focus is local speech processing, native keyboard controls, and an open codebase you can inspect or extend.

- Run speech recognition on your own Mac after installing the runtime and model; no cloud transcription account or API key is required.
- Dictate with a floating mic, menu-bar control, or global push-to-talk shortcuts.
- Recognize Hindi and English with automatic language detection, or select English recognition explicitly.
- Modify or build commercial products from the original app code under Apache-2.0, while respecting the separate runtime/model licenses.

The current release provides core dictation, not every feature of a mature writing assistant. It does not yet offer automatic text rewriting, speech translation, cross-platform clients, or a signed public installer. We do not claim better accuracy, lower resource use, or greater speed than Wispr Flow without testing both apps on the same hardware and audio.

## Requirements

- macOS 14 or newer.
- Swift 6.0 or newer and the macOS SDK, from compatible Xcode Command Line Tools or Xcode. Check with `swift --version` and `xcode-select -p`; install missing tools with `xcode-select --install`.
- A local `nemo-speech` installation and the downloaded `nemotron-3.5` model. The currently tested runtime is **0.1.0**.
- Internet access for the initial runtime/model download. Once installed, audio transcription runs locally.
- Apple Silicon is the locally verified platform. Intel builds and CPU runtime support need separate testing; the app is not currently a universal binary.

## 1. Install the speech runtime

Download and inspect the upstream installer before running it:

```sh
installer="$(mktemp -t nemo-speech-install)"
curl -fsSL https://raw.githubusercontent.com/NVIDIA/NeMo-Speech.cpp/main/scripts/install.sh -o "$installer"
# Read "$installer" before running the next command.
sh "$installer" --version 0.1.0
rm "$installer"

NEMO="$HOME/Library/Application Support/NeMoSpeech/bin/nemo-speech"
"$NEMO" --version
"$NEMO" pull nemotron-3.5
"$NEMO" doctor
```

The explicit binary path works even if the installer has not yet updated your shell's `PATH`. The model download is substantial; allow disk space for the runtime and weights. See the [upstream installation guide](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/docs/install.md) if binary installation falls back to a source build.

The app searches these locations, followed by its process `PATH`:

- `~/.local/bin/nemo-speech`
- `~/Library/Application Support/NeMoSpeech/bin/nemo-speech`
- `/opt/homebrew/bin/nemo-speech`
- `/usr/local/bin/nemo-speech`

Do not assume a Finder-launched app receives your terminal's `PATH`.

## 2. Build and open the app

From this repository's root:

```sh
swift run VoiceOverlayTestRunner
./scripts/package-app.sh
open dist/VoiceOverlay.app
```

The packaging script runs the tests, builds an optimized executable, and creates `dist/VoiceOverlay.app`. The test suite uses generated audio and test doubles; it does not download a model, record your microphone, or type into another app.

**Use `swift run VoiceOverlayTestRunner`, not `swift test`.** This project currently uses an executable assertion-based test runner, not an XCTest/Swift Testing target.

For a stable local installation, quit any running Voice Overlay instance and copy the built app to `~/Applications` using Finder. Launch that copy and grant permissions to that same copy. Avoid running both copies together. Changing the bundle identifier, app location, or signing identity may require macOS permissions to be granted again.

## 3. Grant macOS permissions

On first launch, allow **Microphone** access. Then enable **Accessibility** for Voice Overlay under **System Settings → Privacy & Security → Accessibility**. The menu-bar mic's right-click menu has **Enable Auto-Paste…** to open the settings.

Microphone permission is needed to record. Accessibility permission allows text insertion, paste, and global keyboard monitoring. If a shortcut does not work, check those permissions and conflicting system/application shortcuts. Do not disable macOS security protections to work around a failed launch.

## Usage

Focus the destination text field first, then speak using one of these controls:

| Control | Action |
| --- | --- |
| Hold **Right Option (⌥)** | Record with automatic language detection; release to transcribe and insert |
| Hold **Right Command (⌘)** | Record in English mode; release to transcribe and insert |
| **F5** or **Control + Option + V** | Start/stop automatic-language recording |
| **F6** | Start/stop English-mode recording |
| **Control + Option + H** | Show/hide the floating mic |
| Floating mic or menu-bar mic left-click | Start/stop automatic-language recording |
| Menu-bar mic right-click | Open the app menu, including Quit |

Drag the floating mic to reposition it. On keyboards where function keys control hardware, F5/F6 may require Fn.

Automatic detection supports the model's languages, including Hindi and English; mixed-language accuracy depends on the recording and model. **English mode sets the recognition language; it does not translate Hindi into English or rewrite your wording.** The text is inserted after recording stops, not streamed live as you speak.

## Privacy and current limitations

- Audio is captured as a local 16 kHz, mono, 16-bit PCM WAV. The app trims leading/trailing silence and invokes the local CLI for transcription.
- The controller attempts to remove both the original recording and prepared audio after success or failure. Cancellation while recording also removes the recording. File-removal errors, a crash, or a forced quit can leave files in the system temporary directory; this is not secure erasure.
- The latest transcript is kept in app memory and **remains on the system clipboard**. The current macOS paste implementation does not restore the previous clipboard, including when Accessibility insertion succeeds. Clipboard managers can retain copied text.
- Operational logs are written to `~/Library/Logs/VoiceOverlay.log`. They include target application names, paths, recording events, and transcript lengths, not the transcript text itself. Logs are not currently rotated automatically.
- There is no account, analytics integration, transcript-history database, or cloud transcription client in this app. Initial runtime/model installation needs network access.
- Silence detection can reject very quiet speech. There is no transcription timeout or in-progress transcription cancellation. Auto-paste compatibility varies between apps; password fields and other protected inputs may reject insertion.
- This repository does not include model weights, the speech runtime, signing certificates, or a public installer.

## Troubleshooting

- **“Nemotron is not installed”:** confirm the CLI exists in one of the searched locations and is executable; install it, then restart the app.
- **Model errors or first-run delays:** run `"$HOME/Library/Application Support/NeMoSpeech/bin/nemo-speech" pull nemotron-3.5` in Terminal first. Runtime configuration can change the selected model; see the upstream docs.
- **Recording works but text is not inserted:** check Accessibility for the exact app copy you launched, focus an ordinary text field, and try pasting manually from the clipboard.
- **“Heard silence”:** speak closer to the microphone and check the macOS input device/level. Silence trimming is intentionally conservative.
- **Permissions stopped working after a rebuild:** quit the old instance, launch the intended app copy, and re-enable its permission in System Settings if necessary.
- **Build failure:** confirm `swift --version` reports at least 6.0 and the selected developer tools provide the macOS SDK.

## Development

```sh
swift build
swift run VoiceOverlayTestRunner
./scripts/package-app.sh
codesign --verify --deep --strict dist/VoiceOverlay.app
```

The GitHub Actions workflow runs the mock-based suite and packaging on macOS; live microphone, hotkey, auto-paste, and model quality checks remain manual. VS Code tasks are supplied for build, tests, and packaging.

Coding agents should read [AGENTS.md](AGENTS.md) for setup commands, architecture, the Wispr Flow alternative product direction, and contribution safeguards.

## License and commercial use

Original Voice Overlay code is licensed under [Apache-2.0](LICENSE). Commercial use, modification, and redistribution are permitted subject to the license; keep the required license, copyright, and notice information. This is not an exclusive commercialization license and does not automatically entitle the original author to royalties from other people's products.

The external runtime and model have their own licenses. NeMo-Speech.cpp uses Apache-2.0; the configured `nvidia/nemotron-3.5-asr-streaming-0.6b` model uses **OpenMDW-1.1**, not this repository's Apache license. Read [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before bundling or redistributing either dependency. A paid distribution still needs its own packaging, signing, privacy, and license review.
