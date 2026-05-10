# Security And Privacy

Private Moments is designed for private, self-hosted use. Do not expose the Mac server directly to the public internet unless you have added a stronger security boundary yourself.

## Recommended Network Boundary

- Run the server on your Mac.
- Access it from your iPhone through a restricted Cloudflare Tunnel HTTPS endpoint for the owner setup.
- Keep Tailscale or another private VPN as an emergency fallback or diagnostic route, not the daily default.
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

## AI Generated Metadata

AI media summaries and periodic reviews are optional generated metadata. For audio/video summaries, the Mac server runs local transcription first, then sends the transcript to the configured external summary API. For periodic reviews, the Mac server builds a bounded review input pack from the selected period, including moment text, comments, safe metadata, tags, and ready audio/video summary metadata, then sends that pack to the configured external review API.

This means:

- The external provider credential stays in `server/.env`.
- Raw media files are intended to stay on the Mac server.
- Transcript text can be sent to the configured AI provider when summary generation is enabled.
- Moment text, comments, and ready summary metadata can be sent to the configured AI provider when periodic review generation is enabled.
- Disable summary/review-related environment variables if you do not want external AI calls.

Operational logs should record IDs, status, provider/model names, error codes, and input lengths only. They should not include transcript, summary, review, post, or comment bodies.

## Backup And Restore

Mac Admin Archive uses restic snapshots for owner recovery. The project creates a `.private-moments-restic-key` next to the configured repository so the owner does not need to remember a separate backup password.

Security implication:

- The repository and `.private-moments-restic-key` together are enough to restore the archive.
- iCloud Drive can be used as a user-selected folder, but the app does not provide a separate encrypted cloud-backup product.
- Do not publish or share the repository, key file, restored data directories, `archive/pending-promote.json`, or maintenance job artifacts if they include local paths.
- Backup/restore logs and job metadata should contain paths, IDs, counts, statuses, and error codes only, not private post text, comments, transcripts, summaries, or media bodies.

## Reporting Issues

This project is currently a personal/local-first app. If it becomes public, add a stable contact or GitHub Security Advisory policy here before accepting external reports.
