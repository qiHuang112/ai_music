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
- Device delivery rule (user correction 2026-10-05): default to a debug build installed on `192.168.31.77` (Mi 10 Pro). Install release on `192.168.31.191` only when the user explicitly requests that release delivery. A prior release installation request, remembered port, or currently connected 191 device does not authorize installing later feature builds there. Do not use 191 as a fallback when 77 is unavailable. Discover current connections, verify device identity and installed package, and preserve app data; request 77's current wireless-debugging connection port if discovery fails. Debug delivery archives the APK without changing the release update pointer; publish release updates only for an explicitly requested release delivery.

- Workflow shortcut (user 2026-10-05): “走流程” means hand off review to the existing Codex task titled **AI music-代码 review**, exactly like “review”. Send the scope and evidence, then return to the user without waiting. Do not substitute a collaboration sub-agent or initiate a new review task.
