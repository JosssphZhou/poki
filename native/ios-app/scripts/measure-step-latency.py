#!/usr/bin/env python3
"""Measure Poki iOS chat step latency and per-turn request breakdown on an ephemeral iOS Simulator.

Creates, boots, and deletes its own isolated iOS Simulator so existing simulators' conversations,
memories, and backups are never touched. Drives unmodified Release simulator builds through Poki's
built-in `-pokiInProcess chat` probe against a local OpenAI-compatible scripted model server,
capturing:
- Per-turn HTTP wire bytes and OpenAI o200k_base token counts (via tiktoken when installed).
- Per-source breakdown: base system prompt, reply examples, counted-scroll rules,
  memory-attribution rules, embedded tool instructions, app IDs, saved memories, saved skills,
  tool schemas (total and per-tool including finish_task.card), screen text, mid-task app
  memories, screenshot IDs, and accumulated base64 JPEG screenshots.
- Per-step timing: server-observed step-to-step interval, PokiCore screen read time,
  and per-tool timing from inprocess-probe.json.
- Regression check for ordinary requests containing message-count phrasing without scroll intent.
- SQLite + JSONL output and optional CI/bisect gate thresholds.
"""
import argparse
from contextlib import contextmanager
import json
import os
import plistlib
import re
import shutil
import sqlite3
import statistics
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

try:
    import tiktoken
    ENC = tiktoken.get_encoding("o200k_base")
except Exception:
    ENC = None

TASKS = {
    "settings": "打开设置查看通用里的关于本机",
    "web": "打开 https://example.com/ 查看标题和域名",
    "photos": "打开照片查看最近的照片",
    "false_scroll": "打开设置帮我发一条消息测试",
}

OWNED_SIMULATORS: set[str] = set()
BUILTIN_PROFILES = ("empty", "light", "heavy")


def resolve_developer_dir() -> str:
    env_dir = os.environ.get("DEVELOPER_DIR")
    if env_dir:
        return env_dir
    out = subprocess.check_output(["xcode-select", "-p"], text=True).strip()
    return out


def count_tokens(text: str) -> int:
    if not text:
        return 0
    if ENC is not None:
        return len(ENC.encode(text, disallowed_special=()))
    return max(1, len(text.encode("utf-8")) // 3)


def make_memory_file(profile: str, memory_file: Path | None = None) -> dict:
    if memory_file is not None:
        return json.loads(memory_file.read_text())
    if profile not in BUILTIN_PROFILES:
        raise ValueError(
            f"unknown memory profile {profile!r}; expected one of {', '.join(BUILTIN_PROFILES)} or pass --memory-file"
        )
    now = "2026-11-20T10:00:00Z"
    if profile == "empty":
        return {"schema": "poki.agent-memory/2", "skills": [], "notes": [], "runs": []}
    if profile == "light":
        return {
            "schema": "poki.agent-memory/2",
            "skills": [
                {
                    "name": "查看系统版本",
                    "description": "打开设置进入通用查看关于本机里的系统版本。",
                    "app": "com.apple.Preferences",
                    "steps": [{"action": {"launch": "com.apple.Preferences"}, "app": "com.apple.Preferences"}],
                    "params": {},
                    "expect": [],
                    "read": [],
                    "runs": 1,
                    "ok": 1,
                    "failuresInARow": 0,
                    "savedBy": "owner",
                    "created": now,
                    "updated": now,
                }
            ],
            "notes": [
                {
                    "id": "mem00001",
                    "text": "查看网页时同时报出标题和当前域名。",
                    "by": "owner",
                    "at": now,
                }
            ],
            "runs": [],
        }
    notes = [
        {"id": "n0000001", "text": "回复尽量简短直接，先给结论再给细节。", "by": "owner", "at": now},
        {"id": "n0000002", "text": "查火车票默认优先看二等座和直达车次。", "by": "owner", "at": now},
        {"id": "n0000003", "text": "公司差旅群名字叫「项目差旅通知群」。", "by": "owner", "at": now},
        {"id": "n0000004", "text": "发微信给家人时语气自然，不用书面敬语。", "by": "owner", "at": now},
        {"id": "n0000005", "text": "外卖默认不要香菜和葱花，微辣。", "by": "owner", "at": now},
        {"id": "n0000006", "text": "酒店优先选地铁步行五分钟内且含双早的房型。", "by": "owner", "at": now},
        {"id": "n0000007", "text": "查看网页时同时报出标题和当前域名。", "by": "owner", "at": now},
        {"id": "n0000008", "text": "在设置里检查网络时先确认无线局域网名称和代理状态。", "by": "owner", "at": now, "app": "com.apple.Preferences"},
        {"id": "n0000009", "text": "在设置里查看关于本机时顺带记录系统版本号和容量。", "by": "owner", "at": now, "app": "com.apple.Preferences"},
        {"id": "n0000010", "text": "不要关闭设置里的深色外观和自动亮度开关。", "by": "owner", "at": now, "app": "com.apple.Preferences"},
        {"id": "n0000011", "text": "在设置通用页面核对设备名称后再汇报。", "by": "owner", "at": now, "app": "com.apple.Preferences"},
        {"id": "n0000012", "text": "在照片里找截图优先去最近项目相簿顶部。", "by": "owner", "at": now, "app": "com.apple.mobileslideshow"},
        {"id": "n0000013", "text": "照片里不要主动删除任何截图或发票图片。", "by": "owner", "at": now, "app": "com.apple.mobileslideshow"},
        {"id": "n0000014", "text": "照片分享前先确认不是包含隐私地址的原图。", "by": "owner", "at": now, "app": "com.apple.mobileslideshow"},
        {"id": "n0000015", "text": "在照片里查最近一张图时顺便看拍摄时间。", "by": "owner", "at": now, "app": "com.apple.mobileslideshow"},
    ]

    def mk_skill(name, desc, stored_app, launch_app):
        return {
            "name": name,
            "description": desc,
            "app": stored_app,
            "steps": [
                {"action": {"button": "home"}, "app": "nz.zheha.poki"},
                {"action": {"launch": launch_app}, "app": "com.apple.springboard"},
                {"action": {"tap": "@"}, "target": {"type": "StaticText", "label": "General", "x": 200, "y": 300}, "app": launch_app},
            ],
            "params": {},
            "expect": [],
            "read": [],
            "runs": 2,
            "ok": 2,
            "failuresInARow": 0,
            "savedBy": "owner",
            "created": now,
            "updated": now,
        }

    skills = [
        mk_skill("查看关于本机", "打开设置进入通用查看关于本机的名称与系统版本信息。", "com.apple.Preferences", "com.apple.Preferences"),
        mk_skill("检查设置存储空间", "打开设置进入通用查看 iPhone 储存空间占用详情。", "com.apple.Preferences", "com.apple.Preferences"),
        mk_skill("开关设置无线局域网", "进入设置无线局域网页面查看当前连接的网络。", "com.apple.springboard", "com.apple.Preferences"),
        mk_skill("检查设置蓝牙设备", "打开设置蓝牙列表检查已连接的耳机与外设。", "com.apple.springboard", "com.apple.Preferences"),
        mk_skill("查看设置电池健康", "进入设置电池页面查看电池最大容量和充电上限。", "com.apple.springboard", "com.apple.Preferences"),
        mk_skill("检查设置日期与时间", "进入设置通用日期与时间确认自动设置状态。", "com.apple.springboard", "com.apple.Preferences"),
        mk_skill("查看最近照片", "打开照片应用进入最近项目查看最新保存的照片。", "com.apple.mobileslideshow", "com.apple.mobileslideshow"),
        mk_skill("查找照片里的截图", "在照片应用里打开截屏相簿定位最新屏幕截图。", "com.apple.mobileslideshow", "com.apple.mobileslideshow"),
        mk_skill("打开照片收藏相簿", "进入照片应用个人收藏查看标星图片。", "com.apple.springboard", "com.apple.mobileslideshow"),
        mk_skill("检查照片最近删除", "进入照片应用更多项目检查最近删除相簿数量。", "com.apple.springboard", "com.apple.mobileslideshow"),
        mk_skill("查询12306高铁票", "打开铁路12306查询指定日期和城市的高铁余票。", "cn.12306.rails12306", "cn.12306.rails12306"),
        mk_skill("携程搜索酒店", "打开携程旅行按城市和入住日期筛选高评分酒店。", "ctrip.com", "ctrip.com"),
        mk_skill("淘宝查看物流", "打开淘宝我的订单查看最近包裹物流状态。", "com.taobao.taobao4iphone", "com.taobao.taobao4iphone"),
        mk_skill("点评搜索附近餐厅", "打开大众点评按好评排序查找附近餐厅。", "com.dianping.dpscope", "com.dianping.dpscope"),
        mk_skill("备忘录新建清单", "打开备忘录新建一条待办事项并保存。", "com.apple.mobilenotes", "com.apple.mobilenotes"),
    ]
    return {"schema": "poki.agent-memory/2", "skills": skills, "notes": notes, "runs": []}


def split_system_prompt(text: str) -> dict:
    sections = {
        "reply_examples": "",
        "counted_scroll": "",
        "memory_attribution": "",
        "embedded_tool_instructions": "",
        "app_ids": "",
        "memories": "",
        "skills": "",
    }
    paras = text.split("\n\n")
    other = []
    in_reply_examples = False
    for p in paras:
        ps = p.strip()
        if ps == "## Reply examples":
            in_reply_examples = True
            sections["reply_examples"] += ("\n\n" if sections["reply_examples"] else "") + p
            continue
        if in_reply_examples:
            if (
                ps.startswith("For a request measured in pages or screens,")
                or ps.startswith("look reads the iPhone's screen;")
                or ps.startswith("Poki has its own browser")
                or ps.startswith("To continue or resume,")
            ):
                in_reply_examples = False
            else:
                sections["reply_examples"] += "\n\n" + p
                continue
        if ps.startswith("For a request measured in pages or screens,") or "Use count_messages only for requests measured in individual messages." in ps:
            sections["counted_scroll"] += ("\n\n" if sections["counted_scroll"] else "") + p
        elif ps.startswith("When a saved memory changes an action in do,") or ps.startswith("A skill or memory you ask to save is kept only after"):
            sections["memory_attribution"] += ("\n\n" if sections["memory_attribution"] else "") + p
        elif ps.startswith("Use these iPhone bundle ids for apps named in this request:"):
            sections["app_ids"] += ("\n\n" if sections["app_ids"] else "") + p
        elif ps.startswith("Saved memories, newest first.") or ps.startswith("Notes saved about the owner") or ps.startswith("Saved skills:"):
            lines = p.split("\n")
            cur = None
            mem_lines, skill_lines = [], []
            for line in lines:
                if line.startswith("Saved skills:"):
                    cur = "skills"
                elif line.startswith("Saved memories, newest first.") or line.startswith("Notes saved about the owner"):
                    cur = "memories"
                if cur == "skills":
                    skill_lines.append(line)
                else:
                    mem_lines.append(line)
            if mem_lines:
                sections["memories"] += ("\n" if sections["memories"] else "") + "\n".join(mem_lines)
            if skill_lines:
                sections["skills"] += ("\n" if sections["skills"] else "") + "\n".join(skill_lines)
        elif (
            ps.startswith("look reads the iPhone's screen;")
            or ps.startswith("Poki has its own browser for websites")
            or ("Screen History" in ps and "screen_history" in ps)
        ):
            sections["embedded_tool_instructions"] += ("\n\n" if sections["embedded_tool_instructions"] else "") + p
        else:
            other.append(p)
    sections["base_system"] = "\n\n".join(other)
    return sections


def analyze_request(raw_bytes: bytes, body: dict) -> dict:
    messages = body.get("messages", [])
    tools = body.get("tools", [])
    sys_texts = []
    for m in messages:
        if m.get("role") in ("system", "developer"):
            c = m.get("content", "")
            if isinstance(c, str):
                sys_texts.append(c)
            elif isinstance(c, list):
                sys_texts.extend(p.get("text", "") for p in c if isinstance(p, dict) and p.get("type") == "text")
    sys_full = "\n\n".join(sys_texts)
    sec = split_system_prompt(sys_full)

    tools_json = json.dumps(tools, ensure_ascii=False, separators=(",", ":"))
    per_tool_bytes = {}
    per_tool_tokens = {}
    card_bytes = 0
    card_tokens = 0
    for t in tools:
        fn = t.get("function", t)
        name = fn.get("name", "?")
        s = json.dumps(t, ensure_ascii=False, separators=(",", ":"))
        per_tool_bytes[name] = len(s.encode("utf-8"))
        per_tool_tokens[name] = count_tokens(s)
        if name == "finish_task":
            card = fn.get("parameters", {}).get("properties", {}).get("card")
            if card is not None:
                cs = json.dumps(card, ensure_ascii=False, separators=(",", ":"))
                card_bytes = len(cs.encode("utf-8"))
                card_tokens = count_tokens(cs)

    screen_text = []
    app_mem_brief = []
    screenshot_id_lines = []
    other_msg_text = []
    image_count = 0
    image_b64_bytes = 0

    call_names = {}
    for m in messages:
        role = m.get("role")
        if role == "assistant":
            if isinstance(m.get("content"), str):
                other_msg_text.append(m["content"])
            for tc in m.get("tool_calls") or []:
                fn = tc.get("function") or {}
                call_names[tc.get("id", "")] = fn.get("name", "")
                other_msg_text.append(fn.get("name", "") + " " + (fn.get("arguments") or ""))
        elif role == "user":
            c = m.get("content")
            if isinstance(c, str):
                other_msg_text.append(c)
            elif isinstance(c, list):
                for p in c:
                    if isinstance(p, dict):
                        if p.get("type") == "text":
                            other_msg_text.append(p.get("text", ""))
                        elif p.get("type") == "image_url":
                            url = (p.get("image_url") or {}).get("url", "")
                            image_count += 1
                            image_b64_bytes += len(url.encode("utf-8"))
        elif role == "tool":
            tname = call_names.get(m.get("tool_call_id", ""), "")
            c = m.get("content")
            texts = []
            if isinstance(c, str):
                texts.append(c)
            elif isinstance(c, list):
                for p in c:
                    if isinstance(p, dict):
                        if p.get("type") == "text":
                            texts.append(p.get("text", ""))
                        elif p.get("type") == "image_url":
                            url = (p.get("image_url") or {}).get("url", "")
                            image_count += 1
                            image_b64_bytes += len(url.encode("utf-8"))
            joined = "\n".join(texts)
            if tname in ("look", "do", "web_open", "web_read", "web_click", "web_type"):
                lines = joined.splitlines()
                scr_lines = []
                in_app_mem = False
                for line in lines:
                    if line.startswith("Saved memories for this app."):
                        in_app_mem = True
                        app_mem_brief.append(line)
                    elif in_app_mem and line.startswith("- ["):
                        app_mem_brief.append(line)
                    elif line.startswith("screenshot_id: "):
                        in_app_mem = False
                        screenshot_id_lines.append(line)
                    else:
                        in_app_mem = False
                        scr_lines.append(line)
                screen_text.append("\n".join(scr_lines))
            else:
                other_msg_text.append(joined)

    screen_joined = "\n".join(screen_text)
    app_mem_joined = "\n".join(app_mem_brief)
    shot_id_joined = "\n".join(screenshot_id_lines)
    other_joined = "\n".join(other_msg_text)

    non_image_text = sys_full + "\n" + tools_json + "\n" + screen_joined + "\n" + app_mem_joined + "\n" + shot_id_joined + "\n" + other_joined
    return {
        "wire_bytes": len(raw_bytes),
        "text_tokens_total": count_tokens(non_image_text),
        "system_total_bytes": len(sys_full.encode("utf-8")),
        "system_total_tokens": count_tokens(sys_full),
        "base_system_bytes": len(sec["base_system"].encode("utf-8")),
        "base_system_tokens": count_tokens(sec["base_system"]),
        "reply_examples_bytes": len(sec["reply_examples"].encode("utf-8")),
        "reply_examples_tokens": count_tokens(sec["reply_examples"]),
        "counted_scroll_bytes": len(sec["counted_scroll"].encode("utf-8")),
        "counted_scroll_tokens": count_tokens(sec["counted_scroll"]),
        "memory_attr_bytes": len(sec["memory_attribution"].encode("utf-8")),
        "memory_attr_tokens": count_tokens(sec["memory_attribution"]),
        "embedded_tool_prose_bytes": len(sec["embedded_tool_instructions"].encode("utf-8")),
        "embedded_tool_prose_tokens": count_tokens(sec["embedded_tool_instructions"]),
        "app_ids_bytes": len(sec["app_ids"].encode("utf-8")),
        "app_ids_tokens": count_tokens(sec["app_ids"]),
        "memories_bytes": len(sec["memories"].encode("utf-8")),
        "memories_tokens": count_tokens(sec["memories"]),
        "skills_bytes": len(sec["skills"].encode("utf-8")),
        "skills_tokens": count_tokens(sec["skills"]),
        "tools_total_bytes": len(tools_json.encode("utf-8")),
        "tools_total_tokens": count_tokens(tools_json),
        "finish_task_bytes": per_tool_bytes.get("finish_task", 0),
        "finish_task_tokens": per_tool_tokens.get("finish_task", 0),
        "finish_task_card_bytes": card_bytes,
        "finish_task_card_tokens": card_tokens,
        "do_tool_bytes": per_tool_bytes.get("do", 0),
        "do_tool_tokens": per_tool_tokens.get("do", 0),
        "skills_tool_bytes": per_tool_bytes.get("skills", 0),
        "count_messages_bytes": per_tool_bytes.get("count_messages", 0) + per_tool_bytes.get("wait_for_counted_scroll_reply", 0),
        "count_messages_tokens": per_tool_tokens.get("count_messages", 0) + per_tool_tokens.get("wait_for_counted_scroll_reply", 0),
        "per_tool_bytes": per_tool_bytes,
        "screen_text_bytes": len(screen_joined.encode("utf-8")),
        "screen_text_tokens": count_tokens(screen_joined),
        "app_memory_brief_bytes": len(app_mem_joined.encode("utf-8")),
        "app_memory_brief_tokens": count_tokens(app_mem_joined),
        "screenshot_id_bytes": len(shot_id_joined.encode("utf-8")),
        "screen_image_count": image_count,
        "screen_image_b64_bytes": image_b64_bytes,
    }


def tool_text(msg: dict) -> str:
    c = msg.get("content", "")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(p.get("text", "") for p in c if isinstance(p, dict) and p.get("type") == "text")
    return ""


def decide_action(task_name: str, turn_idx: int, tool_msgs: list, state: dict):
    if task_name == "settings":
        if turn_idx == 0:
            return "report_plan", {"steps": ["打开设置", "进入通用", "查看关于本机"], "currentStep": 1, "title": "查看关于本机"}
        if turn_idx == 1:
            return "do", {"actions": [{"launch": "com.apple.Preferences"}]}
        if turn_idx == 2:
            last = tool_text(tool_msgs[-1])
            state["saw_settings"] = "com.apple.Preferences" in last or "Settings" in last or "设置" in last
            m = re.search(r'(?m)^[ +~]*([0-9]+)\s+\S+\s+"(?:General|通用)"', last)
            if m:
                return "do", {"actions": [{"tap": int(m.group(1))}]}
            return "look", {}
        if turn_idx == 3:
            last = tool_text(tool_msgs[-1])
            state["saw_general"] = any(k in last for k in ("About", "关于本机", "General", "通用"))
            return "look", {}
        if turn_idx == 4:
            return "finish_task", {
                "success": True,
                "summary": "已打开设置并查看通用页面。",
                "details": [{"label": "App", "value": "Settings"}],
                "answer": {"kind": "action"},
            }
        return None, "已打开设置并核对通用页面。"

    if task_name == "web":
        if turn_idx == 0:
            return "report_plan", {"steps": ["打开网页", "读取标题与域名"], "currentStep": 1, "title": "查看网页"}
        if turn_idx == 1:
            return "web_open", {"url": "https://example.com/"}
        if turn_idx == 2:
            return "web_read", {"find": "Example Domain"}
        if turn_idx == 3:
            last = tool_text(tool_msgs[-1])
            state["saw_example"] = "Example Domain" in last and "example.com" in last
            return "finish_task", {
                "success": True,
                "summary": "标题是 Example Domain，域名是 example.com。",
                "details": [{"label": "标题", "value": "Example Domain"}, {"label": "域名", "value": "example.com"}],
                "answer": {"kind": "field", "items": []},
            }
        return None, "已核实 example.com，标题为 Example Domain。"

    if task_name == "photos":
        if turn_idx == 0:
            return "report_plan", {"steps": ["打开照片", "查看并滑动列表"], "currentStep": 1, "title": "查看照片"}
        if turn_idx == 1:
            return "do", {"actions": [{"launch": "com.apple.mobileslideshow"}]}
        if turn_idx == 2:
            last = tool_text(tool_msgs[-1])
            state["saw_photos"] = "com.apple.mobileslideshow" in last or "Photos" in last or "照片" in last
            return "look", {}
        if turn_idx == 3:
            return "do", {"actions": [{"swipe": "up"}]}
        if turn_idx == 4:
            return "finish_task", {
                "success": True,
                "summary": "已打开照片并查看最近照片。",
                "details": [{"label": "App", "value": "Photos"}],
                "answer": {"kind": "action"},
            }
        return None, "已打开照片并浏览最近的照片。"

    if task_name == "false_scroll":
        if turn_idx == 0:
            return "report_plan", {"steps": ["打开设置", "完成测试"], "currentStep": 1, "title": "发一条消息测试"}
        if turn_idx == 1:
            return "do", {"actions": [{"launch": "com.apple.Preferences"}]}
        if turn_idx == 2:
            return "finish_task", {
                "success": True,
                "summary": "测试完成。",
                "details": [{"label": "App", "value": "Settings"}],
                "answer": {"kind": "action"},
            }
        if turn_idx == 3:
            last = tool_text(tool_msgs[-1])
            state["finish_task_answer"] = last
            state["finish_task_rejected"] = "older messages" in last or "Confirmed 0 of" in last or "较早的消息" in last
            return None, "测试完成。"
        return None, "测试完成。"

    raise ValueError(f"unknown task {task_name}")


class ScriptedHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def reply_json(self, value, status=200):
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def stream(self, model, message, finish, usage):
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("cache-control", "no-cache")
        self.end_headers()
        base = {"id": "chatcmpl-perf", "object": "chat.completion.chunk", "created": int(time.time()), "model": model}

        def send(chunk):
            self.wfile.write(b"data: " + json.dumps({**base, **chunk}, ensure_ascii=False).encode("utf-8") + b"\n\n")
            self.wfile.flush()

        delta = {"role": "assistant"}
        if message.get("tool_calls"):
            delta["tool_calls"] = message["tool_calls"]
        else:
            delta["content"] = message["content"]
        send({"choices": [{"index": 0, "delta": delta, "finish_reason": None}]})
        send({"choices": [{"index": 0, "delta": {}, "finish_reason": finish}]})
        send({"choices": [], "usage": usage})
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self.reply_json({"object": "list", "data": [{"id": "poki-perf-mock", "object": "model"}]})
        else:
            self.reply_json({"ok": True})

    def do_POST(self):
        t_recv = time.monotonic()
        state = self.server.state
        parts = self.path.strip("/").split("/")
        if not parts or parts[0] != state["run_id"] or state["done"].is_set():
            self.send_error(410)
            return
        length = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        body = json.loads(raw)
        if not body.get("tools"):
            model = body.get("model") or "poki-perf-mock"
            msg = {"role": "assistant", "content": "NORMAL"}
            usage = {"prompt_tokens": 50, "completion_tokens": 5, "total_tokens": 55}
            if body.get("stream"):
                self.stream(model, msg, "stop", usage)
            else:
                self.reply_json({
                    "id": "chatcmpl-helper",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": model,
                    "choices": [{"index": 0, "message": msg, "finish_reason": "stop"}],
                    "usage": usage,
                })
            return
        messages = body.get("messages", [])
        tool_msgs = [m for m in messages if m.get("role") == "tool"]
        turn_idx = len(tool_msgs)
        stats = analyze_request(raw, body)

        prev_sent = state.get("last_response_sent")
        step_interval_ms = (t_recv - prev_sent) * 1000.0 if prev_sent is not None else None

        if state.get("save_first_request") and turn_idx >= 1:
            (state["run_dir"] / f"turn{turn_idx}_request.json").write_bytes(raw)

        tool_name, payload = decide_action(state["task"], turn_idx, tool_msgs, state)
        model = body.get("model") or "poki-perf-mock"
        if tool_name:
            call = {
                "index": 0,
                "id": f"call_{state['run_id']}_{turn_idx}",
                "type": "function",
                "function": {"name": tool_name, "arguments": json.dumps(payload, ensure_ascii=False)},
            }
            message = {"role": "assistant", "content": None, "tool_calls": [call]}
            finish = "tool_calls"
        else:
            message = {"role": "assistant", "content": payload}
            finish = "stop"
        usage = {"prompt_tokens": stats["text_tokens_total"], "completion_tokens": 20, "total_tokens": stats["text_tokens_total"] + 20}
        if body.get("stream"):
            self.stream(model, message, finish, usage)
        else:
            self.reply_json({
                "id": "chatcmpl-perf",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [{"index": 0, "message": message, "finish_reason": finish}],
                "usage": usage,
            })
        t_sent = time.monotonic()
        state["last_response_sent"] = t_sent
        state["turns"].append({
            "turn": turn_idx,
            "t_recv": t_recv,
            "t_sent": t_sent,
            "model_ms": (t_sent - t_recv) * 1000.0,
            "step_interval_ms": step_interval_ms,
            "response_tool": tool_name or "final_text",
            **stats,
        })
        if finish == "stop":
            state["done"].set()


def sim(*args, env=None, timeout=30, check=True):
    res = subprocess.run(["xcrun", "simctl", *args], text=True, capture_output=True, env=env, timeout=timeout)
    if check and res.returncode != 0:
        raise RuntimeError(f"simctl {' '.join(args)} failed ({res.returncode}): {res.stderr.strip()} {res.stdout.strip()}")
    return res.stdout


def resolve_simulator_spec(device_type: str | None = None, runtime: str | None = None) -> tuple[str, str]:
    if device_type is None:
        dev_list = json.loads(sim("list", "-j", "devicetypes")).get("devicetypes", [])
        iphones = [d["identifier"] for d in dev_list if "iPhone" in d.get("name", "") and d.get("identifier")]
        if not iphones:
            raise RuntimeError("no iPhone simulator device type available")
        preferred = [d for d in iphones if "iPhone-17" in d]
        device_type = preferred[0] if preferred else iphones[-1]
    if runtime is None:
        rt_list = json.loads(sim("list", "-j", "runtimes")).get("runtimes", [])
        ios_runtimes = [
            r for r in rt_list
            if r.get("isAvailable") and str(r.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
        ]
        if not ios_runtimes:
            raise RuntimeError("no available iOS simulator runtime found")
        ios_runtimes.sort(key=lambda r: tuple(int(p) for p in re.findall(r"\d+", str(r.get("version", ""))) or [0]))
        runtime = ios_runtimes[-1]["identifier"]
    return device_type, runtime


@contextmanager
def ephemeral_simulator(device_type: str | None = None, runtime: str | None = None):
    resolved_device, resolved_runtime = resolve_simulator_spec(device_type, runtime)
    name = f"Poki-Step-Latency-{os.getpid()}-{int(time.time())}"
    udid = sim("create", name, resolved_device, resolved_runtime, timeout=60).strip()
    if not udid:
        raise RuntimeError("simctl create returned empty UDID")
    OWNED_SIMULATORS.add(udid)
    try:
        sim("boot", udid, timeout=60)
        sim("bootstatus", udid, "-b", timeout=180)
        yield udid
    finally:
        OWNED_SIMULATORS.discard(udid)
        sim("shutdown", udid, check=False, timeout=30)
        sim("delete", udid, check=False, timeout=60)


def init_db(db_path: Path):
    conn = sqlite3.connect(db_path)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS runs (
            run_id TEXT PRIMARY KEY,
            label TEXT,
            commit_sha TEXT,
            task TEXT,
            profile TEXT,
            round_idx INTEGER,
            ok INTEGER,
            error TEXT,
            task_total_ms REAL,
            step_interval_median_ms REAL,
            step_interval_min_ms REAL,
            step_interval_max_ms REAL,
            tool_ms_median REAL,
            client_overhead_median_ms REAL,
            wire_bytes_median REAL,
            tokens_median REAL,
            system_bytes INTEGER,
            base_system_bytes INTEGER,
            reply_examples_bytes INTEGER,
            counted_scroll_bytes INTEGER,
            memory_attr_bytes INTEGER,
            embedded_tool_prose_bytes INTEGER,
            memories_bytes INTEGER,
            skills_bytes INTEGER,
            tools_bytes INTEGER,
            finish_task_bytes INTEGER,
            finish_task_card_bytes INTEGER,
            count_messages_bytes INTEGER,
            app_memory_brief_max_bytes INTEGER,
            screen_text_max_bytes INTEGER,
            screen_image_max_count INTEGER,
            screen_image_max_b64_bytes INTEGER,
            finish_task_rejected INTEGER
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS turns (
            run_id TEXT,
            turn INTEGER,
            response_tool TEXT,
            step_interval_ms REAL,
            model_ms REAL,
            wire_bytes INTEGER,
            text_tokens_total INTEGER,
            system_total_bytes INTEGER,
            base_system_bytes INTEGER,
            counted_scroll_bytes INTEGER,
            memory_attr_bytes INTEGER,
            embedded_tool_prose_bytes INTEGER,
            memories_bytes INTEGER,
            skills_bytes INTEGER,
            tools_total_bytes INTEGER,
            finish_task_bytes INTEGER,
            finish_task_card_bytes INTEGER,
            count_messages_bytes INTEGER,
            screen_text_bytes INTEGER,
            app_memory_brief_bytes INTEGER,
            screenshot_id_bytes INTEGER,
            screen_image_count INTEGER,
            screen_image_b64_bytes INTEGER,
            PRIMARY KEY (run_id, turn)
        )
    """)
    conn.commit()
    return conn


def run_one(server, udid: str, app_path: Path, label: str, commit_sha: str, task_name: str, profile: str, round_idx: int, out_dir: Path, developer_dir: str, memory_file: Path | None = None, save_payload: bool = False):
    if udid not in OWNED_SIMULATORS:
        raise ValueError(
            f"refusing to run against simulator {udid!r} not created by ephemeral_simulator"
        )
    memory_payload = make_memory_file(profile, memory_file)
    info = plistlib.loads((app_path / "Info.plist").read_bytes())
    bid = info["CFBundleIdentifier"]
    run_id = f"r{round_idx:02d}_{label}_{task_name}_{profile}_{int(time.time() * 1000) % 100000}"
    run_dir = out_dir / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    sim("terminate", udid, bid, check=False)
    sim("terminate", udid, "com.apple.Preferences", check=False)
    sim("terminate", udid, "com.apple.mobileslideshow", check=False)
    sim("install", udid, str(app_path), timeout=60)
    data_dir = Path(sim("get_app_container", udid, bid, "data").strip())

    mem_dir = data_dir / "Library/Application Support/Poki"
    mem_dir.mkdir(parents=True, exist_ok=True)
    (mem_dir / "agent-memory.json").write_text(json.dumps(memory_payload, ensure_ascii=False))
    backup_dir = data_dir / "Documents/AgentBackup"
    if backup_dir.exists():
        shutil.rmtree(backup_dir, ignore_errors=True)
    sessions_dir = data_dir / "Library/Application Support/Poki/Sessions"
    if sessions_dir.exists():
        shutil.rmtree(sessions_dir, ignore_errors=True)
    probe_file = data_dir / "Documents/inprocess-probe.json"
    probe_file.unlink(missing_ok=True)
    poki_log = data_dir / "Library/Caches/poki-log.txt"
    log_offset = poki_log.stat().st_size if poki_log.exists() else 0

    state = {
        "run_id": run_id,
        "run_dir": run_dir,
        "task": task_name,
        "turns": [],
        "done": threading.Event(),
        "save_first_request": save_payload,
    }
    server.state = state

    xcode_sim = Path(developer_dir) / "Platforms/iPhoneSimulator.platform/Developer"
    env = dict(
        os.environ,
        SIMCTL_CHILD_POKI_SIMULATOR_DEVELOPER_DIR=str(xcode_sim),
        SIMCTL_CHILD_DYLD_FRAMEWORK_PATH=f"{xcode_sim}/Library/Frameworks:{xcode_sim}/Library/PrivateFrameworks",
        SIMCTL_CHILD_DYLD_LIBRARY_PATH=f"{xcode_sim}/usr/lib",
    )

    error = None
    try:
        sim(
            "launch", "--terminate-running-process", udid, bid,
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-pokiInProcess", "chat",
            "-pokiProbeModelURL", f"http://127.0.0.1:{server.server_port}/{run_id}/v1",
            "-pokiProbeModel", "poki-perf-mock",
            "-pokiProbeTask", TASKS[task_name],
            env=env,
            timeout=30,
        )
        if not state["done"].wait(60):
            error = "timeout waiting for final model response"
            state["done"].set()
        else:
            time.sleep(0.5)
    except Exception as exc:
        error = str(exc)
    finally:
        sim("terminate", udid, bid, check=False)

    log_tail = ""
    if poki_log.exists():
        with poki_log.open("rb") as f:
            f.seek(min(log_offset, poki_log.stat().st_size))
            log_tail = f.read().decode("utf-8", errors="replace")
        (run_dir / "poki-log-slice.txt").write_text(log_tail)

    probe_calls = []
    task_total_ms = None
    if probe_file.exists():
        try:
            probe_data = json.loads(probe_file.read_text())
            (run_dir / "inprocess-probe.json").write_text(json.dumps(probe_data, ensure_ascii=False, indent=2))
            for item in probe_data:
                if item.get("step") == "chat":
                    task_total_ms = (item.get("seconds") or 0) * 1000.0
                    probe_calls = item.get("calls") or []
        except Exception:
            pass

    turns = state["turns"]
    chat_timing_lines = [l for l in log_tail.splitlines() if "[chat-timing]" in l]
    if chat_timing_lines:
        (run_dir / "chat-timing.txt").write_text("\n".join(chat_timing_lines) + "\n")
    read_ms_list = [int(m.group(1)) for m in re.finditer(r'\[agent\] done: .*?read: \S+ \((\d+) ms\)', log_tail)]
    m_task_s = re.search(r'\[chat\] task ended: .*?after ([0-9.]+) s', log_tail)
    if task_total_ms is None and m_task_s:
        task_total_ms = float(m_task_s.group(1)) * 1000.0

    if error is None:
        if len(turns) < 4:
            error = f"too few turns: {len(turns)}"
        elif task_name == "settings" and not state.get("saw_settings"):
            error = "settings app never observed in screen read"
        elif task_name == "web" and not state.get("saw_example"):
            error = "example.com content never verified in web_read"
        elif task_name == "photos" and not state.get("saw_photos"):
            error = "photos app never observed in screen read"

    intervals = [t["step_interval_ms"] for t in turns if t["step_interval_ms"] is not None]
    tool_ms_list = [c.get("ms", 0) for c in probe_calls if isinstance(c, dict)]
    if task_total_ms is None and len(turns) >= 2:
        task_total_ms = (turns[-1]["t_sent"] - turns[0]["t_recv"]) * 1000.0

    overheads = []
    if len(tool_ms_list) == len(intervals):
        overheads = [iv - tm for iv, tm in zip(intervals, tool_ms_list)]

    first = turns[0] if turns else {}
    row = {
        "run_id": run_id,
        "label": label,
        "commit_sha": commit_sha,
        "task": task_name,
        "profile": profile,
        "round_idx": round_idx,
        "ok": 1 if error is None else 0,
        "error": error or "",
        "task_total_ms": task_total_ms,
        "step_interval_median_ms": statistics.median(intervals) if intervals else None,
        "step_interval_min_ms": min(intervals) if intervals else None,
        "step_interval_max_ms": max(intervals) if intervals else None,
        "tool_ms_median": statistics.median(read_ms_list) if read_ms_list else (statistics.median(tool_ms_list) if tool_ms_list else None),
        "read_ms_list": read_ms_list,
        "client_overhead_median_ms": statistics.median(overheads) if overheads else None,
        "wire_bytes_median": statistics.median([t["wire_bytes"] for t in turns]) if turns else None,
        "tokens_median": statistics.median([t["text_tokens_total"] for t in turns]) if turns else None,
        "system_bytes": first.get("system_total_bytes", 0),
        "base_system_bytes": first.get("base_system_bytes", 0),
        "reply_examples_bytes": first.get("reply_examples_bytes", 0),
        "counted_scroll_bytes": first.get("counted_scroll_bytes", 0),
        "memory_attr_bytes": first.get("memory_attr_bytes", 0),
        "embedded_tool_prose_bytes": first.get("embedded_tool_prose_bytes", 0),
        "memories_bytes": first.get("memories_bytes", 0),
        "skills_bytes": first.get("skills_bytes", 0),
        "tools_bytes": first.get("tools_total_bytes", 0),
        "finish_task_bytes": first.get("finish_task_bytes", 0),
        "finish_task_card_bytes": first.get("finish_task_card_bytes", 0),
        "count_messages_bytes": first.get("count_messages_bytes", 0),
        "app_memory_brief_max_bytes": max((t["app_memory_brief_bytes"] for t in turns), default=0),
        "screen_text_max_bytes": max((t["screen_text_bytes"] for t in turns), default=0),
        "screen_image_max_count": max((t["screen_image_count"] for t in turns), default=0),
        "screen_image_max_b64_bytes": max((t["screen_image_b64_bytes"] for t in turns), default=0),
        "finish_task_rejected": 1 if state.get("finish_task_rejected") else 0,
        "turns": turns,
        "probe_calls": probe_calls,
        "finish_task_answer": state.get("finish_task_answer", ""),
    }
    (run_dir / "summary.json").write_text(json.dumps(row, ensure_ascii=False, indent=2))
    return row


def save_row(conn: sqlite3.Connection, row: dict):
    cols = [
        "run_id", "label", "commit_sha", "task", "profile", "round_idx", "ok", "error",
        "task_total_ms", "step_interval_median_ms", "step_interval_min_ms", "step_interval_max_ms",
        "tool_ms_median", "client_overhead_median_ms", "wire_bytes_median", "tokens_median",
        "system_bytes", "base_system_bytes", "reply_examples_bytes", "counted_scroll_bytes", "memory_attr_bytes",
        "embedded_tool_prose_bytes", "memories_bytes", "skills_bytes", "tools_bytes",
        "finish_task_bytes", "finish_task_card_bytes", "count_messages_bytes",
        "app_memory_brief_max_bytes", "screen_text_max_bytes", "screen_image_max_count",
        "screen_image_max_b64_bytes", "finish_task_rejected",
    ]
    conn.execute(
        f"INSERT OR REPLACE INTO runs ({','.join(cols)}) VALUES ({','.join('?' for _ in cols)})",
        [row[c] for c in cols],
    )
    tcols = [
        "turn", "response_tool", "step_interval_ms", "model_ms", "wire_bytes", "text_tokens_total",
        "system_total_bytes", "base_system_bytes", "counted_scroll_bytes", "memory_attr_bytes",
        "embedded_tool_prose_bytes", "memories_bytes", "skills_bytes", "tools_total_bytes",
        "finish_task_bytes", "finish_task_card_bytes", "count_messages_bytes", "screen_text_bytes",
        "app_memory_brief_bytes", "screenshot_id_bytes", "screen_image_count", "screen_image_b64_bytes",
    ]
    for t in row["turns"]:
        conn.execute(
            f"INSERT OR REPLACE INTO turns (run_id,{','.join(tcols)}) VALUES (?,{','.join('?' for _ in tcols)})",
            [row["run_id"]] + [t.get(c) for c in tcols],
        )
    conn.commit()


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Measure Poki iOS step latency and prompt breakdown on a fresh ephemeral simulator."
    )
    p.add_argument("--device-type", default=None, help="Optional simctl device type identifier for the ephemeral simulator")
    p.add_argument("--runtime", default=None, help="Optional simctl runtime identifier for the ephemeral simulator")
    p.add_argument("--target", action="append", required=True, help="label=commit=/path/to/Poki.app")
    p.add_argument("--tasks", default="settings,web,photos", help="Comma-separated tasks")
    p.add_argument("--profiles", default="light,heavy", help="Comma-separated memory profiles (empty, light, heavy)")
    p.add_argument("--memory-file", type=Path, default=None, help="Optional custom agent-memory.json fixture path")
    p.add_argument("--rounds", type=int, default=5, help="Interleaved rounds per profile")
    p.add_argument("--out", required=True, help="Output directory")
    p.add_argument("--max-wire-bytes", type=int, default=None, help="Optional gate for bisect/CI")
    p.add_argument("--max-tokens", type=int, default=None, help="Optional median token gate for bisect/CI")
    p.add_argument("--max-step-ms", type=float, default=None, help="Optional gate for bisect/CI")
    p.add_argument("--forbid-false-scroll", action="store_true", help="Fail if false_scroll rejects finish_task")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)

    developer_dir = resolve_developer_dir()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    targets = []
    for item in args.target:
        label, sha, path = item.split("=", 2)
        targets.append((label, sha, Path(path)))
    task_list = [t.strip() for t in args.tasks.split(",") if t.strip()]
    profile_list = [pr.strip() for pr in args.profiles.split(",") if pr.strip()]
    for profile in profile_list:
        make_memory_file(profile, args.memory_file)

    conn = init_db(out_dir / "results.sqlite")
    server = ThreadingHTTPServer(("127.0.0.1", 0), ScriptedHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    all_rows = []
    try:
        with ephemeral_simulator(device_type=args.device_type, runtime=args.runtime) as udid:
            for profile in profile_list:
                for r in range(args.rounds):
                    order = targets[r % len(targets):] + targets[:r % len(targets)]
                    for task_name in task_list:
                        for label, sha, app_path in order:
                            row = run_one(
                                server, udid, app_path, label, sha, task_name, profile, r, out_dir,
                                developer_dir=developer_dir, memory_file=args.memory_file, save_payload=(r == 0),
                            )
                            save_row(conn, row)
                            all_rows.append(row)
                            with (out_dir / "runs.jsonl").open("a") as jf:
                                jf.write(json.dumps({k: v for k, v in row.items() if k != "turns"}, ensure_ascii=False) + "\n")
                            iv = f"{row['step_interval_median_ms']:.0f}ms" if row["step_interval_median_ms"] is not None else "n/a"
                            wb = f"{row['wire_bytes_median']:.0f}B" if row["wire_bytes_median"] is not None else "n/a"
                            tk = f"{row['tokens_median']:.0f}tok" if row["tokens_median"] is not None else "n/a"
                            print(
                                f"[{profile} r{r}] {label:12s} {task_name:12s} ok={row['ok']} "
                                f"step_p50={iv:7s} wire_p50={wb:9s} tok_p50={tk:9s} "
                                f"sys={row['system_bytes']}B tools={row['tools_bytes']}B "
                                f"mem={row['memories_bytes']}B skill={row['skills_bytes']}B "
                                f"appMem={row['app_memory_brief_max_bytes']}B rej={row['finish_task_rejected']} {row['error']}",
                                flush=True,
                            )
    finally:
        server.shutdown()
        conn.close()

    failed = [r for r in all_rows if not r["ok"]]
    if failed:
        print(f"ERROR: {len(failed)}/{len(all_rows)} runs failed", file=sys.stderr)
        sys.exit(2)
    if args.max_wire_bytes is not None:
        med_wire = statistics.median(r["wire_bytes_median"] for r in all_rows if r["wire_bytes_median"] is not None)
        if med_wire > args.max_wire_bytes:
            print(f"GATE FAIL: median wire bytes {med_wire:.0f} > {args.max_wire_bytes}", file=sys.stderr)
            sys.exit(1)
    if args.max_tokens is not None:
        med_tok = statistics.median(r["tokens_median"] for r in all_rows if r["tokens_median"] is not None)
        if med_tok > args.max_tokens:
            print(f"GATE FAIL: median tokens {med_tok:.0f} > {args.max_tokens}", file=sys.stderr)
            sys.exit(1)
    if args.max_step_ms is not None:
        med_ms = statistics.median(r["step_interval_median_ms"] for r in all_rows if r["step_interval_median_ms"] is not None)
        if med_ms > args.max_step_ms:
            print(f"GATE FAIL: median step interval {med_ms:.1f}ms > {args.max_step_ms}ms", file=sys.stderr)
            sys.exit(1)
    if args.forbid_false_scroll:
        if any(r["finish_task_rejected"] for r in all_rows if r["task"] == "false_scroll"):
            print("GATE FAIL: false_scroll task had finish_task rejected", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
