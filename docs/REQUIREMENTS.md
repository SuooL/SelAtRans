# Product requirements — v0.1

## Confirmed behavior

SelAtRans is a local macOS utility backed by a user-configured OpenAI-compatible
Chat Completions endpoint. Translation is online; no local model is required.

| Input | Successful delivery |
| --- | --- |
| Selection in an editable field | Replace only that selection; leave the clipboard unchanged. |
| Selection in a read-only surface | Put the English translation on the clipboard. |
| No selection | Translate clipboard text and replace clipboard contents with the translation. |
| Focus, window, selected range, or field contents changed during translation | Preserve the field; copy the translation to the clipboard and explain the fallback. |
| No usable text or translation fails | Keep the original field and clipboard intact; show status. |

- Default global shortcut: **Shift–Command–E**. It is configurable.
- Produce natural, fluent English that sounds like a real person, preserving
  meaning, structure, terminology, and code. Return translation only.
- Already-English input should remain unchanged unless translation is necessary.
- A small draggable floating indicator shows idle, working, success, or error.
- Left click is status-only: never translates or steals keyboard focus.
- Right click exposes settings, shortcut pause/resume, and quit.
- No menu bar icon or Dock icon. Relaunching the app brings the indicator back.
- Settings include endpoint base URL, model, and API key; API keys live in Keychain.
- No credentials, private configuration, source text, or translations in Git.
- Only a deliberate shortcut sends text. No clipboard monitoring or background translation.

## Implementation decisions

- macOS 13 or later; native Swift/AppKit without third-party runtime dependencies.
- HTTPS endpoints only. Reject URL credentials, queries, and fragments so secrets
  cannot be accidentally persisted as part of endpoint configuration.
- API keys are scoped to their endpoint origin. Changing provider cannot silently
  send the previous provider's key to another host.
- If Accessibility cannot safely replace an editable selection, copy the result
  and show a fallback. Never synthesize a paste into an unverified target.
- Read selection through Accessibility first. A bounded Command-C fallback may
  temporarily use the clipboard for apps that do not expose selected text; restore
  prior clipboard representations after capture if no newer clipboard write occurred.
- No automatic retry, text history, or automatic submission/Enter key.
- English-only preservation is requested from the model; no unreliable local
  language guess silently bypasses the user's request.

## Acceptance checks

1. An editable selection is replaced without changing surrounding text or clipboard.
2. A read-only selection produces clipboard output.
3. Clipboard-only input produces clipboard output without changing an active field.
4. Changing focus, selection, window, or full field contents routes to clipboard.
5. API failure, empty input, and missing configuration preserve original state.
6. Rapid repeated shortcuts do not create concurrent requests.
7. Indicator click does not activate, translate, or move the text caret; dragging persists position.
8. Settings can save/reload endpoint/model and securely save/delete a provider-scoped key.
9. Shortcut conflicts and missing Accessibility permission are visible and actionable.
10. Secret scanning checks the working tree before commit and Git history in CI.
