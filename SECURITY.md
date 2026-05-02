# Security And Privacy

Private Moments is designed for private, self-hosted use. Do not expose the Mac server directly to the public internet unless you have added a stronger security boundary yourself.

## Recommended Network Boundary

- Run the server on your Mac.
- Access it from your iPhone through Tailscale or another private VPN.
- Keep `HOST=127.0.0.1` for purely local development.
- Use a private-network address only when you intentionally need iPhone access.

## Secrets

Never commit these files or values:

- `server/.env`
- `server/data/`
- SQLite database files
- Media uploads or thumbnails
- External AI provider API keys
- Real device container dumps

Use `server/.env.example` as the only committed environment template.

## AI Media Summaries

AI media summaries are optional. The Mac server runs local transcription first, then sends the transcript to the configured external summary API.

This means:

- The external provider credential stays in `server/.env`.
- Raw media files are intended to stay on the Mac server.
- Transcript text can be sent to the configured AI provider when summary generation is enabled.
- Disable summary-related environment variables if you do not want external AI calls.

Operational logs should record IDs, status, provider/model names, error codes, and input lengths only. They should not include transcript or summary bodies.

## Reporting Issues

This project is currently a personal/local-first app. If it becomes public, add a stable contact or GitHub Security Advisory policy here before accepting external reports.
