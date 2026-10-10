---
name: ai-music-developer
description: Develop and fix AI Music, install and self-test on phone 77, and run the user-triggered independent code/release review, GitHub CI publication, and verified LAN mirror workflow in /Users/huangqi/AIHome/projects/ai_music.
---

# AI Music developer

This is AI Music's single workflow skill: development, device self-test, independent code/release review, and delivery. Follow the project's `AGENTS.md`; it and the user's current instructions take precedence. The former fixed **AI music-代码 review** conversation is archived. Do not route work to it, restore its role, or maintain separate reviewer/release skills. Archived legacy runbooks describe retired workflows.

## Workspace boundary

- Work in this one checkout on `main` by default. Create or switch branches only when the user explicitly requests it. Never create or switch to a Git worktree for AI Music. Do not create a clone or separate project as a workaround; if that is truly needed, explain why and wait for the user to request it.
- Inspect `git status`, `CURRENT_STATE.md`, and the affected feature document before changing code. Preserve existing edits and data. Treat older collaboration/lane plans as history, not active instructions.
- Use the bundled Flutter executable at `/Users/huangqi/AIHome/tools/flutter/bin/flutter`; do not assume `flutter` is on `PATH`.

## Develop and self-test

1. Record the latest requested behavior, failure behavior, and a few concrete user trial scenarios in the affected feature document. Update them when the user corrects an earlier request; implement the latest decision.
2. Reproduce a reported bug using the actual track, source, cache, or device state when relevant. Fix the cause and add a regression test when it can meaningfully reproduce the failure. For batch and asynchronous flows, check cancellation, out-of-order completion, source failure, retry, duplicate work, and persistence where applicable.
3. Test every code change. For a small change, run the relevant tests plus analysis and diff checks; add a matching manual UI/device check when behavior requires it. Before handing over a new trial build, run the full applicable suite and verify the build. Avoid rebuilding and reinstalling for every intermediate edit, but never call an untested change ready.
4. Standing user instruction (2026-10-10): after completing a fix and automated checks, build and archive the debug APK, install it directly on the 77 phone with app data preserved, and self-test the actual reported scenario on that installed build before asking the user to accept it. This instruction authorizes subsequent fix installations; do not ask the user to repeat the installation request. Verify package version/hash, preserved data and successful startup; exercise the affected real UI and service behavior, including pagination/source switching when relevant, and save evidence. A host-side API probe, automated tests, or installation alone does not replace this device self-test. Complete one coherent fix before building/installing, rather than every intermediate edit. If 77 is unavailable or self-test fails, continue troubleshooting and report the concrete limitation; never substitute 191, claim the device check passed, or hand an untested fix to the user for acceptance.
5. A requested commit includes pushing through `python3 tool/push_and_publish_android.py`. The user's “走流程” additionally authorizes the complete review-to-publication sequence below, including committing the reviewed changes after approval by the independent reviewer; do not ask again at each stage. GitHub Actions builds and signs the formal release, and the Mac mirrors those exact verified bytes to LAN. Do not duplicate routine release builds on the Mac. Explicit review-only requests stop at review; an instruction describing or changing this workflow does not itself start a release.
6. Retain every delivered debug/release APK with immutable version metadata in `/Users/huangqi/AIHome/releases/ai_music/android`, outside the disposable Flutter build directory. Never remove historical APKs during publishing or cleanup unless the user explicitly asks. Use `tool/publish_android_release.py` to publish a tested release and preserve the previous latest; use `tool/archive_android_apks.py` for debug/historical packages without changing the release update pointer. Read `docs/android-updates.md` for the currently deployed service and certificate/archival commands; do not assume Windows is serving when the live deployment is on the Mac.

## User trigger and temporary independent review

- Tell the user what changed and what automated/device checks actually passed. Developer self-test is not user acceptance. Do not start review or publication during ordinary development or before the user's trigger.
- “走流程” / “走流程吧” starts the complete sequence: independent code and release review → resolve findings and recheck → commit/push → verify GitHub CI publication → verify LAN mirror/download. Continue through completion; a review handoff or a successful push alone is not the final outcome. A request only to review authorizes the independent review stage without publication.
- Start one fresh, temporary reviewer with `collaboration.spawn_agent`, `fork_turns: "none"`, using inherited model settings. Pass the project path, this exact skill path, requirements, review scope, baseline/snapshot, tests and phone evidence. This user-triggered workflow authorizes that delegation. Do not create a permanent Codex review thread or use the archived fixed conversation. Keep the reviewer independent of the implementation history; it reads the actual code and evidence.
- Pin the review target before delegation: HEAD and applicable comparison commit, staged/unstaged diffs, relevant untracked source files, and their content hashes. Save the target and report under `build/review/`. Include all changes intended for the release, not just the last fix; explicitly list exclusions. Do not include signing secrets or private device data backups in the review bundle.
- For uncommitted changes, review both index and working tree plus new files. For unpublished commits/base-branch review, resolve the comparison ref/upstream and use the actual merge base, then include the pending changes. Stay in this checkout; no worktree, clone, reset or branch switch.
- The reviewer follows the next two sections in read-only mode. It may run appropriate tests/probes, but must not edit, stage, commit, push, publish, install, send messages, or delegate review further. The developer owns fixes and delivery.

### Independent code review instructions

1. Read `AGENTS.md`, this skill, the current feature requirements and the pinned target. Inspect the complete diff, relevant new files, surrounding code, call sites and tests. Continue through the whole scope after finding an issue.
2. Report concrete, introduced, actionable defects affecting correctness, security, performance or maintainability, with a demonstrated trigger/call path. Check async cancellation, out-of-order results, retries, identity/source changes, persistence/cache compatibility and UI/device behavior where affected. Do not report speculation, old defects, intended behavior changes or cosmetic preferences as blockers.
3. Verify meaningful regression coverage and distinguish automated tests, real service probes and checks on the actual installed build. Read the recorded phone version/hash and source stage; never assume an older installed build contains later fixes. Reproduce suspected defects with a focused probe when possible.
4. Return every qualifying finding, severity first: `[P0/P1/P2/P3] Actionable title — path:line`, followed by the trigger, impact and evidence. Cite the smallest relevant location in the changed code. P0 is a critical/universal blocker, P1 urgent, P2 ordinary, P3 low impact but actionable. If none qualify, say `No findings.` Include overall assessment, tests actually run, material gaps and the reviewed target identity.

### Release review instructions

1. Confirm the intended source scope/version, current phone self-test evidence and no unintended removal of user changes. Check the build/release configuration and relevant pipeline tests; do not substitute green CI from another commit for this target.
2. Confirm version allocation exceeds local retained APKs and GitHub release/draft codes. Keep `LOCAL_VERSION_FLOOR` at least the highest delivered debug code; account for arm64's +2000 offset and inspect the actual APK version. Require `com.qi.ai.music`, arm64-v8a, the existing trusted release certificate, and consistent manifest version/size/SHA-256. Debug trials must not replace the formal release pointer.
3. Review the delivery path for the affected changes: GitHub Actions signed publication with read-back verification, immutable historical artifacts, same-commit retry, no publication of superseded source, and atomic latest switching. Preserve old latest on failure; do not bypass signing/integrity checks or expose signing material.
4. Review LAN delivery and app update behavior where affected: mirror verified CI bytes without recompilation, verify the served metadata and full APK, prefer LAN silently and fall back to GitHub, enforce the same artifact for download fallback, and respect cancellation. Formal updates use the APP; 77 debug self-test remains separate and 191 is not an automatic install target.
5. Separate pre-publication review conclusions from checks that can only run after CI produces the APK. List the latter explicitly for the developer to complete; do not claim an unpublished release passed artifact/download checks.

### Findings, recheck and pass condition

- Fix actionable findings within the authorized scope, add/run meaningful regressions and necessary checks, and install/self-test app fixes on 77 before returning them for recheck. If a fix changes visible behavior, clearly identify the new phone build for the user; do not claim the earlier acceptance covers it or waive explicit user constraints.
- Have the temporary reviewer recheck the fixes and final target. Code or release-configuration changes after a pass invalidate that pass for the affected scope; unrelated work must stay excluded. Recording verified results alone does not require an endless review loop.
- Proceed only when the reviewer reports no remaining actionable findings and required pre-publication verification is complete. A failed/incomplete review or material unverified requirement is not a pass. Continue resolving issues and report concrete blockers if needed; do not publish merely because the review was started or tests are green.

## Automatic publication after “走流程” review passes

1. Recheck the final diff against the reviewed target, stage only reviewed files and commit with a description of the final behavior. Preserve unrelated edits. Then run `python3 tool/push_and_publish_android.py`; this pushes `origin/main` and triggers `.github/workflows/android-release.yml`. No additional approval is needed under this user trigger. Do not force push or publish unreviewed source.
2. Find and follow the workflow run for that exact pushed commit in `qiHuang112/ai_music`. Wait for its terminal result with concise progress updates and bounded waits. Diagnose failures, fix/retest/review the affected change and retry as appropriate. For an already pushed unchanged commit, `python3 tool/push_and_publish_android.py --publish-only` can trigger a retry. Never report a push, a running build or a different commit's successful job as publication success.
3. After successful CI, verify the public Release and `latest.json` correspond to the intended source commit and actual APK. Check package/version/channel/ABI, existing certificate, declared size and SHA-256 against the downloaded complete APK; retain immutable history. Report GitHub publication separately if the LAN step is still pending or fails.
4. Ensure the Mac LAN mirror is serving this verified CI artifact. The existing background service mirrors every 60 seconds; when needed run the following verified mirror command rather than rebuilding a release:

   ```sh
   JAVA_HOME=/Users/huangqi/Library/Java/JavaVirtualMachines/openjdk-22.0.1/Contents/Home \
   python3 tool/mirror_github_android_release.py \
     --root /Users/huangqi/AIHome/releases/ai_music/android \
     --aapt /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/aapt \
     --apksigner /Users/huangqi/Library/Android/sdk/build-tools/35.0.0/apksigner
   ```

5. Read `http://192.168.31.167:8788/api/v1/update/android`, compare source commit/version/size/hash with the published release, and download the complete served APK to verify size/SHA-256. Do not replace a newer release or claim LAN delivery based only on a copied file or healthy service. Preserve the old LAN latest on failure and continue diagnosis/retry; report any unresolved limitation accurately. The APP handles the silent LAN/GitHub choice.
6. Record the review target/report and resolved findings, commit, CI run, version, artifact hash, GitHub verification and LAN download result in `docs/worklog/YYYY-MM-DD.md`; keep `CURRENT_STATE.md` concise. Report the completed review/publication/LAN outcomes and update entry point to the user. Do not make an extra release-triggering commit only to record the previous run's final logs; keep those results for the next authorized commit.
