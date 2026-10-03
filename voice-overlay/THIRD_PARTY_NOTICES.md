# Third-party components and redistribution

The repository contains the original Swift app and its tests, not NVIDIA runtime binaries, model weights, or vendored Swift dependencies. The default packaging script includes only the app executable and its metadata. Dependencies are installed separately by the user.

## NeMo-Speech.cpp runtime

- Upstream: https://github.com/NVIDIA/NeMo-Speech.cpp
- Locally tested CLI version: **0.1.0**
- Upstream license: **Apache License 2.0**
- Upstream copyright notice: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
- License: https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/LICENSE
- Notice: https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/NOTICE
- Dependency inventory: https://github.com/NVIDIA/NeMo-Speech.cpp/blob/main/THIRD_PARTY_NOTICES.md

This runtime is an external executable, not part of Voice Overlay's Swift source. An installed distribution has its own license/notice files under `share/licenses/nemo-speech/`; retain those when redistributing that distribution. Its dependencies have their own terms—do not assume everything inside a runtime package is Apache-2.0. For example, upstream inventories include MIT/BSD components and optional LGPL components; review the actual build you intend to bundle.

## Nemotron 3.5 ASR model

- Model: `nvidia/nemotron-3.5-asr-streaming-0.6b`
- CLI alias: `nemotron-3.5`
- Model card: https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- Revision recorded in the locally installed runtime index: `1c8deaecc64b91f034d73e08dd8b64625eb3395d`
- Revision-specific card: https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b/blob/1c8deaecc64b91f034d73e08dd8b64625eb3395d/README.md
- That revision's model-card license name: **OpenMDW-1.1**
- Official agreement: https://openmdw.ai/license/1-1/

The model is downloaded by `nemo-speech pull nemotron-3.5`, not stored in this repo. Its license is independent of the app's Apache-2.0 license. OpenMDW-1.1 grants broad usage rights, including commercial use, subject to its terms; redistribution of model materials requires the agreement and applicable copyright/origin notices to accompany the distribution. Refer to the full agreement rather than treating this paragraph as a substitute.

The runtime's index also labels the model as “NVIDIA Open Model License (OpenMDW 1.1)”; the revision-specific Hugging Face card directly points to the OpenMDW-1.1 agreement above. Check the exact model/revision again if the runtime index or selected model changes.

## macOS frameworks and developer tools

The app uses system-provided Apple frameworks (AppKit, AVFoundation, ApplicationServices, Carbon and CoreGraphics) and the Swift toolchain. This repository does not redistribute an Apple SDK, Xcode, or those frameworks. Their use and any signed Mac distribution remain subject to the applicable Apple terms.

## Before bundling dependencies or selling a distribution

1. Inventory the exact runtime build, shared libraries, model revision and any installer dependencies.
2. Copy the applicable license texts, copyright/origin notices and attribution files into the distribution; meet any additional component-specific obligations.
3. Do not replace dependency licenses with this repository's LICENSE or imply ownership of NVIDIA model weights.
4. Do not imply NVIDIA endorsement or a trademark license. Apache-2.0 does not grant trademark rights.
5. Recheck licenses when dependencies/models change and obtain legal review where needed for the planned distribution.

Commercial use of the original app code is permitted under Apache-2.0; that does not guarantee that an arbitrary future bundle is compliant. No runtime/model redistribution is performed by this repository's default packaging workflow.
