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
- Delivery rule (user 2026-10-10): every requested commit includes pushing to `origin/main`. Use `python3 tool/push_and_publish_android.py`: the push triggers `.github/workflows/android-release.yml` to check, build with the existing Android release key, verify, and publish APK + `latest.json` to GitHub Releases. Do not also build/upload manually on the Mac for routine delivery. Report push and CI publication separately; verify the Actions result before claiming a package is published. An authenticated GitHub CLI can retry an already pushed clean commit with `--publish-only`; `--lan` explicitly retains the previous Mac LAN delivery mode. Preserve historical APKs. Users update from the APP over GitHub; do not install via ADB by default. Debug trial installation on 77 is only for a user-requested trial; never fall back to 191. Preserve app data. See `docs/android-updates.md` for one-time signing Secrets setup and version allocation.

- Workflow shortcut (user 2026-10-05): “走流程” means hand off review to the existing Codex task titled **AI music-代码 review**, exactly like “review”. Send the scope and evidence, then return to the user without waiting. Do not substitute a collaboration sub-agent or initiate a new review task.
