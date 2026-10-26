"""Normalize agent attribution from runtime markers, never from API credentials."""

import os
import re
import sys
from pathlib import Path

IDENTITIES = {
    "codex": "Codex <codex@openai.com>",
    "claude": "Claude <noreply@anthropic.com>",
    "deepseek": "DeepSeek <noreply@deepseek.com>",
}
AGENT_LINE = re.compile(r"^Co-authored-by:\s*(?:Codex|OpenAI Codex|Claude|DeepSeek)\s*<[^>]+>\s*$", re.I)


def detect(env):
    explicit = env.get("SELATRANS_AGENT", "").strip().lower()
    if explicit:
        if explicit not in IDENTITIES:
            raise ValueError("SELATRANS_AGENT must be codex, claude, or deepseek.")
        return explicit
    markers = {
        "codex": any(env.get(k) for k in ("CODEX_THREAD_ID", "CODEX_SESSION_ID")),
        "claude": any(env.get(k) for k in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT")),
        "deepseek": bool(env.get("DEEPSEEK_AGENT_SESSION_ID")),
    }
    active = [name for name, enabled in markers.items() if enabled]
    if len(active) > 1:
        raise ValueError("Ambiguous agent session; explicitly set SELATRANS_AGENT.")
    return active[0] if active else None


def normalize(message, agent):
    if agent is None:
        return message
    body = "\n".join(line for line in message.splitlines() if not AGENT_LINE.match(line)).rstrip()
    return body + "\n\nCo-authored-by: " + IDENTITIES[agent] + "\n"


if __name__ == "__main__":
    try:
        action, path = sys.argv[1:]
        source = Path(path).read_text()
        agent = detect(os.environ)
        result = normalize(source, agent)
        if action == "commit":
            Path(path).write_text(result)
        elif action == "body":
            sys.stdout.write(result)
        elif action == "verify":
            if agent and source != result:
                raise ValueError("Agent attribution mismatch; enable .githooks or run the prepare hook.")
        else:
            raise ValueError("Unknown attribution action.")
    except (ValueError, OSError) as error:
        sys.exit(str(error))
