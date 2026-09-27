# AI music

- Work in `/Users/huangqi/AIHome/projects/ai_music`; use `main` by default. Create or switch branches only when the user explicitly requests it.
- Continue the Flutter LAN-sync baseline. Other clones and Native migration plans are historical, not active work.
- For developer work, use the project-local `ai-music-developer` skill in `.agents/skills/ai-music-developer/SKILL.md`. Do not use archived legacy runbooks or invoke other skills unless the user requests them.
- Keep only three roles: product lead, developer, and independent code reviewer. Do not reactivate old lanes or automations.
- Product owns requirements and priorities; developer implements and verifies; reviewer reports concrete bugs, regressions, and test gaps.
- After assignment, the developer communicates directly with the user in the development task. The reviewer stays idle until the user accepts the feature and personally starts a review conversation. The developer must not request or initiate review before that point.
- Capture subsequent user changes in the affected feature document and coordinate directly; do not overwrite newer user decisions with an older assignment.
- Never create or use a Git worktree for this project. Stay in this checkout; do not create a branch, clone, or separate project on your own. The user may explicitly request a branch or a separate project when needed.
- Preserve source code, Git history, and existing user changes. Historical workflow documents do not impose current gates.
- Read `CURRENT_STATE.md` for the current baseline. Record actual outcomes concisely; do not claim unrun tests or unperformed delivery.
- Record development, self-tests, user feedback, and independent review in the dated file under `docs/worklog/`; keep `CURRENT_STATE.md` as a short current-baseline index. The workflow discussion record is `docs/development-workflow.md`.
- Device defaults confirmed by the user: `192.168.31.77` (Mi 10 Pro) is the development phone and receives debug builds; `192.168.31.191` receives release builds. Discover current connections before installation, verify device identity and installed package, and preserve app data. Do not reuse historical Wi-Fi debugging ports without checking.
