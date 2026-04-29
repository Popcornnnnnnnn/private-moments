# GSD context snapshot (2026-04-29T19:18:28.245Z)

## Top project memories
- [MEM002] (architecture) Work planning mode Chose: Use lightweight continuous maintenance by default, with milestone/slice planning required for high-risk domains.. Rationale: Small UI and documentation changes should stay fast, while sync, schema migration, storage, backup, security, and cross-device work need explicit boundaries and evidence..
- [MEM001] (architecture) Persistent project workflow and documentation source of truth Chose: .gsd is the structured source for current facts, requirements, decisions, and milestone state; docs remains the stable human-facing documentation set.. Rationale: The project will continue to evolve across iOS, server, admin, sync, and storage; separating structured execution facts from stable operator/product docs reduces drift..
- [MEM006] (architecture) Moments product positioning for management and writing features Chose: Treat Moments as a private expression space, not a management database or writing editor.. Rationale: The user's north star is “一个没有观众的生活表达空间”: features should preserve lightweight expression, private feed-like browsing, and no audience pressure rather than optimizing for archiving or structured writing..
- [MEM008] (architecture) Text input assistance boundary Chose: Support plain-text list continuation only for bullet and numbered lists; do not render Markdown or add heading, bold, quote, or link-preview formatting.. Rationale: List continuation removes small input friction without turning Moments into a Markdown editor or long-form writing tool..
- [MEM005] (preference) Moments' product purpose is a private expression space with no audience: social-feed ease without social pressure, diary-level privacy without diary heaviness, and feed-like immersive browsing over a flowing personal timeline. Product decisions should preserve “表达，而不是记录”, “默认没有观众”, “时间是流动的”, and “本地优先”.
- [
…[truncated]
