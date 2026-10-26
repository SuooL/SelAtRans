# Product requirements — v0.1

## Confirmed behavior

SelAtRans is a local macOS utility backed by a user-configured OpenAI-compatible
Chat Completions endpoint. Translation is online; no local model is required.
Shift–Command–E targets natural English; Shift–Command–C targets natural Simplified
Chinese. Both actions share the selected profile and all delivery protections.

| Input | Successful delivery |
| --- | --- |
| Selection in an editable field | Replace only that selection; leave the clipboard unchanged. |
| Selection in a read-only surface | Put the target-language translation on the clipboard. |
| No selection | Translate clipboard text and replace clipboard contents with the translation. |
| Focus, window, selected range, or field contents changed during translation | Preserve the field; copy the translation to the clipboard and explain the fallback. |
| No usable text or translation fails | Keep the original field and clipboard intact; show status. |

- Default global shortcuts: **Shift–Command–E** (English), **Shift–Command–C**
  (Chinese). Both are configurable, and cannot be assigned the same key chord.
- Produce natural, fluent target-language text that sounds like a real person, preserving
  meaning, structure, terminology, and code. Return translation only.
- Input already in the target language should remain unchanged.
- A small draggable floating indicator shows idle, working, success, or error.
- Left click toggles status/translation preview: never translates or steals focus.
- Translation previews stream incrementally for both directions. They open during
  a request, can be collapsed, and retain only the latest result in memory. No
  partial result may be delivered or copied; a normal stop and stream terminator
  are required before replacement/clipboard output. Final results can be manually copied.
- Right click exposes settings, shortcut pause/resume, and quit.
- No menu bar icon or Dock icon. Relaunching the app brings the indicator back.
- Settings show a CRUD list of LLM profiles. Each has a name, endpoint, model,
  reasoning effort, and independent Keychain credential. Choose one saved profile
  as active; there is no implicit fallback to a different provider.
- DeepSeek is the initial provider. Its effort choices are provider default,
  none, low, high, and max. Generic compatible endpoints also expose minimal,
  medium, and xhigh; the user must select a level their model supports.
- No credentials, private configuration, source text, or translations in Git.
- Only a deliberate shortcut sends text. No clipboard monitoring or background translation.

## Implementation decisions

- macOS 13 or later; native Swift/AppKit with exact-version-pinned Sparkle for updates.
- HTTPS endpoints only. Reject URL credentials, queries, and fragments so secrets
  cannot be accidentally persisted as part of endpoint configuration.
- API keys are scoped to profile UUID and endpoint origin. Changing provider cannot silently
  send the previous provider's key to another host.
- If Accessibility cannot safely replace an editable selection, copy the result
  and show a fallback. Never synthesize a paste into an unverified target.
- Read selection through Accessibility first. A bounded Command-C fallback may
  temporarily use the clipboard for apps that do not expose selected text; restore
  prior clipboard representations after capture if no newer clipboard write occurred.
- No automatic retry, text history, or automatic submission/Enter key.
- Target-language preservation is requested from the model; no unreliable local
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
11. Add, edit, delete, test, and activate independent LLM profiles; deleting the
    active profile disables translation until another profile is explicitly enabled.
12. Version changes pass through dev/main PRs; release tags produce verified ZIP,
    DMG, checksums, and a signed appcast. Updates use project-specific signing keys.
13. Idle operation has no clipboard polling, translation timers, or active context
    listeners. Animation and context listeners exist only during a translation.
14. Chinese-target prompts and both shortcut identities remain independent.
    Streaming handles keepalive/usage events and Unicode, ignores reasoning, and
    rejects disconnects, malformed/truncated output, or oversized responses.
15. Local/release builds share a certificate-backed identity across changed code;
    CI ad-hoc artifacts are staging only and cannot be published directly.

## Provider references

- [DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)
- [DeepSeek thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/)
- [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
- [Sparkle publishing](https://sparkle-project.org/documentation/publishing/)
