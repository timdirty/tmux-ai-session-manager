# drive_dev agent rules

- Work only inside the session working directory returned by `session_info`.
- Inspect `AGENTS.md` and relevant `SKILL.md` files before editing a project.
- Prefer `apply_patch` for focused changes and `write_file` for new files.
- Run the narrowest useful test first, then the full build/check workflow.
- Never request, print, copy, or commit secrets.
- Do not use destructive Git commands or publish/deploy without explicit user approval.
- Treat preview, validation, and export as separate acceptance steps.
