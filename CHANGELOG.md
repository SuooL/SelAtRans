# Changelog

## 0.1.3

- Keep the expanded translation preview attached while dragging the floating icon.
- Fit preview height to its text and status, growing during streaming and scrolling long output.
- Keep the preview on the active screen, including narrow and secondary displays.
- Draw a rounded background with transparent corners in light and dark appearances.
- Cache text measurements and retain the existing coalesced streaming updates without idle polling.

## 0.1.2

- Store LLM API keys in private local files instead of Keychain, avoiding password prompts.
- Require one-time key re-entry after upgrading; never access legacy API Keychain entries.
- Distinguish missing selection metadata from an explicitly empty selection.
- Read selected text through Accessibility ranges when direct selected text is unavailable.
- Refuse ambiguous or timed-out selection capture instead of translating stale clipboard text.
- Add explicit clipboard translation actions to the floating indicator's right-click menu.

## 0.1.1

- Publish the first signed update feed and universal macOS release.
- Clear stale floating Accessibility warnings when permission is granted.
- Explain an unpublished update feed in Chinese instead of showing a generic error.
- Keep permission and update information accessible in a scrolling settings panel.
- Require the complete local CI gate before commits and pull requests.

## 0.1.0

- Translate editable selections in place using Shift–Command–E (English) or Shift–Command–C (Chinese).
- Stream translations into a nonactivating preview; only deliver complete responses.
- Copy translated read-only selections and clipboard input to the clipboard.
- Preserve the original field and copy the translation when the target changes.
- Show a draggable floating status indicator without menu bar or Dock clutter.
- Manage multiple LLM configurations and select an active configuration.
- Configure per-profile reasoning effort, including DeepSeek support.
- Store profile- and origin-scoped credentials in macOS Keychain.
- Check for signed updates with Sparkle and GitHub Releases.
- Use the existing Apple Development identity for stable local/release signing.
- Refresh Accessibility status on return to the app and protect running bundles from overwrite.
- Use protected dev/main branches, required CI, and agent-aware attribution.
