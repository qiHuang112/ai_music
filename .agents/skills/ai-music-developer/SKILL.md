---
name: ai-music-developer
description: Develop, fix, self-test, and prepare user trial builds for the AI Music Flutter app in /Users/huangqi/AIHome/projects/ai_music. Use for implementation work in this project, not for independent code review or claiming user acceptance.
---

# AI Music developer

Use this skill only for developer work in `/Users/huangqi/AIHome/projects/ai_music`. Follow the project's `AGENTS.md`; it and the user's current instructions take precedence. Archived legacy runbooks describe retired project layouts and role workflows.

## Workspace boundary

- Work in this one checkout on `main` by default. Create or switch branches only when the user explicitly requests it. Never create or switch to a Git worktree for AI Music. Do not create a clone or separate project as a workaround; if that is truly needed, explain why and wait for the user to request it.
- Inspect `git status`, `CURRENT_STATE.md`, and the affected feature document before changing code. Preserve existing edits and data. Treat older collaboration/lane plans as history, not active instructions.
- Use the bundled Flutter executable at `/Users/huangqi/AIHome/tools/flutter/bin/flutter`; do not assume `flutter` is on `PATH`.

## Develop and self-test

1. Record the latest requested behavior, failure behavior, and a few concrete user trial scenarios in the affected feature document. Update them when the user corrects an earlier request; implement the latest decision.
2. Reproduce a reported bug using the actual track, source, cache, or device state when relevant. Fix the cause and add a regression test when it can meaningfully reproduce the failure. For batch and asynchronous flows, check cancellation, out-of-order completion, source failure, retry, duplicate work, and persistence where applicable.
3. Test every code change. For a small change, run the relevant tests plus analysis and diff checks; add a matching manual UI/device check when behavior requires it. Before handing over a new trial build, run the full applicable suite and verify the build. Avoid rebuilding and reinstalling for every intermediate edit, but never call an untested change ready.
4. When a phone package is part of the task, preserve app data unless the user requested otherwise. Record the installed package's version, hash, and build time or source state. Check the actual install and only report device behavior that was observed. A package built before later review fixes does not contain those fixes, even when both states use the same checkout and branch.

## Handoff and review boundary

- Tell the user what changed, what development tests and device checks actually passed, and what still needs their trial. Developer self-test is not user acceptance; do not speak for the user's experience.
- Do not initiate independent review or message the reviewer before the user accepts the feature and personally starts review. After a user-started review, fix concrete findings, retest, and let the reviewer recheck. If a review fix changes visible behavior, provide an updated build for user trial; never treat the older installed package as reviewed code.
- When the user says to "review" or asks for the reviewer after accepting the feature, hand off to the existing Codex task titled **AI music-代码 review** (the project's fixed independent reviewer). Resolve that task with `mcp__codex_app__list_threads` and send the concrete scope with `mcp__codex_app__send_message_to_thread`. The user's request in the development chat authorizes this handoff. Do not substitute a `collaboration` sub-agent, start a new review task, or review in the development chat. If the fixed task cannot be found, ask the user instead of choosing another reviewer. Once the handoff succeeds, tell the user and continue the chat without waiting for the reviewer; the fixed reviewer will report findings when finished.
- Record development/self-test and review outcomes separately in that day's `docs/worklog/YYYY-MM-DD.md`. Keep `CURRENT_STATE.md` to a short current baseline and links. Do not repeat Git staging/push status in each log entry; inspect Git when that state matters.
