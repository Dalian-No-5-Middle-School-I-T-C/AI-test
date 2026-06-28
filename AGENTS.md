# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
This repo is an **AI model evaluation harness**, not a single deployable app. Each top-level directory (`claude`, `composer`, `deepseek`, `doubao`, `ernie`, `gemini`, `glm`, `gpt`, `kimi`, `mimo`, `minimax`, `qwen`) is an **independent, standalone HarmonyOS (ArkTS) DevEco project** — all 12 are different model implementations of the same task described in `question.md` (a DeepSeek AI chat phone app). They do not depend on each other. The acceptance gate per `README.md` is: the project compiles under hvigor, then the app runs.

### Toolchain (already installed in the VM snapshot)
HarmonyOS command-line-tools **6.1.0.830 (SDK API 23 / HarmonyOS 6.1.0, hvigor 6.23.5, ohpm 6.1.1.830, codelinter 6.0.240, hdc 3.2.0c)** live at `/home/ubuntu/command-line-tools`. `~/.bashrc` puts only `/home/ubuntu/command-line-tools/bin` on `PATH` and sets `DEVECO_SDK_HOME=/home/ubuntu/command-line-tools/sdk`, so a fresh login shell can run `hvigorw`, `ohpm`, `codelinter`, and `hstack` directly.

- The tools bundle their own Node (v18) under `tool/node`, and the `hvigorw`/`ohpm` wrappers self-resolve it via `DEVECO_NODE_HOME`. We deliberately do NOT add `tool/node/bin` to `PATH`, so the default `node` in a shell stays the system nvm Node (v22); adding it would shadow the system Node. You do not need to set `NODE_HOME`/`DEVECO_NODE_HOME` manually.

- The projects pin hvigor `modelVersion: 6.1.0` and `compatibleSdkVersion: 6.1.0(23)`. They will NOT build with older command-line-tools (e.g. the publicly mirrored `6.0.1`), which fail with `Unsupported modelVersion of Hvigor 6.1.0` / missing API 23. The 6.1.0 toolchain is required and is what is installed.

### Build / lint a project
Run inside any one model directory (example uses `claude`):
- Install deps: `ohpm install` (pulls `@ohos/hypium`, `@ohos/hamock` from the public `ohpm.openharmony.cn` registry).
- Build: `hvigorw assembleHap --no-daemon` → output HAP at `entry/build/default/outputs/default/entry-default-unsigned.hap`.
- Lint: `codelinter` (uses the project's `code-linter.json5`).

### Non-obvious caveats
- The produced HAP is **unsigned** — projects ship empty `signingConfigs`, so hvigor prints `Will skip sign 'hos_hap'` and emits `entry-default-unsigned.hap`. This is expected; signing needs DevEco Studio signing setup and is not required to pass the build gate.
- ArkTS `WARN` lines during `CompileArkTS` (e.g. "Function may throw exceptions", deprecated `showToast`/`getContext`) are warnings, not errors, and do not fail the build.
- **The apps cannot be launched headless in this VM.** Running a HarmonyOS app requires the DevEco Studio emulator (GUI + hardware virtualization) or a physical device, neither of which is available here. The achievable end-to-end validation is compiling to a HAP (+ codelinter). The repo's own acceptance flow treats a passing compile as completion.
- There is no CLI test runner available for the in-repo tests: local unit tests (`entry/src/test`) and instrumentation tests (`entry/src/ohosTest`) run through DevEco Studio's test runner or against a device/emulator, so they cannot be executed in this headless environment.
- At runtime the app is a DeepSeek chat client: it needs a user-supplied API key entered in-app and network access to `https://api.deepseek.com`. There is no in-repo backend or database (on-device storage only).
