#!/usr/bin/env python3
"""Live voice eval: plays spoken Chinese into a real Realtime session over WebRTC, as the phone's
microphone does, with the session the voice bridge mints (bin/voice-bridge.mjs: the same instructions,
tools and turn detection as VoiceDirect.swift), and checks what the model did. The client does what
VoiceModel does: it closes wait_for_user without asking for an answer, asks for none after a run_task
that went to the running task, and asks for one answer at a time. The tools are stubbed: they answer in
English, as Poki's often do, after about the time they take on a phone.

The scenarios are the spoken acceptance sentences for the live voice, with the iPhone in Chinese:

  open         打开微信: one word (好), WeChat opened, the result in Chinese
  scroll       打开微信, then 往下翻一下: a scroll on the screen in front (phone_step, or a swipe in do),
               not Poki's agent, no translation, nothing in English
  hello        给文件传输助手发个hello: one sentence that names 文件传输助手, then the work starts in the
               same turn, without waiting for a yes
  stop         停 while that task runs: stop_task, or no more steps
  backchannel  嗯 0.3 s into Poki's answer: the answer plays to its end, is not said again, nothing in English
and more from talks on a physical iPhone:
  start_blip   a short English sound as the talk opens, then 帮我打开我的微信: every answer in Chinese
  flip         打开微信, then 稍微翻一下: a scroll, not a translation
  back         打开微信, then 返回上一页: one step back on the screen in front, not Poki's agent
  barge        打开小红书 said 0.5 s into Poki's answer about the screen: Xiaohongshu opens within 3 s of it
  vague        打开微信, then 帮我打开: a short question, and nothing opened
  quiet_add    帮我回到微信的首页 (Poki's agent), then 再打开小红书 while it works: nothing said until the
               result, besides one 好
  hush         别说了 said 0.5 s into Poki's answer: the answer does not go on, at most a short 好的
Before any call that changes the phone, Poki says at most one word (好), except the sentence that says what it sends.

Speech comes from macOS `say` (Tingting, Samantha) through ffmpeg; nothing is played aloud. Needs
`pip install aiortc aiohttp`, Node for the bridge and an OpenAI API key:

    OPENAI_API_KEY=... python3 native/ios-app/scripts/voice-eval.py [--scenario all] [--runs 4] [--root <checkout>]

--root runs the same scenarios against another checkout's voice bridge, to compare two versions.
A scenario passes when every run does. Exit status 1 when any scenario fails.
"""
import argparse, asyncio, fractions, json, os, re, subprocess, sys, tempfile, time

import aiohttp
import av
from aiortc import MediaStreamTrack, RTCPeerConnection, RTCSessionDescription

RATE = 48000
FRAME = 960
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
CLIPS = {
    "it": ("Samantha", "it"),
    "open_mine": ("Tingting", "帮我打开我的微信"),
    "open": ("Tingting", "打开微信"),
    "look": ("Tingting", "看一下我这个界面有什么内容"),
    "scroll": ("Tingting", "往下翻一下"),
    "flip": ("Tingting", "稍微翻一下"),
    "hello": ("Tingting", "给文件传输助手发个hello"),
    "stop": ("Tingting", "停"),
    "en": ("Tingting", "嗯"),
    "back": ("Tingting", "返回上一页"),
    "xhs": ("Tingting", "打开小红书"),
    "vague": ("Tingting", "帮我打开"),
    "first_page": ("Tingting", "帮我回到微信的首页"),
    "add_xhs": ("Tingting", "再打开小红书"),
    "hush": ("Tingting", "别说了"),
}
LOOK = ("app: WeChat\nelements (9):\n 1 Other \"Chats\" [0,54,402,44]\n 2 Button \"Search\" [306,58,40,44]\n"
        " 3 Cell \"Family group, unread, [6 messages] Mom: ok, 13:42\" [0,353,402,72]\n 4 Cell \"Official Accounts, unread, [6]\" [0,425,402,72]\n"
        " 5 Cell \"Alex, [Voice] 11\\\", 13:37\" [0,497,402,72]\n 6 Button \"Chats\" [0,800,100,74]\n 7 Button \"Contacts\" [100,800,100,74]\n"
        " 8 Button \"Discover\" [200,800,100,74]\n 9 Button \"Me\" [300,800,100,74]")
OPENED = "launch com.tencent.xin\napp: WeChat\nelements (3):\n 1 Other \"Chats\" [0,54,402,44]\n 2 Button \"Search\" [306,58,40,44]\n 3 Button \"Me\" [300,800,100,74]"
TASK = "result: done: the task is finished.\nPoki said: Done."
SCREEN = "app: WeChat\nelements (3):\n 1 Cell \"Family group, 13:42\" [0,353,402,72]\n 2 Cell \"Alex, 13:37\" [0,425,402,72]\n 3 Button \"Me\" [300,800,100,74]"
RESUME = "That sound cut off your last answer. If it was only a backchannel (嗯, 哦, uh-huh), say only the rest of that answer: carry on at the next phrase after the last word heard, and say nothing that was already said. If it asked you to stop or be quiet, call wait_for_user and say nothing."  # VoiceModel.resume
# --client 1751: the phone before the backchannel resume (origin/main), which asks for nothing after a cut.
RESUMES = True
ADDED = "added: the running task takes this in. Do not hand it over again; the task's result follows when it ends."
APPS = {"微信": "com.tencent.xin", "小红书": "com.xingin.discover"}
# The phone's own tools, which change the screen; run_task's are Poki's agent's.
ACTS = {"open_app", "do", "phone_step", "run_task"}
STOPPED = "result: stopped by the user."


def make_clips(folder):
    for name, (voice, text) in CLIPS.items():
        aiff = os.path.join(folder, f"{name}.aiff")
        subprocess.run(["say", "-v", voice, "-o", aiff, text], check=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", aiff, "-ac", "1", "-ar", str(RATE), "-f", "s16le",
                        os.path.join(folder, f"{name}.pcm")], check=True)


class Mic(MediaStreamTrack):
    """Silence, except for the clips handed to say(), in real time."""
    kind = "audio"

    def __init__(self):
        super().__init__()
        self.queue = bytearray()
        self.pts = 0
        self.start = None

    def say(self, pcm):
        self.queue += pcm

    async def recv(self):
        self.start = self.start or time.monotonic()
        wait = self.start + self.pts / RATE - time.monotonic()
        if wait > 0:
            await asyncio.sleep(wait)
        chunk = bytes(self.queue[:FRAME * 2]).ljust(FRAME * 2, b"\0")
        del self.queue[:FRAME * 2]
        frame = av.AudioFrame(format="s16", layout="mono", samples=FRAME)
        frame.planes[0].update(chunk)
        frame.sample_rate, frame.pts, frame.time_base = RATE, self.pts, fractions.Fraction(1, RATE)
        self.pts += FRAME
        return frame


def chinese(text):
    han = len(re.findall(r"[一-鿿]", text))
    return han > 0 and han >= len(re.findall(r"[A-Za-z]", text)) / 3


class Talk:
    def __init__(self, secret, clips):
        self.secret, self.clips = secret, clips
        self.t0 = time.monotonic()
        self.mic = Mic()
        self.log, self.calls, self.replies, self.spoken = [], [], [], []
        self.args = {}
        self.events = 0
        self.speaking = False
        self.active = None
        self.stopped = asyncio.Event()
        self.running = False
        self.cut = False
        self.timed = []
        self.stops = []
        self.task_takes = 1.5
        self.cleared = self.cancelled = self.outputs = self.replied_after_output = 0

    def note(self, text):
        self.log.append(f"{time.monotonic() - self.t0:6.2f} {text}")

    def send(self, event):
        self.channel.send(json.dumps(event))

    def say(self, clip):
        with open(os.path.join(self.clips, f"{clip}.pcm"), "rb") as f:
            self.mic.say(f.read())

    async def until(self, test, timeout=20):
        end = time.monotonic() + timeout
        while time.monotonic() < end and not test():
            await asyncio.sleep(0.05)
        return test()

    async def quiet(self, settle=1.5, timeout=30):
        """Until nothing has happened for `settle` seconds and Poki is not speaking."""
        end, last, seen = time.monotonic() + timeout, time.monotonic(), self.events
        while time.monotonic() < end:
            await asyncio.sleep(0.1)
            if self.events != seen or self.speaking:
                seen, last = self.events, time.monotonic()
            elif time.monotonic() - last > settle:
                return

    def english(self):
        return [x for x in self.replies if x.strip() and not chinese(x)]

    def now(self):
        return time.monotonic() - self.t0

    def acts(self, since=0.0):
        """The calls that change the phone, made after `since`, as (time, name, arguments)."""
        return [c for c in self.timed if c[0] >= since and c[1] in ACTS]

    def said(self, since=0.0, until=float("inf")):
        return [text for t, text in self.spoken if since <= t < until]

    def chatter(self, since=0.0):
        """What Poki said after the last speech before its first phone call after `since`, beyond one word (好)."""
        acts = self.acts(since)
        if not acts:
            return []
        stop = max([t for t in self.stops if t < acts[0][0]] or [since])
        return [x for x in self.said(stop, acts[0][0] + 0.01) if len(re.sub(r"\W", "", x)) > 3]

    def opens(self, app, since=0.0):
        """The first call after `since` that opens `app`, as its time, or None."""
        for t, name, args in self.acts(since):
            if (name == "open_app" and app in (args or "")) or (name == "do" and APPS[app] in (args or "")):
                return t
        return None

    def scrolls(self, since=0.0):
        return any((n == "phone_step" and "scroll" in (a or "")) or (n == "do" and "swipe" in (a or "")) for _, n, a in self.acts(since))

    def backs(self, since=0.0):
        return any((n == "phone_step" and "back" in (a or "")) or (n == "do" and "back" in (a or "")) for _, n, a in self.acts(since))

    def on_event(self, e):
        self.events += 1
        t = e.get("type", "")
        if t == "session.created":
            self.note("session created")
        elif t == "session.updated":
            turn = e.get("session", {}).get("audio", {}).get("input", {}).get("turn_detection")
            self.note(f"speech detection {'on' if turn else 'off'}")
        elif t == "input_audio_buffer.speech_started":
            self.cut = self.cut or self.speaking
            self.note("speech started")
        elif t == "input_audio_buffer.speech_stopped":
            self.stops.append(self.now())
            self.note("speech stopped")
        elif t == "conversation.item.input_audio_transcription.completed":
            self.note(f"heard: {e.get('transcript', '').strip()}")
        elif t == "response.created":
            self.active = e.get("response", {}).get("id")
        elif t == "response.done":
            response = e.get("response", {})
            self.cancelled += response.get("status") == "cancelled"
            if response.get("id") == self.active:
                self.active = None
            if any(i.get("type") == "function_call" and i.get("name") != "wait_for_user" for i in response.get("output", [])):
                self.cut = False
            self.note(f"response {response.get('status')}")
        elif t == "output_audio_buffer.started":
            self.speaking, self.cut = True, False
            self.note("audio started")
        elif t in ("output_audio_buffer.stopped", "output_audio_buffer.cleared"):
            self.speaking = False
            self.cleared += t.endswith("cleared")
            self.note(f"audio {t.split('.')[-1]}")
        elif t == "response.output_audio_transcript.done":
            self.replies.append(e.get("transcript", ""))
            self.spoken.append((self.now(), e.get("transcript", "")))
            self.replied_after_output += self.outputs > 0
            self.note(f"said: {e.get('transcript', '')}")
        elif t == "response.output_item.done" and e.get("item", {}).get("type") == "function_call":
            item = e["item"]
            self.calls.append(item.get("name"))
            self.timed.append((self.now(), item.get("name"), item.get("arguments")))
            self.args.setdefault(item.get("name"), []).append(item.get("arguments"))
            self.note(f"call {item.get('name')} {item.get('arguments')}")
            asyncio.get_event_loop().create_task(self.answer(item))
        elif t == "error":
            self.note(f"error: {e.get('error', {}).get('message')}")

    async def answer(self, item):
        name, args = item.get("name"), item.get("arguments") or ""
        ask = name != "wait_for_user"
        if name == "wait_for_user" and self.cut and RESUMES:
            # VoiceModel.leaveUnanswered: a 嗯 that cut Poki off gets the rest of the answer.
            self.cut, ask = False, True
            self.send({"type": "conversation.item.create", "item": {"type": "message", "role": "system", "content": [{"type": "input_text", "text": RESUME}]}})
        if name == "run_task" and self.running:
            # VoiceTasks: a second run_task goes to the running task, and VoiceModel asks for no answer.
            output, ask = ADDED, False
        elif name == "run_task":
            self.running = True
            try:
                await asyncio.wait_for(self.stopped.wait(), self.task_takes)
                output = STOPPED
            except asyncio.TimeoutError:
                output = TASK
            self.running = False
        else:
            if name == "stop_task":
                self.stopped.set()
            await asyncio.sleep({"look": 0.8, "open_app": 1.0, "phone_step": 1.0, "do": 1.0}.get(name, 0))
            if name in ("open_app", "do") and any(k in args or v in args for k, v in APPS.items()):
                output = OPENED if ("微信" in args or "tencent" in args) else OPENED.replace("com.tencent.xin", "com.xingin.discover").replace("WeChat", "Xiaohongshu")
            elif name in ("phone_step", "do"):
                output = f"{json.loads(args or '{}')}: done\n" + SCREEN
            else:
                output = {"look": LOOK, "stop_task": "stopped", "check_task": "running for 3 s: step 1 of 2"}.get(name, "ok")
        self.send({"type": "conversation.item.create", "item": {"type": "function_call_output", "call_id": item["call_id"], "output": output}})
        self.outputs += 1
        if ask:
            # As VoiceModel.flush: one response at a time.
            await self.until(lambda: self.active is None, timeout=10)
            self.send({"type": "response.create"})

    async def connect(self):
        self.pc = RTCPeerConnection()
        self.pc.addTrack(self.mic)
        self.channel = self.pc.createDataChannel("oai-events")
        created = asyncio.Event()

        @self.channel.on("message")
        def message(raw):
            event = json.loads(raw)
            if event.get("type") == "session.created":
                created.set()
            self.on_event(event)

        @self.pc.on("track")
        def track(remote):
            async def drain():
                try:
                    while True:
                        await remote.recv()
                except Exception:
                    pass
            asyncio.get_event_loop().create_task(drain())

        await self.pc.setLocalDescription(await self.pc.createOffer())
        async with aiohttp.ClientSession() as http:
            async with http.post("https://api.openai.com/v1/realtime/calls", data=self.pc.localDescription.sdp,
                                 headers={"Authorization": f"Bearer {self.secret}", "Content-Type": "application/sdp"}) as r:
                answer = await r.text()
                if r.status >= 300:
                    raise RuntimeError(f"realtime/calls answered {r.status}: {answer[:200]}")
        await self.pc.setRemoteDescription(RTCSessionDescription(sdp=answer, type="answer"))
        await asyncio.wait_for(created.wait(), 15)


async def opened(t, clip="open"):
    t.say(clip)
    await t.until(lambda: t.outputs > 0 and t.replied_after_output > 0)
    await t.quiet()


def plain(t, **more):
    return {"calls": [f"{n} {a}" for _, n, a in t.timed], "said": t.replies, "english": t.english(), **more}


async def open_wechat(t):
    await opened(t)
    first = t.replies[0] if t.replies else ""
    ok = t.opens("微信") is not None and len(re.sub(r"\W", "", first)) <= 3 and not t.chatter() and t.replied_after_output > 0 and not t.english()
    return ok, plain(t, chatter=t.chatter())


async def then(t, clip, check):
    await opened(t)
    since, calls = t.now(), len(t.calls)
    t.say(clip)
    await t.until(lambda: len(t.calls) > calls)
    await t.quiet(settle=2.5)
    translated = any("翻译" in x or "translat" in x.lower() for x in t.said(since))
    chatter = t.chatter(since)
    return check(t, since) and not translated and not chatter and not t.english(), plain(t, agent="run_task" in t.calls[calls:], chatter=chatter)


async def hello(t):
    t.task_takes = 4
    t.say("hello")
    await t.until(lambda: t.acts())
    first = t.acts()[0][0] if t.acts() else float("inf")
    restated = [x for x in t.said(0, first + 0.01) if "文件传输助手" in x]
    asked = [x for x in t.said(0, first + 0.01) if "吗" in x or "?" in x or "？" in x]
    await t.until(lambda: t.replied_after_output > 0)
    await t.quiet()
    ok = bool(restated) and not asked and bool(t.acts()) and not t.english()
    return ok, plain(t)


async def stop(t):
    t.task_takes = 30
    t.say("hello")
    await t.until(lambda: t.acts())
    await t.until(lambda: not t.speaking and t.active is None, timeout=10)
    await asyncio.sleep(1)
    t.say("stop")
    since = t.now()
    await t.until(lambda: "stop_task" in t.calls, timeout=8)
    await t.quiet()
    later = [n for _, n, _ in t.acts(since + 1.5)]
    ok = ("stop_task" in t.calls or not later) and not t.english()
    return ok, plain(t)


async def start_blip(t):
    t.say("it")
    await t.quiet()
    await opened(t, "open_mine")
    return t.opens("微信") is not None and not t.english(), plain(t)


async def backchannel(t):
    t.say("look")
    await t.until(lambda: t.outputs > 0)
    await t.until(lambda: t.speaking and t.replied_after_output == 0)
    await asyncio.sleep(0.3)
    t.say("en")
    await t.quiet(settle=2.5)
    whole = t.cleared == 0 and t.cancelled == 0 and t.replied_after_output == 1
    # Cut off, then the rest said: the second reply must not start the answer again.
    first, rest = (t.replies + ["", ""])[:2]
    # The rest of the answer, not an answer to the 嗯 ("好的，需要我帮你……吗？").
    answered = rest.lstrip().startswith(("好", "嗯", "对")) or any(w in rest for w in ("?", "？", "吗", "需要我", "告诉我", "随时", "如果你"))
    resumed = t.cleared == 1 and len(t.replies) == 2 and bool(rest.strip()) and first[:4] not in rest and not answered
    ok = (whole or resumed) and not t.english()
    return ok, plain(t, cleared=t.cleared, cancelled=t.cancelled, whole=whole, resumed=resumed)


async def barge(t):
    t.say("look")
    await t.until(lambda: t.outputs > 0)
    await t.until(lambda: t.speaking and t.replied_after_output == 0)
    await asyncio.sleep(0.5)
    since = t.now()
    t.say("xhs")
    await t.until(lambda: t.opens("小红书") is not None, timeout=12)
    await t.quiet()
    opened_at = t.opens("小红书")
    said = max([s for s in t.stops if s < (opened_at or float("inf"))] or [since])
    took = None if opened_at is None else round(opened_at - said, 2)
    chatter = t.chatter(since)
    return took is not None and took <= 3.0 and not chatter and not t.english(), plain(t, took=took, cleared=t.cleared, chatter=chatter)


async def hush(t):
    """别说了 0.5 s into Poki's answer, with no task running: the answer does not go on (a short 好的 may follow)."""
    t.say("look")
    await t.until(lambda: t.outputs > 0)
    await t.until(lambda: t.speaking and t.replied_after_output == 0)
    await asyncio.sleep(0.5)
    t.say("hush")
    since = t.now()
    await t.quiet(settle=3)
    later = [x for x in t.replies[1:] if len(re.sub(r"\W", "", x)) > 8]
    return not later and not t.acts() and not t.english(), plain(t, later=later)


async def vague(t):
    await opened(t)
    since = t.now()
    t.say("vague")
    await asyncio.sleep(2)
    await t.quiet(settle=2.5)
    asked = [x for x in t.said(since) if "哪" in x or "?" in x or "？" in x or "什么" in x]
    return not t.acts(since) and bool(asked) and not t.english(), plain(t)


async def quiet_add(t):
    t.task_takes = 9
    t.say("first_page")
    await t.until(lambda: t.acts(), timeout=10)
    await t.until(lambda: not t.speaking and t.active is None, timeout=10)
    await asyncio.sleep(1)
    since = t.now()
    t.say("add_xhs")
    await t.until(lambda: t.outputs > 0 and not t.running and t.replied_after_output > 0, timeout=25)
    await t.quiet(settle=2.5)
    between = [x for x in t.said(since)[:-1] if len(re.sub(r"\W", "", x)) > 3]
    added = any(n in ("run_task", "open_app", "do") for _, n, _ in t.acts(since))
    return added and not between and not t.english(), plain(t, chatter=between)


SCENARIOS = {
    "open": open_wechat,
    "scroll": lambda t: then(t, "scroll", lambda t, since: t.scrolls(since)),
    "hello": hello,
    "stop": stop,
    "backchannel": backchannel,
    "start_blip": start_blip,
    "flip": lambda t: then(t, "flip", lambda t, since: t.scrolls(since)),
    "back": lambda t: then(t, "back", lambda t, since: t.backs(since)),
    "barge": barge,
    "vague": vague,
    "quiet_add": quiet_add,
    "hush": hush,
}


async def bridge(root, language):
    """A voice bridge from `root`, and a function that mints one session's client secret from it."""
    state = tempfile.mkdtemp(prefix="voice-eval-")
    proc = await asyncio.create_subprocess_exec("node", os.path.join(root, "bin/voice-bridge.mjs"), "--port", "0", "--host", "127.0.0.1",
                                                env={**os.environ, "POKI_MCP_STATE_DIR": state},
                                                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    port = json.loads(await proc.stdout.readline())["port"]
    with open(os.path.join(state, "voice-bridge.json")) as f:
        secret = json.load(f)["secret"]

    async def mint():
        async with aiohttp.ClientSession() as http:
            async with http.get(f"http://127.0.0.1:{port}/voice/{secret}/token?language={language}") as r:
                body = await r.json()
                if r.status != 200:
                    raise RuntimeError(f"the bridge answered {r.status}: {body.get('error')}")
                return body["value"]
    return proc, mint


async def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--scenario", default="all", choices=["all", *SCENARIOS])
    p.add_argument("--runs", type=int, default=4)
    p.add_argument("--language", default="zh-Hans-CN", help="the iPhone's language")
    p.add_argument("--root", default=ROOT, help="the checkout whose voice bridge mints the sessions")
    p.add_argument("--out", help="write every run's log here as JSON")
    p.add_argument("--client", default="new", choices=["new", "1751"], help="1751: the phone app without the backchannel resume")
    a = p.parse_args()
    global RESUMES
    RESUMES = a.client == "new"
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("Set OPENAI_API_KEY.")
    names = list(SCENARIOS) if a.scenario == "all" else [a.scenario]
    clips = tempfile.mkdtemp(prefix="voice-eval-clips-")
    make_clips(clips)
    proc, mint = await bridge(a.root, a.language)
    report, failed = {}, []
    try:
        for name in names:
            runs = []
            for n in range(a.runs):
                t = Talk(None, clips)
                try:
                    t.secret = await mint()
                    await t.connect()
                    ok, detail = await SCENARIOS[name](t)
                except Exception as error:
                    ok, detail = False, {"error": repr(error)}
                finally:
                    if hasattr(t, "pc"):
                        await t.pc.close()
                runs.append({"ok": ok, **detail, "log": t.log})
                print(f"--- {name} {n + 1}: {'pass' if ok else 'FAIL'}", *t.log, f"    {json.dumps(detail, ensure_ascii=False)}", sep="\n    ", flush=True)
            passed = sum(r["ok"] for r in runs)
            print(f"=== {name}: {passed}/{a.runs}", flush=True)
            report[name] = runs
            if passed < a.runs:
                failed.append(name)
    finally:
        proc.terminate()
        await proc.wait()
    if a.out:
        with open(a.out, "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
    print("failed: " + ", ".join(failed) if failed else "all passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    asyncio.run(main())
