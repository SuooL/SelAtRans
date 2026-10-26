<div align="center">
  <img src="docs/assets/app-icon.png" width="96" height="96" alt="SelAtRans app icon">
  <h1>SelAtRans</h1>
  <p><strong>Select. Translate. Keep writing.</strong></p>
  <p>Natural English and Chinese, one shortcut away.<br>A native macOS utility with in-place replacement and a streaming floating preview.</p>
  <p>
    <a href="https://github.com/SuooL/SelAtRans/releases/latest"><img src="https://img.shields.io/github/v/release/SuooL/SelAtRans?color=168b90&label=download" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/macOS-13%2B-303846" alt="macOS 13 or later">
    <img src="https://img.shields.io/badge/Apple_Silicon_%2B_Intel-universal-303846" alt="Universal app for Apple Silicon and Intel">
    <a href="https://github.com/SuooL/SelAtRans/actions/workflows/ci.yml?query=branch%3Adev"><img src="https://github.com/SuooL/SelAtRans/actions/workflows/ci.yml/badge.svg?branch=dev" alt="Development CI status"></a>
  </p>
  <p><strong>English · <a href="README.zh-CN.md">简体中文</a></strong></p>
  <p><a href="https://github.com/SuooL/SelAtRans/releases/latest/download/SelAtRans.dmg"><strong>Download for macOS</strong></a> · <a href="#get-started">Get started</a> · <a href="CHANGELOG.md">What's new</a> · <a href="https://github.com/SuooL/SelAtRans/issues">Feedback</a></p>
</div>

## Translation where you write

Polish a message in English, read a passage in Chinese, or translate something you
just copied. Select text and press **⇧⌘E** for English or **⇧⌘C** for Simplified
Chinese. SelAtRans uses your own LLM API to produce natural, fluent wording while
preserving meaning, structure, terminology, and code.

| Translate to English · ⇧⌘E | Translate to Chinese · ⇧⌘C |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/preview-english-dark.png"><img src="docs/assets/preview-english-light.png" width="380" alt="English translation in the compact native floating preview"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/preview-chinese-dark.png"><img src="docs/assets/preview-chinese-light.png" width="380" alt="Chinese translation in the compact native floating preview"></picture> |

*Native preview components rendered offscreen with synthetic demonstration text;
these are UI previews, not a recording of a live API request. Settings and status
messages currently use Simplified Chinese.*

- **Replace the selection in place.** In a supported editable field, only the
  selected text changes; the clipboard stays as it was.
- **Watch the translation arrive.** Both directions stream into a preview that
  follows the floating icon, fits short text, and scrolls longer output.
- **Keep control of the result.** If you switch windows, move the caret, or edit
  the source while waiting, the original stays intact and the result goes to the clipboard.
- **Bring your own model.** Save multiple OpenAI-compatible Chat Completions
  profiles, switch the active one, and choose a per-profile reasoning effort.
  DeepSeek is the initial profile.
- **Keep the desktop quiet.** A draggable status icon, no menu bar or Dock item,
  no clipboard watcher, and no translation history on disk.

## Get started

**Requires macOS 13+ and your own compatible API access.** The same download
supports Apple Silicon and Intel. Translation needs an internet connection;
provider usage and billing follow your own API account.

1. [Download the latest DMG](https://github.com/SuooL/SelAtRans/releases/latest/download/SelAtRans.dmg),
   drag **SelAtRans** into **Applications**, and open it.
2. In **翻译配置**, add or select a profile. Enter the HTTPS API address, model ID,
   and API key, then click **保存并启用** (Save and activate).
3. In **快捷键与更新**, grant **Accessibility** permission for the installed app in
   macOS System Settings. This enables selection capture and safe replacement.
4. Select text and press **⇧⌘E** or **⇧⌘C**. You can change either shortcut in settings.

Current releases use a stable Apple Development signing identity. Developer ID
signing and Apple notarization are not configured. Download published release
assets; CI artifacts are staging builds.

### Configure your API

Profiles form an editable list: add, rename, edit, test, delete, and explicitly
activate one. You can save several profiles for the same provider with different
models, keys, or effort levels. Requests use only the active profile.

| Setting | What to enter |
| --- | --- |
| API address | Your provider's HTTPS base URL, including `/v1` if required. The app appends `/chat/completions` unless it is already present. |
| Model | The exact model ID available to your API account. |
| Effort | Start with **服务默认** (service default), which omits `reasoning_effort`. Choose another level only if your provider/model supports it. |
| API key | Enter it in settings. Each profile and endpoint origin has its own saved credential. |

**测试连接** (Test connection) sends a fixed synthetic greeting. It does not save
or activate the profile; use **保存并启用** when ready.

## Everyday controls

| Action | Behavior |
| --- | --- |
| **⇧⌘E** / **⇧⌘C** | Translate to English / Simplified Chinese. |
| Left-click the floating icon | Show or hide the preview and status, without taking focus or translating. |
| Drag the icon | Move it together with the expanded preview. |
| Right-click the icon | Open settings, explicitly translate clipboard text, pause/resume shortcuts, or quit. |
| Reopen SelAtRans | Bring settings back. |

| Source or situation | Where the result goes |
| --- | --- |
| Editable selection that can be safely replaced | Replace the selection; leave the clipboard unchanged. |
| Read-only selection | Put the translation on the clipboard. |
| No selection, confirmed by the app | Translate clipboard text and update the clipboard. |
| Window, caret, selection, or field text changes during the request | Keep the field unchanged; copy the translation and explain the fallback. |
| Selection capture is ambiguous, or the request fails | Stop with a status message; do not substitute stale clipboard text or write partial output. |

Streaming output is display-only until the complete response is validated. You
can manually copy the completed result from the preview.

## Privacy and resource use

Text is sent to the configured HTTPS provider only when you invoke translation
or the connection test. Provider retention policies apply. There is no background
clipboard monitoring or saved translation history; only the latest preview is
kept in memory. Idle operation has no translation polling or animation, and
streamed UI updates are coalesced. See [resource design and measurement limits](docs/PERFORMANCE.md).

API keys are **plaintext local files**, not Keychain items, in
`~/Library/Application Support/SelAtRans/Credentials`. Directory permissions are
`0700` and file permissions `0600`; this is access restriction, **not encryption**.
Other processes running as your user can read them. Keys are scoped to profile
and endpoint origin and kept out of Git. See [Security](SECURITY.md).

## FAQ

**Why did my selection go to the clipboard instead of being replaced?**

Accessibility support varies by app. SelAtRans replaces text only when it can
verify the editable target and confirm it has not changed. Otherwise, it copies
the completed translation and shows the reason.

**Why won't it translate the current selection?**

Confirm Accessibility is enabled for the installed app. If the editor exposes
neither selected text nor a usable Copy action, manually copy first, then choose
**Translate clipboard to English/Chinese** from the icon's right-click menu.
An uncertain selection never silently falls back to an older clipboard value.

**Where did the app go?**

Look for the floating desktop icon. There is no menu bar or Dock item. Reopening
the app brings up settings; right-click the icon to quit or pause shortcuts.

**How do updates work?**

Use **快捷键与更新 → 检查更新…**. Sparkle verifies signed updates from GitHub
Releases. Daily automatic checks can be disabled; installation requires your
confirmation. [All releases and downloads](https://github.com/SuooL/SelAtRans/releases).

**Do I need to enter my key again after upgrading from v0.1.1?**

Yes, once per profile. API keys moved from Keychain to private local files in
v0.1.2. Legacy Keychain items are never accessed or deleted.

## Build and contribute

Requires macOS Command Line Tools, Python 3, and network access for pinned
Sparkle and Gitleaks dependencies. Full Xcode is optional for compilation;
local packaging needs a stable signing identity (a free Xcode Personal Team
Apple Development identity is supported).

```sh
git clone https://github.com/SuooL/SelAtRans.git
cd SelAtRans
git config core.hooksPath .githooks
scripts/ci-test.sh
open build/package/SelAtRans.app
```

Development goes through a feature/fix/chore branch → PR → **dev** → release PR →
**main**, with required CI and automerge. Run the complete local gate before
committing or opening a PR. CI uses synthetic text and fake API keys; it does not
verify live provider behavior or cross-app desktop interactions.

- [Requirements and acceptance checks](docs/REQUIREMENTS.md)
- [Development and agent attribution](docs/DEVELOPMENT.md)
- [Versioning and signed releases](docs/RELEASING.md)
- [Report a bug or suggest a feature](https://github.com/SuooL/SelAtRans/issues)

If SelAtRans helps your workflow, star the repository or share the
[download page](https://github.com/SuooL/SelAtRans/releases/latest). Please keep
credentials and private source text out of public issues.
