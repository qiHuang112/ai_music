# AI music Current State

Updated: 2026-09-25.

## Baseline

- Sole project: `/Users/huangqi/AIHome/projects/ai_music`.
- Branch: `main`; preserved code baseline: `2f8bf9d355df2e2ae7b52f2db8eadf42d1bf2bde`.
- Product: Flutter accepted version plus LAN music synchronization, not the Android Native rewrite.
- LAN features: read-only Python server, manifest size/SHA/audio validation, incremental synchronization, and folder-to-playlist mapping.
- Last reported baseline verification: 156 Flutter tests passed; analyze reported no issues. Skill cleanup does not rerun or extend that verification.
- Previous delivery record: `/Users/huangqi/AIHome/output/lamaze_guide/DELIVERY_RECORD.md`.
- GitHub remote: `git@github.com:qiHuang112/ai_music.git`; delivery target: `main` from this Flutter LAN project.
- Previous remote `main` (`5c255a92addde324b373e689fdcaae5f649413a2`) is preserved on GitHub as tag `archive/main-before-flutter-lan-20260925`. Other historical remote branches are unchanged.

## Active Roles

| Role | Task ID |
| --- | --- |
| Product lead | `019f4ed4-106e-7860-875d-a32f81629e4e` |
| Developer | `019f6b0e-972c-7eb1-91cd-a43cdbfa7d1e` |
| Code review | `01a0d7ac-1d39-7dd1-ae93-f47b3cccb0da` |

## Cleanup

- Personal skills moved outside discovery to `/Users/huangqi/.codex-disabled-skills/2026-09-25/personal`.
- All 90 currently discovered personal/system/plugin skills disabled in Codex configuration; reload requires restarting Codex.
- Old fixed team roles archived, histories preserved. The old AI Music automatic dispatcher is paused.
- Existing collaboration documents preserve historical facts only; `AGENTS.md` is the current project instruction.
- No feature development or device installation is requested by this cleanup.

## Delivery Review

- Independent review found no blocking issue in the documentation submission or obvious credentials/build artifacts in the current tracked tree. Full Git-history secret auditing was not performed.
- The relocated Flutter SDK instructions were corrected; LAN deployment instructions now restrict the firewall example to private networks and document unauthenticated access.
- Existing limitation: health checks hash the library; large-library performance needs separate validation. No application behavior was changed for repository consolidation.

## Active Feature

- Screenshot playlist import and next-track prefetch are approved for development; see `docs/screenshot-playlist-import.md`.
- Start from consolidated main `9934c8cdd7ff6e993c4a93607e6967a8e9f97d6e`. The developer owns implementation; code review is independent.
- User sample screenshots exist locally, but their paths have not yet been supplied. Do not claim they were inspected or tested.
- The developer works directly with the user and delivers the feature for user acceptance. The reviewer does no work until after acceptance, when the user personally starts a review conversation.
