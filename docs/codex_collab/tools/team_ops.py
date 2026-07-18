#!/usr/bin/env python3
"""Hard-rule checks for the AI Music Codex collaboration ledger."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


ALLOWED_TYPES = {
    "task",
    "status",
    "demo_ready",
    "review_request",
    "review_result",
    "handoff",
    "blocker",
    "team_rule",
    "task_assignment",
    "changes_requested",
    "escalation",
}

ALLOWED_LANES = {
    "mobile-ai-music-product",
    "mobile-ai-music-ux",
    "mobile-ai-music-developer",
    "mobile-ai-music-lead",
    "product",
    "architect",
    "android",
    "android-source",
    "android-streaming",
    "android-discovery",
    "android-voice",
    "ios",
    "ohos",
    "ui",
    "qa",
    "release-manager",
    "source-researcher",
    "playlist-researcher",
    "streaming-researcher",
    "xiaoai-researcher",
    "qa-researcher",
}

ALLOWED_MESSAGE_STATUSES = {
    "proposed",
    "assigned",
    "in_progress",
    "review",
    "ready_to_try",
    "beta_ready",
    "self_tested",
    "accepted",
    "changes_requested",
    "accepted_pending_merge",
    "accepted_pending_push",
    "merged",
    "pushed",
    "verified",
    "failed",
    "blocked",
    "acknowledged",
    "review_requested",
    "action_required",
    "continue_required",
    "continue_now",
    "assigned_onboarding",
    "not_ready",
}

ALLOWED_REQUEST_STATUSES = {
    "proposed",
    "assigned",
    "in_progress",
    "self_tested",
    "review_requested",
    "review",
    "changes_requested",
    "accepted",
    "accepted_pending_merge",
    "accepted_pending_push",
    "accepted_ohos_pending_android_p2",
    "accepted_pushed_verified",
    "merged",
    "pushed",
    "notified",
    "verified",
    "device_verified",
    "failed",
    "blocked",
}

WORKFLOW_NAME = "superpowers-v1"
WORKFLOW_REQUIRED_FROM = "2026-07-11"
WORKFLOW_GATES = ("design", "start", "review", "merge", "close")
ALLOWED_WORK_TYPES = {"feature", "bugfix", "refactor", "research", "process", "release"}
ALLOWED_RISK_LEVELS = {"P0", "P1", "P2", "P3"}
ALLOWED_TDD_MODES = {"required", "exception", "not_applicable"}
PENDING_VALUES = {"", "pending", "todo", "tbd", "none", "n/a", "not_applicable"}
PLACEHOLDER_PATTERN = re.compile(
    r"(?im)\b(?:TBD|TODO|implement later|fill in details)\b|待补|稍后再实现"
)

SECRET_PATTERNS = [
    re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*\S+"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"(?i)-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----"),
]

CALLBACK_TERMS = (
    "回",
    "同步",
    "通知",
    "review",
    "证据",
    "测试",
    "提交",
    "路径",
    "commit",
    "完成后",
    "owner",
    "blocker",
    "架构师",
    "product",
    "qa",
    "release-manager",
    "研究员",
    "researcher",
)

GENERIC_NEXT_ACTIONS = {
    "继续推进",
    "继续处理",
    "看一下",
    "再看看",
    "等反馈",
    "等回复",
    "待确认",
    "尽快处理",
    "跟进一下",
}


@dataclass
class CheckResult:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    @property
    def ok(self) -> bool:
        return not self.errors


def parse_key_values(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    current_key: str | None = None
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$", line)
        if match:
            current_key = match.group(1).strip()
            data[current_key] = match.group(2).strip()
        elif current_key and line.startswith((" ", "\t")):
            data[current_key] = f"{data[current_key]}\n{line.strip()}".strip()
    return data


def parse_request_id(text: str) -> str | None:
    match = re.search(r"(?m)^#\s+(AM-[A-Za-z0-9-]+)(?:\s|$)", text)
    return match.group(1) if match else None


def check_secrets(text: str, result: CheckResult) -> None:
    for pattern in SECRET_PATTERNS:
        if pattern.search(text):
            result.error("内容疑似包含 secret/token/password/private key，禁止写入协同消息或账本")


def validate_message_text(
    text: str,
    *,
    request_path: Path | None = None,
) -> CheckResult:
    result = CheckResult()
    check_secrets(text, result)
    data = parse_key_values(text)
    required = ["type", "request", "lane", "thread", "status", "summary", "next_action"]
    for field_name in required:
        if not data.get(field_name):
            result.error(f"消息缺少必填字段 `{field_name}:`")

    msg_type = data.get("type", "")
    request = data.get("request", "")
    lane = data.get("lane", "")
    status = data.get("status", "")
    summary = data.get("summary", "")
    next_action = data.get("next_action", "")
    message_workflow = data.get("workflow", "")
    superpowers_message = message_workflow == WORKFLOW_NAME

    if message_workflow and message_workflow != WORKFLOW_NAME:
        result.error(f"消息 `workflow` 不在允许范围内: {message_workflow}")
    if request_path is not None:
        if not request_path.is_file():
            result.error(f"消息 request 上下文文件不存在: {request_path}")
        else:
            request_text = request_path.read_text(encoding="utf-8")
            request_fields = parse_request_header(request_text)
            context_request = parse_request_id(request_text)
            if context_request is None:
                result.error(f"消息 request 上下文无法解析 requestId: {request_path}")
            else:
                request_stem = request_path.stem
                if not (
                    request_stem == context_request
                    or request_stem.startswith(f"{context_request}-")
                ):
                    result.error(
                        "`--request-file` 文件名与任务单 requestId 不匹配: "
                        f"{request_stem} != {context_request}"
                    )
                if data.get("request") != context_request:
                    result.error(
                        "消息 `request` 与 `--request-file` 不匹配: "
                        f"{data.get('request', '')} != {context_request}"
                    )
            superpowers_message = (
                superpowers_message
                or request_fields.get("Workflow") == WORKFLOW_NAME
            )

    if msg_type and msg_type not in ALLOWED_TYPES:
        result.error(f"`type` 不在允许范围内: {msg_type}")
    if lane and lane not in ALLOWED_LANES:
        result.error(f"`lane` 不在允许范围内: {lane}")
    if lane == "all":
        result.error("禁止用 `lane: all` 广播；只能发给相关 lane")
    if status and status not in ALLOWED_MESSAGE_STATUSES:
        result.error(f"`status` 不在允许范围内: {status}")
    if request and not re.match(r"^AM-[A-Za-z0-9-]+$", request):
        result.error(f"`request` 必须以 AM- 开头且不含空格: {request}")
    if data.get("thread") and not re.match(r"^[0-9a-f-]{10,}$", data["thread"]):
        result.warn("`thread` 看起来不像 Codex threadId；如果是临时占位，请尽快补齐真实 threadId")
    if summary and len(summary) < 12:
        result.error("`summary` 太短，必须写新增事实，不能只写泛泛状态")
    if next_action:
        normalized = re.sub(r"\s+", "", next_action)
        if normalized in GENERIC_NEXT_ACTIONS:
            result.error("`next_action` 太泛，必须写清谁做、做什么、完成后回给谁、带什么证据")
        if len(next_action) < 16:
            result.error("`next_action` 太短，必须写清可执行动作和回传路径")
        if not any(term in next_action for term in CALLBACK_TERMS):
            result.error("`next_action` 缺少回传/证据/测试/review/commit 等闭环词")

    combined = f"{summary}\n{next_action}"
    if msg_type == "blocker" and not re.search(r"卡|阻塞|失败|无法|需要|冲突|缺少|不可用", combined):
        result.error("`blocker` 必须说明具体卡点、已尝试路径或需要谁支持")
    if msg_type == "review_result" and not re.search(r"accepted|changes_requested|blocked|P0|P1|P2|问题|无问题|修复", combined):
        result.error("`review_result` 必须包含明确结论或问题分级")
    if superpowers_message and msg_type == "review_request":
        if not re.search(r"(?i)\bHEAD\b|\bcommit\b|提交", combined):
            result.error("`review_request` 必须包含当前 HEAD 或 commit 证据")
        if not re.search(r"(?i)\btests?\b|测试", combined):
            result.error("`review_request` 必须包含已执行的测试证据")
        if not re.search(r"(?i)self[-_ ]?test|自测", combined):
            result.error("`review_request` 必须包含 owner 自测证据")
    if superpowers_message and msg_type == "review_result":
        if not re.search(r"(?i)\bspec\b|规格", combined):
            result.error("`review_result` 必须包含规格符合性结论")
        if not re.search(r"(?i)code quality|quality|代码质量", combined):
            result.error("`review_result` 必须包含代码质量结论")
    if msg_type == "demo_ready" and not re.search(r"体验|安装|包|路径|设备|验证|已知", combined):
        result.error("`demo_ready` 必须写清体验入口、平台/设备、包路径或已知限制")
    if superpowers_message and status in {"accepted", "merged", "pushed", "verified"} and not re.search(
        r"(?i)证据|tests?|测试|sha|commit|\bHEAD\b|日志|截图|包", combined
    ):
        result.error("完成状态消息必须包含新鲜验证、commit/HEAD、包或日志证据")
    if "完整聊天" in text or "原文如下" in text:
        result.warn("不要把完整聊天原文写入协同账本；只保留摘要和定位信息")
    return result


def parse_request_header(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in text.splitlines():
        match = re.match(r"^([A-Za-z][A-Za-z ]+):\s*(.*)$", line.strip())
        if match:
            fields[match.group(1)] = match.group(2).strip()
    return fields


def request_date_from_name(path: Path) -> str | None:
    match = re.match(r"AM-(\d{8})-", path.stem)
    return match.group(1) if match else None


def is_legacy_request(path: Path, legacy_ok: bool) -> bool:
    request_date = request_date_from_name(path)
    return bool(legacy_ok and request_date and request_date < "20260625")


def validate_request_file(path: Path, *, legacy_ok: bool = False) -> CheckResult:
    result = CheckResult()
    text = path.read_text(encoding="utf-8")
    check_secrets(text, result)
    fields = parse_request_header(text)
    legacy_request = is_legacy_request(path, legacy_ok)
    required = [
        "Status",
        "Owner Lane",
        "Source Thread",
        "Target Version",
        "Base Branch",
        "Work Branch",
        "Merge Branch",
        "Created",
        "Updated",
    ]
    for field_name in required:
        if not fields.get(field_name):
            message = f"{path.name}: 缺少任务单字段 `{field_name}:`"
            if legacy_request:
                result.warn(f"legacy: {message}")
            else:
                result.error(message)

    status = fields.get("Status", "")
    owner = fields.get("Owner Lane", "")
    target_version = fields.get("Target Version", "")
    project_path = fields.get("Project Path", "")
    worktree = fields.get("Worktree Path", "")
    workspace_path = project_path or worktree
    work_branch = fields.get("Work Branch", "")
    created = fields.get("Created", "")

    if created >= WORKFLOW_REQUIRED_FROM:
        workflow_required = [
            "Workflow",
            "Work Type",
            "Risk Level",
            "User Visible",
            "Design Doc",
            "Implementation Plan",
            "Required Skills",
            "TDD Mode",
        ]
        for field_name in workflow_required:
            if not fields.get(field_name):
                result.error(f"{path.name}: 新任务缺少 Superpowers 字段 `{field_name}:`")
        workflow = fields.get("Workflow", "")
        if workflow and workflow != WORKFLOW_NAME:
            result.error(
                f"{path.name}: 2026-07-11 以后新任务必须使用 `Workflow: {WORKFLOW_NAME}`"
            )

    if status and status not in ALLOWED_REQUEST_STATUSES:
        result.error(f"{path.name}: Status 不在允许范围内: {status}")
    if owner and owner not in ALLOWED_LANES:
        owner_parts = [part.strip() for part in owner.split(",") if part.strip()]
        if legacy_request and owner_parts and all(part in ALLOWED_LANES for part in owner_parts):
            result.warn(f"{path.name}: legacy 多 owner 任务单需要迁移为唯一 Owner Lane: {owner}")
        else:
            result.error(f"{path.name}: Owner Lane 不在允许范围内: {owner}")
    if target_version != "process":
        if workspace_path in {"", "none", "pending"}:
            message = f"{path.name}: 业务任务必须写清 Project Path（历史任务可暂用 Worktree Path）"
            if legacy_request:
                result.warn(f"legacy: {message}")
            else:
                result.error(message)
        elif not project_path:
            result.warn(f"{path.name}: 任务单仍使用 Worktree Path；新规则要求改用独立仓库/工程 Project Path")
        elif "/worktrees/" in project_path:
            result.warn(f"{path.name}: Project Path 指向 /worktrees/，新规则要求迁移到独立仓库/工程目录")
        if work_branch in {"", "none", "pending"}:
            message = f"{path.name}: 业务任务必须写清 Work Branch"
            if legacy_request:
                result.warn(f"legacy: {message}")
            else:
                result.error(message)
    if status in {"accepted", "accepted_pending_merge", "pushed"} and "Result: pending" in text:
        result.error(f"{path.name}: 已验收/推送状态不能保留 `Result: pending`")
    if status == "pushed" and "Push Status: pushed" not in text:
        result.warn(f"{path.name}: Status=pushed 但版本区未写 `Push Status: pushed`")
    if status in {"in_progress", "review", "changes_requested", "blocked"}:
        if not re.search(r"next_action|下一步|需要|回传|Review|Verification|消息记录", text, re.IGNORECASE):
            result.warn(f"{path.name}: 活跃任务缺少下一步或回传线索")
    return result


def _project_root_for_request(path: Path) -> Path:
    resolved = path.resolve()
    for parent in resolved.parents:
        if (parent / "docs" / "codex_collab" / "requests").is_dir():
            return parent
    return resolved.parent


def _resolved_doc_path(project_root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    return path if path.is_absolute() else project_root / path


def _is_pending(value: str) -> bool:
    return value.strip().lower() in PENDING_VALUES


def _require_evidence(
    fields: dict[str, str], field_name: str, result: CheckResult
) -> None:
    value = fields.get(field_name, "")
    if _is_pending(value):
        result.error(f"工作流门禁缺少有效 `{field_name}:` 证据")


def _require_commit(
    fields: dict[str, str], field_name: str, result: CheckResult
) -> None:
    value = fields.get(field_name, "")
    if not re.fullmatch(r"[0-9a-fA-F]{7,40}", value):
        result.error(f"工作流门禁要求 `{field_name}:` 为 7-40 位 commit SHA")


def _validate_document(
    project_root: Path,
    fields: dict[str, str],
    field_name: str,
    result: CheckResult,
) -> None:
    value = fields.get(field_name, "")
    if _is_pending(value):
        result.error(f"工作流门禁缺少 `{field_name}:`")
        return
    path = _resolved_doc_path(project_root, value)
    if not path.is_file():
        result.error(f"`{field_name}` 文件不存在: {path}")
        return
    text = path.read_text(encoding="utf-8")
    if PLACEHOLDER_PATTERN.search(text):
        result.error(f"`{field_name}` 仍包含 TODO/TBD/待补等占位内容")


def workflow_gate_for_status(status: str) -> str:
    if status == "proposed":
        return "design"
    if status in {"assigned", "in_progress"}:
        return "start"
    if status in {"self_tested", "review_requested", "review", "changes_requested"}:
        return "review"
    if status in {"accepted", "accepted_pending_merge", "accepted_pending_push"}:
        return "merge"
    if status in {"merged", "pushed", "notified", "verified"}:
        return "close"
    return "design"


def validate_workflow_file(path: Path, *, gate: str) -> CheckResult:
    result = CheckResult()
    if gate not in WORKFLOW_GATES:
        result.error(f"未知工作流门禁 `{gate}`；允许值: {', '.join(WORKFLOW_GATES)}")
        return result

    text = path.read_text(encoding="utf-8")
    check_secrets(text, result)
    fields = parse_request_header(text)
    project_root = _project_root_for_request(path)

    if fields.get("Workflow") != WORKFLOW_NAME:
        result.error(f"工作流门禁要求 `Workflow: {WORKFLOW_NAME}`")

    work_type = fields.get("Work Type", "")
    if work_type not in ALLOWED_WORK_TYPES:
        result.error(f"`Work Type` 不在允许范围内: {work_type}")
    risk_level = fields.get("Risk Level", "")
    if risk_level not in ALLOWED_RISK_LEVELS:
        result.error(f"`Risk Level` 不在允许范围内: {risk_level}")
    if fields.get("User Visible") not in {"yes", "no"}:
        result.error("`User Visible` 必须是 yes 或 no")
    _require_evidence(fields, "Required Skills", result)
    _validate_document(project_root, fields, "Design Doc", result)

    if gate == "design":
        return result

    _validate_document(project_root, fields, "Implementation Plan", result)
    tdd_mode = fields.get("TDD Mode", "")
    if tdd_mode not in ALLOWED_TDD_MODES:
        result.error(f"`TDD Mode` 不在允许范围内: {tdd_mode}")
    if work_type in {"feature", "bugfix", "refactor"} and tdd_mode == "not_applicable":
        result.error(f"{work_type} 不能使用 `TDD Mode: not_applicable`")
    project_path = fields.get("Project Path", "")
    if work_type != "process" and _is_pending(project_path):
        result.error("业务任务必须填写有效 `Project Path`")
    if "/worktrees/" in project_path.replace("\\", "/"):
        result.error("`Project Path` 不得指向 worktree；AI Music 使用独立仓库/工程")
    if project_path and not Path(project_path).expanduser().is_dir():
        result.error(f"`Project Path` 不存在: {project_path}")
    _require_commit(fields, "Baseline Commit", result)

    if gate == "start":
        return result

    _require_commit(fields, "Head Commit", result)
    if work_type == "bugfix":
        _require_evidence(fields, "Root Cause Evidence", result)
    if work_type == "research":
        _require_evidence(fields, "Research Evidence", result)
    if tdd_mode == "required":
        _require_evidence(fields, "Red Evidence", result)
        _require_evidence(fields, "Green Evidence", result)
    elif tdd_mode == "exception":
        _require_evidence(fields, "TDD Exception", result)
        if fields.get("TDD Exception Review") != "accepted":
            result.error("`TDD Exception Review` 必须由 architect 标记为 accepted")
    _require_evidence(fields, "Targeted Tests", result)
    _require_evidence(fields, "Self Test Evidence", result)
    _require_evidence(fields, "Baseline Freshness Evidence", result)
    _require_evidence(fields, "Scope Diff Evidence", result)
    if fields.get("User Visible") == "yes":
        _require_evidence(fields, "Product Main Path Evidence", result)

    if gate == "review":
        return result

    if fields.get("Spec Review Result") != "accepted":
        result.error("`Spec Review Result` 必须是 accepted")
    if fields.get("Code Quality Review Result") != "accepted":
        result.error("`Code Quality Review Result` 必须是 accepted")
    _require_evidence(fields, "Full Verification Evidence", result)
    if fields.get("Blocking Findings", "").strip().lower() not in {"none", "无"}:
        result.error("`Blocking Findings` 必须为 none/无，才能通过 merge gate")

    if gate == "merge":
        return result

    _require_evidence(fields, "Merge Evidence", result)
    _require_evidence(fields, "Push Evidence", result)
    _require_evidence(fields, "Product Notification Evidence", result)
    _require_evidence(fields, "Knowledge Evidence", result)
    return result


def print_result(result: CheckResult, *, as_json: bool = False) -> None:
    if as_json:
        print(json.dumps({"ok": result.ok, "errors": result.errors, "warnings": result.warnings}, ensure_ascii=False, indent=2))
        return
    for warning in result.warnings:
        print(f"WARN: {warning}")
    for error in result.errors:
        print(f"ERROR: {error}")
    if result.ok:
        print("OK")


def command_validate_message(args: argparse.Namespace) -> int:
    if args.file:
        text = Path(args.file).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()
    result = validate_message_text(
        text,
        request_path=Path(args.request_file) if args.request_file else None,
    )
    print_result(result, as_json=args.json)
    return 0 if result.ok and not (args.strict and result.warnings) else 1


def command_validate_request(args: argparse.Namespace) -> int:
    result = validate_request_file(Path(args.file), legacy_ok=args.legacy_ok)
    print_result(result, as_json=args.json)
    return 0 if result.ok and not (args.strict and result.warnings) else 1


def command_validate_workflow(args: argparse.Namespace) -> int:
    result = validate_workflow_file(Path(args.file), gate=args.gate)
    print_result(result, as_json=args.json)
    return 0 if result.ok and not (args.strict and result.warnings) else 1


def command_scan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    requests_dir = root / "docs" / "codex_collab" / "requests"
    result = CheckResult()
    files = sorted(p for p in requests_dir.glob("*.md") if p.name != "README.md")
    if not files:
        result.error(f"没有找到任务单: {requests_dir}")
    for path in files:
        child = validate_request_file(path, legacy_ok=args.legacy_ok)
        result.errors.extend(child.errors)
        result.warnings.extend(child.warnings)
        fields = parse_request_header(path.read_text(encoding="utf-8"))
        if fields.get("Workflow") == WORKFLOW_NAME:
            workflow = validate_workflow_file(
                path,
                gate=workflow_gate_for_status(fields.get("Status", "")),
            )
            result.errors.extend(workflow.errors)
            result.warnings.extend(workflow.warnings)

    if args.json:
        print(json.dumps({"ok": result.ok, "checked": len(files), "errors": result.errors, "warnings": result.warnings}, ensure_ascii=False, indent=2))
    else:
        print(f"Checked request files: {len(files)}")
        print_result(result)
    return 0 if result.ok and not (args.strict and result.warnings) else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="AI Music Codex team operation hard-rule checks")
    subparsers = parser.add_subparsers(dest="command", required=True)

    msg = subparsers.add_parser("validate-message", help="validate a cross-lane message")
    msg.add_argument("--file", help="message text file; stdin is used when omitted")
    msg.add_argument(
        "--request-file",
        help="optional request markdown; enables workflow-specific message gates",
    )
    msg.add_argument("--json", action="store_true", help="emit JSON")
    msg.add_argument("--strict", action="store_true", help="treat warnings as failures")
    msg.set_defaults(func=command_validate_message)

    req = subparsers.add_parser("validate-request", help="validate one request markdown file")
    req.add_argument("file")
    req.add_argument("--json", action="store_true", help="emit JSON")
    req.add_argument("--strict", action="store_true", help="treat warnings as failures")
    req.add_argument("--legacy-ok", action="store_true", help="downgrade pre-2026-06-25 ledger migration debt to warnings")
    req.set_defaults(func=command_validate_request)

    workflow = subparsers.add_parser(
        "validate-workflow",
        help="validate a Superpowers workflow gate for one request",
    )
    workflow.add_argument("file")
    workflow.add_argument("--gate", choices=WORKFLOW_GATES, required=True)
    workflow.add_argument("--json", action="store_true", help="emit JSON")
    workflow.add_argument("--strict", action="store_true", help="treat warnings as failures")
    workflow.set_defaults(func=command_validate_workflow)

    scan = subparsers.add_parser("scan", help="scan all request markdown files")
    scan.add_argument("--root", default=".", help="AI Music project root")
    scan.add_argument("--json", action="store_true", help="emit JSON")
    scan.add_argument("--strict", action="store_true", help="treat warnings as failures")
    scan.add_argument("--legacy-ok", action="store_true", help="downgrade pre-2026-06-25 ledger migration debt to warnings")
    scan.set_defaults(func=command_scan)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
