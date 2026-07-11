from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from docs.codex_collab.tools import team_ops


class TeamOpsWorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.requests_dir = self.root / "docs" / "codex_collab" / "requests"
        self.specs_dir = self.root / "docs" / "superpowers" / "specs"
        self.plans_dir = self.root / "docs" / "superpowers" / "plans"
        self.requests_dir.mkdir(parents=True)
        self.specs_dir.mkdir(parents=True)
        self.plans_dir.mkdir(parents=True)
        (self.specs_dir / "design.md").write_text(
            "# 设计\n\n目标、非目标、验收场景、风险和错误处理均已明确。\n",
            encoding="utf-8",
        )
        (self.plans_dir / "plan.md").write_text(
            "# 实施计划\n\n- [ ] 写失败测试\n- [ ] 运行测试确认失败\n"
            "- [ ] 实现最小修复\n- [ ] 运行测试确认通过\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _request_text(self, **overrides: str) -> str:
        fields = {
            "Status": "in_progress",
            "Owner Lane": "android",
            "Source Thread": "019ee41d-647e-7250-bb01-f1ae81098696",
            "Target Version": "1.0.2",
            "Base Branch": "release/1.0.2",
            "Work Branch": "feature/1.0.2/AM-20260711-999-test",
            "Project Path": str(self.root),
            "Merge Branch": "release/1.0.2",
            "Created": "2026-07-11",
            "Updated": "2026-07-11",
            "Workflow": "superpowers-v1",
            "Work Type": "bugfix",
            "Risk Level": "P1",
            "User Visible": "yes",
            "Design Doc": "docs/superpowers/specs/design.md",
            "Implementation Plan": "docs/superpowers/plans/plan.md",
            "Required Skills": "systematic-debugging, test-driven-development",
            "TDD Mode": "required",
            "TDD Exception": "none",
            "TDD Exception Review": "not_applicable",
            "Baseline Commit": "abcdef1",
            "Head Commit": "abcdef2",
            "Root Cause Evidence": "复现后确认错误值来自缓存 key 冲突",
            "Research Evidence": "not_applicable",
            "Red Evidence": "test_cache_key 先失败，expected A got B",
            "Green Evidence": "test_cache_key 通过",
            "Targeted Tests": "python3 -m unittest test_cache - 4 passed",
            "Self Test Evidence": "小米 10 Pro 从搜索到播放闭环通过",
            "Product Main Path Evidence": "搜索、点击、播放和缓存结果均符合预期",
            "Baseline Freshness Evidence": "merge-base 与 release/1.0.2 最新提交一致",
            "Scope Diff Evidence": "git diff 仅包含本 request 的 2 个文件",
            "Spec Review Result": "accepted",
            "Code Quality Review Result": "accepted",
            "Full Verification Evidence": "flutter test 150 passed; analyze no issues",
            "Blocking Findings": "none",
            "Merge Evidence": "merge commit abcdef3 on release/1.0.2",
            "Push Evidence": "origin/release/1.0.2 at abcdef3",
            "Product Notification Evidence": "demo_ready 已回 product thread",
            "Knowledge Evidence": "docs/codex_collab/knowledge/android/cache.md",
        }
        fields.update(overrides)
        header = "\n".join(f"{key}: {value}" for key, value in fields.items())
        return f"# AM-20260711-999 测试任务\n\n{header}\n\n## 下一步\n- 回传证据。\n"

    def _write_request(self, **overrides: str) -> Path:
        path = self.requests_dir / "AM-20260711-999-test.md"
        path.write_text(self._request_text(**overrides), encoding="utf-8")
        return path

    def test_new_request_requires_superpowers_workflow(self) -> None:
        path = self._write_request(Workflow="")

        result = team_ops.validate_request_file(path)

        self.assertFalse(result.ok)
        self.assertTrue(any("Workflow" in error for error in result.errors))

    def test_design_gate_accepts_complete_request(self) -> None:
        path = self._write_request()

        result = team_ops.validate_workflow_file(path, gate="design")

        self.assertTrue(result.ok, result.errors)

    def test_start_gate_rejects_placeholder_plan(self) -> None:
        path = self._write_request()
        (self.plans_dir / "plan.md").write_text("# Plan\n\nTODO: implement later\n", encoding="utf-8")

        result = team_ops.validate_workflow_file(path, gate="start")

        self.assertFalse(result.ok)
        self.assertTrue(any("占位" in error for error in result.errors))

    def test_start_gate_rejects_worktree_project_path(self) -> None:
        path = self._write_request(
            **{"Project Path": "/Users/huangqi/AIHome/worktrees/ai_music/test"}
        )

        result = team_ops.validate_workflow_file(path, gate="start")

        self.assertFalse(result.ok)
        self.assertTrue(any("worktree" in error.lower() for error in result.errors))

    def test_bugfix_review_gate_requires_root_cause_and_red_green(self) -> None:
        path = self._write_request(
            **{
                "Root Cause Evidence": "pending",
                "Red Evidence": "pending",
                "Green Evidence": "pending",
            }
        )

        result = team_ops.validate_workflow_file(path, gate="review")

        self.assertFalse(result.ok)
        self.assertTrue(any("Root Cause Evidence" in error for error in result.errors))
        self.assertTrue(any("Red Evidence" in error for error in result.errors))
        self.assertTrue(any("Green Evidence" in error for error in result.errors))

    def test_research_review_gate_uses_research_evidence_without_tdd(self) -> None:
        path = self._write_request(
            **{
                "Work Type": "research",
                "User Visible": "no",
                "TDD Mode": "not_applicable",
                "Root Cause Evidence": "not_applicable",
                "Research Evidence": "低频脚本、JSON 结果和停止条件均已归档",
                "Red Evidence": "not_applicable",
                "Green Evidence": "not_applicable",
                "Product Main Path Evidence": "not_applicable",
            }
        )

        result = team_ops.validate_workflow_file(path, gate="review")

        self.assertTrue(result.ok, result.errors)

    def test_tdd_exception_requires_architect_acceptance(self) -> None:
        path = self._write_request(
            **{
                "TDD Mode": "exception",
                "TDD Exception": "生成代码无法稳定手写失败测试",
                "TDD Exception Review": "pending",
                "Red Evidence": "not_applicable",
                "Green Evidence": "not_applicable",
            }
        )

        result = team_ops.validate_workflow_file(path, gate="review")

        self.assertFalse(result.ok)
        self.assertTrue(any("TDD Exception Review" in error for error in result.errors))

    def test_merge_gate_requires_two_review_verdicts_and_fresh_verification(self) -> None:
        path = self._write_request(
            **{
                "Spec Review Result": "pending",
                "Code Quality Review Result": "pending",
                "Full Verification Evidence": "pending",
            }
        )

        result = team_ops.validate_workflow_file(path, gate="merge")

        self.assertFalse(result.ok)
        self.assertTrue(any("Spec Review Result" in error for error in result.errors))
        self.assertTrue(any("Code Quality Review Result" in error for error in result.errors))
        self.assertTrue(any("Full Verification Evidence" in error for error in result.errors))

    def test_close_gate_requires_merge_push_and_product_notification(self) -> None:
        path = self._write_request(
            **{
                "Merge Evidence": "pending",
                "Push Evidence": "pending",
                "Product Notification Evidence": "pending",
            }
        )

        result = team_ops.validate_workflow_file(path, gate="close")

        self.assertFalse(result.ok)
        self.assertTrue(any("Merge Evidence" in error for error in result.errors))
        self.assertTrue(any("Push Evidence" in error for error in result.errors))
        self.assertTrue(any("Product Notification Evidence" in error for error in result.errors))

    def test_superpowers_review_request_requires_head_tests_and_self_test(self) -> None:
        path = self._write_request()
        message = """type: review_request
request: AM-20260711-999
lane: android
thread: 019ee41d-647e-7250-bb01-f1ae81098696
status: review_requested
summary: 功能已经写完，准备交给架构师检查。
next_action: architect 完成 review 后回 android 和 product，并带结论证据。
"""

        result = team_ops.validate_message_text(message, request_path=path)

        self.assertFalse(result.ok)
        self.assertTrue(any("HEAD" in error for error in result.errors))
        self.assertTrue(any("测试" in error for error in result.errors))
        self.assertTrue(any("自测" in error for error in result.errors))

    def test_legacy_review_request_without_context_keeps_compatibility(self) -> None:
        message = """type: review_request
request: AM-20260705-017
lane: android-source
thread: 019f2fef-a4bb-7891-98b6-5f8b0bf3b17b
status: review_requested
summary: 旧任务协议回改已经完成，准备交给 reviewer 检查。
next_action: source-researcher 完成 review 后回 android-source 和 product，带协议证据。
"""

        result = team_ops.validate_message_text(message)

        self.assertTrue(result.ok, result.errors)

    def test_superpowers_review_result_requires_spec_and_quality_verdicts(self) -> None:
        path = self._write_request()
        message = """type: review_result
request: AM-20260711-999
lane: android
thread: 019ee41d-647e-7250-bb01-f1ae81098696
status: accepted
summary: review accepted，测试证据已确认，没有阻塞问题。
next_action: architect 请合入并回 product，带 commit 和推送证据。
"""

        result = team_ops.validate_message_text(message, request_path=path)

        self.assertFalse(result.ok)
        self.assertTrue(any("规格" in error for error in result.errors))
        self.assertTrue(any("代码质量" in error for error in result.errors))

    def test_legacy_review_result_without_context_keeps_compatibility(self) -> None:
        message = """type: review_result
request: AM-20260705-017
lane: android-source
thread: 019f2fef-a4bb-7891-98b6-5f8b0bf3b17b
status: accepted
summary: source-researcher 协议复核 accepted，脚本和真机测试证据均通过。
next_action: architect 请继续合入判断并回 product，带 commit 和推送证据。
"""

        result = team_ops.validate_message_text(message)

        self.assertTrue(result.ok, result.errors)

    def test_request_context_must_match_message_request(self) -> None:
        path = self._write_request()
        message = """type: review_result
request: AM-20260711-998
lane: android
thread: 019ee41d-647e-7250-bb01-f1ae81098696
status: accepted
summary: 规格符合性 accepted，代码质量 accepted，测试证据已确认。
next_action: architect 请合入并回 product，带 commit 和推送证据。
"""

        result = team_ops.validate_message_text(message, request_path=path)

        self.assertFalse(result.ok)
        self.assertTrue(any("request" in error and "不匹配" in error for error in result.errors))

    def test_request_context_title_must_match_filename(self) -> None:
        path = self.requests_dir / "AM-20260711-997-wrong-file.md"
        path.write_text(self._request_text(), encoding="utf-8")
        message = """type: review_result
request: AM-20260711-999
lane: android
thread: 019ee41d-647e-7250-bb01-f1ae81098696
status: accepted
summary: 规格符合性 accepted，代码质量 accepted，测试证据已确认。
next_action: architect 请合入并回 product，带 commit 和推送证据。
"""

        result = team_ops.validate_message_text(message, request_path=path)

        self.assertFalse(result.ok)
        self.assertTrue(any("文件名" in error and "requestId" in error for error in result.errors))

    def test_status_maps_to_expected_workflow_gate(self) -> None:
        self.assertEqual(team_ops.workflow_gate_for_status("proposed"), "design")
        self.assertEqual(team_ops.workflow_gate_for_status("in_progress"), "start")
        self.assertEqual(team_ops.workflow_gate_for_status("review_requested"), "review")
        self.assertEqual(team_ops.workflow_gate_for_status("accepted"), "merge")
        self.assertEqual(team_ops.workflow_gate_for_status("pushed"), "close")


if __name__ == "__main__":
    unittest.main()
