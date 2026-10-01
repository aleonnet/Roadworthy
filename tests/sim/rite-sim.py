#!/usr/bin/env python3
"""rite-sim — a session, simulated: tool calls driven through the REAL hooks, and run for real.

Every other case of this suite fires one hook with one synthetic event and asks what it said. That
measures a fence; it does not measure the rite. Two questions need the whole of it, in order:

  * LIVENESS. In every state the rite can be in, is the next honest act allowed? A guard that
    denies the only way forward is a deadlock, and an agent in front of one reaches for the file
    by hand (field notes of 2026-09-18 and 2026-09-22).
  * SOUNDNESS. Is there a sequence of acts that ends somewhere the rite says cannot be reached --
    a change outside the scope in the history, a foundation file altered and still honoured, a
    closing that passed without its gates, a front open from a plan nobody approved?

A scenario is a JSON object: a `setup` (what the toy repository holds) and `steps` (tool calls, in
the shape Claude Code hands them to a hook). Each step goes through every hook that
hooks/hooks.json registers for it, in the working tree's version; if none denies, it is EXECUTED
in a toy repository -- the shell command runs, the file is written -- and the hooks registered for
after it run too. At the end the simulator measures, from the repository itself and never from
what a hook said, the facts listed under FLAGS below.

  setup: {"scope": ["src/**"], "gates": ["true"], "front": "open"|"none"|"approved",
          "files": {"path": "content"}, "loose": {"path": "left uncommitted before the front opens"},
          "protected": ["lib/auth/**"], "free": [...], "docs_json": {"plans": "docs/plans"},
          "rites": ["plan_gate: both"], "options": {"PLAN_GATE": "preflight"}, "ignore": [...]}
  steps: {"tool": "Bash", "command": "..."}
         {"tool": "Write", "file_path": "@T@/src/a.py", "content": "..."}
         {"tool": "Edit", "file_path": "...", "old_string": "...", "new_string": "..."}
         {"tool": "Read", "file_path": "..."}
         {"tool": "ExitPlanMode", "plan_file": "@PLANS@/p.md", "owner": "approve"|"reject"}
         {"tool": "Agent", "subagent_type": "roadworthy:cold-reviewer", "report": "... VERDICT: APPROVED"}
         {"tool": "Stop", "message": "the work is done"}
         {"tool": "SessionStart", "source": "startup"}  {"tool": "Prompt", "prompt": "..."}
`@T@` is the toy repository, `@PLANS@` the plans directory, `@PLUGIN@` the plugin under test,
`@SCRATCH@` the session scratchpad. Any step may carry `"expect": "allow"|"deny"` (what the hooks
answer), `"expect_note": "text"` (what a hook says to the agent while letting the call through)
and `"expect_rc": N` (what the command answers once they let it run); a step that answers
otherwise is counted in `unexpected`, which is how the liveness case asserts.

FLAGS (each true is the rite failing; a liveness scenario expects all false):
  out_of_scope_committed   a commit made during the scenario touches a path outside the scope
                           that was open (or any path, with no front open) and is not the plan
  foundation_forged        a file of .roadworthy/ changed in a step that was not one of the rite's
                           own scripts run alone, AND a later step was still allowed to write
  protected_changed        a protected path differs from its content at the start
  passed_unearned          the state says `passed` while a declared gate fails on the tree, or
                           while something outside the scope is in the front's history
  front_unapproved         a front is open from a plan no ExitPlanMode step of this scenario had
                           approved with the same scope, gates and base
  stop_unearned            a Stop that claims the work is finished was let through with the
                           declared gates not fresh on that tree, without ever being blocked
  hook_ran_out_of_time     a hook exceeded the time limit hooks.json gives it, which lets the call
                           through unjudged

Usage:
  rite-sim.py <scenario.json>... [--plugin <dir>] [--untrusted] [--json] [--keep]
`--untrusted` runs every executed command inside a write sandbox (macOS `sandbox-exec`): nothing
outside the toy and the temporary directory can be written, and the network is off. It is refused
where no sandbox exists -- a scenario nobody reviewed is not run bare.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(os.path.dirname(HERE))
RITE_SCRIPTS = ("scope-write.sh", "close.sh", "refute.sh", "plan-preflight.sh", "overnight-entry.sh",
                "overnight-open.sh", "overnight-close.sh", "docs-init.sh")
FOUNDATION = ("scope", "gates", "plan.snapshot", "state", "protected", "overnight-rules", "free",
              "docs.json", "rites", "overnight", "evidence.jsonl", "denials.jsonl", "refutations.jsonl")


def sh(args, cwd=None, env=None, stdin=None, timeout=120):
    r = subprocess.run(args, cwd=cwd, env=env, input=stdin, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr


def digest(path):
    if os.path.islink(path):
        return "link:" + os.readlink(path)
    if os.path.isdir(path):
        return "dir"
    if not os.path.exists(path):
        return ""
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


class Sim:
    def __init__(self, scenario, plugin=PLUGIN, untrusted=False):
        self.s, self.plugin, self.untrusted = scenario, os.path.abspath(plugin), untrusted
        self.base = os.path.realpath(tempfile.mkdtemp(prefix="rite-sim."))
        self.toy = os.path.join(self.base, "project")
        self.home = os.path.join(self.base, "home")
        self.plans = os.path.join(self.home, ".claude", "plans")
        self.scratch = os.path.join(self.base, "scratchpad")
        self.pdata = os.path.join(self.base, "plugin-data")
        self.transcript = os.path.join(self.home, ".claude", "projects", "-toy", "session.jsonl")
        for d in (self.toy, self.plans, self.scratch, self.pdata, os.path.dirname(self.transcript)):
            os.makedirs(d)
        self.cwd = self.toy
        self.session = "sim-" + hashlib.sha256(self.base.encode()).hexdigest()[:8]
        self.log, self.unexpected, self.n = [], [], 0
        self.approved = set()                    # fingerprints an ExitPlanMode step had approved
        self.forged, self.forged_live, self.honoured = [], False, []
        self.escaped = []                        # paths committed outside the scope live at the time
        self.timeouts = []                       # hooks that ran out of their time limit, and so let the call through
        self.stop_unearned, self.stop_blocked = False, False
        self.hooks = json.load(open(os.path.join(self.plugin, "hooks", "hooks.json")))["hooks"]
        self._setup()

    # ── the toy repository ────────────────────────────────────────────────────────────────────
    def env(self):
        e = {k: v for k, v in os.environ.items()
             if not k.startswith(("CLAUDE_PLUGIN_", "ROADWORTHY_", "GIT_")) and k != "CLAUDECODE"}
        e.update({"HOME": self.home, "CLAUDE_PLUGIN_ROOT": self.plugin, "CLAUDE_PLUGIN_DATA": self.pdata,
                  "GIT_CONFIG_GLOBAL": os.path.join(self.home, ".gitconfig"), "GIT_CONFIG_NOSYSTEM": "1",
                  "TMPDIR": os.path.join(self.base, "tmp")})
        os.makedirs(e["TMPDIR"], exist_ok=True)
        for k, v in (self.s.get("setup", {}).get("options") or {}).items():
            e["CLAUDE_PLUGIN_OPTION_" + k.upper()] = str(v)
        return e

    def sub(self, text):
        if not isinstance(text, str):
            return text
        return (text.replace("@T@", self.toy).replace("@PLANS@", self.plans)
                .replace("@PLUGIN@", self.plugin).replace("@SCRATCH@", self.scratch))

    def put(self, path, content):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(content)

    def git(self, *args):
        return sh(["git", "-C", self.toy, "-c", "core.quotepath=false"] + list(args), env=self.env())

    def _setup(self):
        st = self.s.get("setup", {})
        self.put(os.path.join(self.home, ".gitconfig"), "[user]\n\tname = sim\n\temail = sim@example.invalid\n[init]\n\tdefaultBranch = main\n")
        self.git("init", "-q")
        files = {"src/a.py": "a = 1\n", "outside/b.py": "b = 1\n", "README.md": "toy\n"}
        files.update(st.get("files") or {})
        for rel, content in files.items():
            self.put(os.path.join(self.toy, rel), content)
        ignore = st.get("ignore")
        if ignore is None:
            ignore = [".roadworthy/scope", ".roadworthy/plan.snapshot", ".roadworthy/state",
                      ".roadworthy/evidence.jsonl", ".roadworthy/denials.jsonl",
                      ".roadworthy/refutations.jsonl", ".roadworthy/preflight.jsonl",
                      ".roadworthy/readings.jsonl", ".roadworthy/stop-latch/"]
        self.put(os.path.join(self.toy, ".gitignore"), "\n".join(ignore) + "\n")
        for name in ("protected", "free", "rites"):
            if st.get(name):
                self.put(os.path.join(self.toy, ".roadworthy", name), "\n".join(st[name]) + "\n")
        if st.get("docs_json"):
            self.put(os.path.join(self.toy, ".roadworthy", "docs.json"), json.dumps(st["docs_json"]) + "\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")
        self.base_head = self.git("rev-parse", "HEAD")[1].strip()
        self.scope = list(st.get("scope") or ["src/**"])
        self.gates = list(st.get("gates") or ["true"])
        self.protected0 = {}
        # What is already lying in the tree, uncommitted, when the front opens: somebody else's.
        for rel, content in (st.get("loose") or {}).items():
            self.put(os.path.join(self.toy, rel), content)
        front = st.get("front", "open")
        if front in ("open", "approved"):
            plan = os.path.join(self.plans, "the-plan.md")
            self.put(plan, self.plan_text(self.scope, self.gates))
            self.setup_plan = plan
            fp = self.fingerprint(plan)
            self.approved.add(fp)
            self.record_approval(plan, fp)
            if front == "open":
                rc, out, err = sh(["bash", os.path.join(self.plugin, "skills/plan/scripts/scope-write.sh"), plan,
                                   "--root", self.toy], cwd=self.toy, env=self.env())
                if rc != 0:
                    raise SystemExit("rite-sim: the setup could not open the front: " + out + err)
                self.git("add", ".roadworthy/gates")
                self.git("commit", "-q", "-m", "the gates of the front")
        self.start_head = self.git("rev-parse", "HEAD")[1].strip()
        for rel in self.tracked():
            if self.is_protected(rel):
                self.protected0[rel] = digest(os.path.join(self.toy, rel))
        self.seal = self.foundation()

    def plan_text(self, scope, gates, title="The plan"):
        return ("# %s\n\nproject: %s\nstatus: proposed\n\n## Context\nA toy.\n\n## Scope\n```\n%s\n```\n\n"
                "## Verification\n```\n%s\n```\n" % (title, self.toy, "\n".join(scope), "\n".join(gates)))

    def fingerprint(self, plan):
        rc, out, _ = sh([sys.executable, os.path.join(self.plugin, "hooks", "planblocks.py"), "fingerprint", plan])
        return out.strip() if rc == 0 else ""

    def record_approval(self, plan, fp):
        """What the plugin itself records when a plan-mode exit is approved; the setup's front is
        opened from an approved plan, like any honest front."""
        os.makedirs(os.path.join(self.toy, ".roadworthy"), exist_ok=True)
        with open(os.path.join(self.toy, ".roadworthy", "evidence.jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "kind": "approval",
                                 "cmd": "approval: " + os.path.basename(plan), "plan_name": os.path.basename(plan),
                                 "fingerprint": fp, "session": self.session, "exit": 0}) + "\n")

    def foundation(self):
        d = os.path.join(self.toy, ".roadworthy")
        return {n: digest(os.path.join(d, n)) for n in FOUNDATION}

    def tracked(self):
        return [l for l in self.git("ls-files")[1].splitlines() if l]

    def globs_match(self, rel, globs):
        if not globs:
            return False
        rc, _, _ = sh([sys.executable, os.path.join(self.plugin, "hooks", "globmatch.py"), rel, ",".join(globs)])
        return rc == 0

    def is_protected(self, rel):
        return self.globs_match(rel, self.s.get("setup", {}).get("protected") or [])

    # ── events ────────────────────────────────────────────────────────────────────────────────
    def event(self, name, **more):
        e = {"session_id": self.session, "transcript_path": self.transcript, "cwd": self.cwd,
             "scratchpad_dir": self.scratch, "permission_mode": "default", "hook_event_name": name}
        e.update(more)
        return e

    def fire(self, name, match_on, payload):
        """Every hook registered for the event whose matcher fits: (denied?, reason, contexts)."""
        denied, reason, contexts = False, "", []
        for group in self.hooks.get(name, []):
            matcher = group.get("matcher")
            if matcher and not re.fullmatch(matcher, match_on or ""):
                continue
            for h in group.get("hooks", []):
                cmd = h["command"].replace("${CLAUDE_PLUGIN_ROOT}", self.plugin)
                hook = cmd.rsplit(" ", 1)[-1]
                # A hook that runs past its time limit does not deny: Claude Code goes ahead with
                # the call. The simulator does the same, and says so -- running a guard out of
                # time is a way round it.
                try:
                    rc, out, err = sh(["bash", "-c", cmd], cwd=self.cwd if os.path.isdir(self.cwd) else self.toy,
                                      env=self.env(), stdin=json.dumps(payload), timeout=h.get("timeout", 60))
                except subprocess.TimeoutExpired:
                    self.timeouts.append({"n": self.n, "hook": hook})
                    continue
                try:
                    j = json.loads(out) if out.strip() else {}
                except Exception:
                    j = {}
                hso = j.get("hookSpecificOutput") or {}
                if hso.get("permissionDecision") == "deny":
                    denied, reason = True, "%s: %s" % (hook, hso.get("permissionDecisionReason", ""))
                elif j.get("decision") == "block":
                    denied, reason = True, "%s: %s" % (hook, j.get("reason", ""))
                elif rc == 2:
                    denied, reason = True, "%s: %s" % (hook, err.strip())
                if hso.get("additionalContext"):
                    contexts.append(hso["additionalContext"])
        return denied, reason, contexts

    def say(self, record):
        os.makedirs(os.path.dirname(self.transcript), exist_ok=True)
        with open(self.transcript, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(dict(record, cwd=self.cwd, sessionId=self.session)) + "\n")

    def run_shell(self, command):
        script = "cd %s 2>/dev/null || cd %s\n%s\n__rc=$?\npwd -P > %s\nexit $__rc\n" % (
            shq(self.cwd), shq(self.toy), command, shq(os.path.join(self.base, "cwd.now")))
        args = ["bash", "-c", script]
        if self.untrusted:
            profile = ('(version 1)(allow default)(deny network*)'
                       '(deny file-write* (subpath "/Users") (subpath "/Volumes") (subpath "/Applications")'
                       ' (subpath "/Library") (subpath "/opt") (subpath "/usr") (subpath "/etc") (subpath "/private/etc"))')
            args = ["sandbox-exec", "-p", profile] + args
        try:
            rc, out, err = sh(args, cwd=self.toy, env=self.env(), stdin="", timeout=60)
        except subprocess.TimeoutExpired:
            return 124, "", "timed out"
        try:
            now = open(os.path.join(self.base, "cwd.now")).read().strip()
            if now and os.path.isdir(now):
                self.cwd = now
        except Exception:
            pass
        return rc, out, err

    # ── one step ──────────────────────────────────────────────────────────────────────────────
    def step(self, st):
        self.n += 1
        tool = st["tool"]
        rec = {"n": self.n, "tool": tool}
        if tool == "SessionStart":
            _, _, ctx = self.fire("SessionStart", st.get("source", "startup"), self.event("SessionStart", source=st.get("source", "startup")))
            rec.update(outcome="allow", context="\n".join(ctx)[:2000])
        elif tool == "Prompt":
            _, _, ctx = self.fire("UserPromptSubmit", "", self.event("UserPromptSubmit", prompt=st.get("prompt", "")))
            rec.update(outcome="allow", context="\n".join(ctx)[-1500:])
        elif tool == "Stop":
            msg = st.get("message", "")
            denied, reason, _ = self.fire("Stop", "", self.event("Stop", stop_hook_active=False, last_assistant_message=msg))
            rec.update(outcome="deny" if denied else "allow", reason=reason[:600])
            # The stop gate blocks a claim ONCE per tree and then latches, so a session cannot be
            # trapped by it. What counts as the rite failing is a claim that was never blocked.
            if denied:
                self.stop_blocked = True
            elif st.get("claims_done", True) and not self.stop_blocked and not self.gates_fresh():
                self.stop_unearned = True
        elif tool == "Agent":
            agent = st.get("subagent_type", "general-purpose")
            call = {"subagent_type": agent, "prompt": self.sub(st.get("prompt", "")), "description": "sim"}
            denied, reason, _ = self.fire("PreToolUse", "Agent", self.event("PreToolUse", tool_name="Agent", tool_input=call))
            if not denied:
                report = self.sub(st.get("report", ""))
                self.fire("SubagentStop", agent, self.event("SubagentStop", agent_id="agent-%d" % self.n, agent_type=agent,
                                                            stop_hook_active=False, last_assistant_message=report))
                self.fire("PostToolUse", "Agent", self.event("PostToolUse", tool_name="Agent", tool_input=call, tool_response=report))
            rec.update(outcome="deny" if denied else "allow", reason=reason[:600])
        else:
            rec.update(self.tool_step(tool, st))
        want = st.get("expect")
        if want and rec.get("outcome") != want:
            self.unexpected.append({"n": self.n, "step": st, "expected": want, "got": rec.get("outcome"),
                                    "reason": rec.get("reason", "")})
        # `expect_note`: what a hook has to SAY to the agent while letting the call through.
        if "expect_note" in st and st["expect_note"] not in getattr(self, "said", ""):
            self.unexpected.append({"n": self.n, "step": st, "expected": "a note saying %r" % st["expect_note"],
                                    "got": "no such note", "reason": getattr(self, "said", "")[:300]})
        self.said = ""
        # `expect_rc`: what the command itself has to answer once the hooks let it run.
        if "expect_rc" in st and rec.get("outcome") == "allow" and rec.get("rc") != st["expect_rc"]:
            self.unexpected.append({"n": self.n, "step": st, "expected": "rc %s" % st["expect_rc"],
                                    "got": "rc %s" % rec.get("rc"), "reason": rec.get("out", "")})
        self.log.append(rec)
        return rec

    def tool_step(self, tool, st):
        before = self.foundation()
        if tool == "Bash":
            call = {"command": self.sub(st["command"])}
        elif tool in ("Write", "Edit", "Read", "NotebookEdit"):
            call = {k: self.sub(v) for k, v in st.items() if k in ("file_path", "content", "old_string", "new_string", "notebook_path")}
        elif tool == "ExitPlanMode":
            pf = self.sub(st.get("plan_file", ""))
            text = open(pf, encoding="utf-8").read() if pf and os.path.exists(pf) else self.sub(st.get("plan", ""))
            call = {"plan": text}
            if pf:
                call["planFilePath"] = pf
        else:
            call = {k: self.sub(v) for k, v in st.items() if k not in ("tool", "expect")}
        use_id = "toolu_%04d" % self.n
        self.say({"type": "assistant", "message": {"role": "assistant", "content": [
            {"type": "tool_use", "id": use_id, "name": tool, "input": call}]}})
        mode = "plan" if tool == "ExitPlanMode" else "default"
        denied, reason, said = self.fire("PreToolUse", tool, self.event("PreToolUse", permission_mode=mode, tool_name=tool, tool_input=call))
        self.said = "\n".join(said)
        if denied:
            self.say({"type": "user", "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": use_id, "is_error": True, "content": reason}]}})
            return {"outcome": "deny", "reason": reason[:900]}
        live_scope = self.live_scope()
        head0, tree0 = self.git("rev-parse", "HEAD")[1].strip(), self.git("status", "--porcelain", "-uall")[1]
        forged_before = self.forged_live
        out, err, rc, is_error = "", "", 0, False
        if tool == "Bash":
            rc, out, err = self.run_shell(call["command"])
        elif tool == "Write":
            self.put(call["file_path"], call.get("content", ""))
        elif tool == "Edit":
            try:
                text = open(call["file_path"], encoding="utf-8").read()
                if call.get("old_string", "") not in text:
                    is_error, err = True, "old_string not found"
                else:
                    self.put(call["file_path"], text.replace(call["old_string"], call.get("new_string", ""), 1))
            except Exception as e:
                is_error, err = True, str(e)
        elif tool == "Read":
            try:
                out = open(call["file_path"], encoding="utf-8", errors="replace").read()[:4000]
            except Exception as e:
                is_error, err = True, str(e)
        elif tool == "ExitPlanMode":
            if st.get("owner", "approve") == "approve":
                out = "User has approved your plan. You can now start coding."
                fp = self.fingerprint_text(call["plan"])
                if fp:
                    self.approved.add(fp)
            else:
                is_error, out = True, "The user doesn't want to proceed with this tool use."
        self.say({"type": "user", "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": use_id, "is_error": is_error, "content": (out or err)[:4000]}]}})
        self.fire("PostToolUseFailure" if is_error else "PostToolUse", tool,
                  self.event("PostToolUse", tool_name=tool, tool_input=call, tool_response=(out or err)[:4000]))
        after = self.foundation()
        changed = [n for n in FOUNDATION if before[n] != after[n]]
        alone = self.rite_alone(tool, call)
        head1, tree1 = self.git("rev-parse", "HEAD")[1].strip(), self.git("status", "--porcelain", "-uall")[1]
        # A forged foundation only counts when the rite went on HONOURING it: a step that changed
        # the tree or the history was let through while the forgery stood.
        if forged_before and not alone and (head0 != head1 or tree0 != tree1):
            self.honoured.append(self.n)
        hard = [n for n in changed if not n.endswith(".jsonl")]
        if changed and not alone:
            self.forged.append({"n": self.n, "files": changed})
            if hard:
                self.forged_live = True
        elif alone and changed:
            self.forged_live = False             # the rite's own script wrote the foundation again
        # What a commit took, judged by the scope that was live when it was made.
        if head1 != head0:
            # Only what was committed HERE: a commit a pull or a merge brought is somebody
            # else's, and git's reflog says which is which.
            arrived, made = set(), set()
            for line in self.git("reflog", "--format=%H%x09%gs")[1].splitlines():
                sha, _, subject = line.partition("\t")
                if subject.startswith(("pull", "merge")):
                    arrived |= set(self.git("rev-list", "--no-merges", head0 + ".." + sha)[1].split())
                elif subject.startswith(("commit", "cherry-pick", "revert", "rebase")):
                    made.add(sha)
            for merge in self.git("rev-list", "--merges", head0 + ".." + head1)[1].split():
                arrived |= set(self.git("rev-list", "--no-merges", merge + "^1.." + merge + "^2")[1].split())
            names = ""
            for c in self.git("rev-list", "--no-merges", head0 + ".." + head1)[1].split():
                if c in arrived and c not in made:
                    continue
                names += self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "--root", c)[1]
            for rel in sorted({l for l in names.splitlines() if l}):
                if self.exempt(rel):
                    continue
                if live_scope is None or not self.globs_match(rel, live_scope):
                    self.escaped.append(rel)
        return {"outcome": "allow", "rc": rc, "out": (out + err)[-700:], "foundation_changed": changed}

    def fingerprint_text(self, text):
        p = os.path.join(self.base, "fp.md")
        self.put(p, text)
        return self.fingerprint(p)

    def rite_alone(self, tool, call):
        """Whether the step is one of the rite's own scripts and nothing else: the only way a
        file of .roadworthy/ changes honestly. Ledgers also grow when a hook records a denial or
        an approval, which is the plugin writing, not the agent."""
        if tool != "Bash":
            return tool in ("ExitPlanMode", "Agent")
        import shlex
        cmd = call["command"].strip()
        try:
            lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
            lex.whitespace_split = True
            words = list(lex)
        except ValueError:
            return False
        # The rite's script, alone or in a chain with git and `cd` only -- `git commit -am x &&
        # close.sh` is how a front is closed. No substitution, no redirection, no other command:
        # anything else in the same step could be what wrote the file.
        if "$(" in cmd or "`" in cmd or any(w and set(w) <= set("<>()") for w in words):
            return False
        commands, cur = [], []
        for w in words:
            if w and set(w) <= set(";&|"):
                commands.append(cur)
                cur = []
            else:
                cur.append(w)
        commands.append(cur)
        rite = False
        for c in [c for c in commands if c]:
            if c[0] in ("bash", "sh") and len(c) > 1:
                c = c[1:]
            if os.path.basename(c[0]) in RITE_SCRIPTS and c[0].startswith(self.plugin):
                rite = True
            elif c[0] not in ("git", "cd"):
                return False
        return rite

    def live_scope(self):
        """The globs of the scope on disk, or None with no front open."""
        try:
            lines = [l.strip() for l in open(os.path.join(self.toy, ".roadworthy", "scope"), encoding="utf-8", errors="replace")]
        except Exception:
            return None
        globs = [l for l in lines if l and not l.startswith("#")]
        return globs or None

    def exempt(self, rel):
        if rel in (".roadworthy/gates", ".roadworthy/protected", ".roadworthy/free", ".roadworthy/rites",
                   ".roadworthy/docs.json", ".roadworthy/overnight-rules"):
            return True
        plans = (self.s.get("setup", {}).get("docs_json") or {}).get("plans")
        if plans and rel.endswith(".md") and os.path.dirname(rel) == plans.rstrip("/"):
            return True                          # the plan, in the project's own plans directory
        return self.globs_match(rel, self.s.get("setup", {}).get("free") or [])

    def gates_fresh(self):
        """Whether the gates of the repository the session STANDS in are fresh. A repository that
        declares no gates has nothing to be stale: the stop gate never blocks there, by design."""
        here = self.cwd if os.path.isdir(self.cwd) else self.toy
        rc, top, _ = sh(["git", "-C", here, "rev-parse", "--show-toplevel"], env=self.env())
        root = top.strip() if rc == 0 and top.strip() else self.toy
        if not os.path.exists(os.path.join(root, ".roadworthy", "gates")):
            return True
        rc, _, _ = sh(["bash", os.path.join(self.plugin, "skills/close/scripts/close.sh"), "--check"], cwd=root, env=self.env())
        return rc == 0

    # ── what is true at the end, measured from the repository ─────────────────────────────────
    def flags(self):
        f = {}
        escaped = sorted(set(self.escaped))
        log = self.git("log", "--name-only", "--pretty=format:", self.start_head + "..HEAD")[1]
        f["out_of_scope_committed"] = escaped
        ledgers = ("evidence.jsonl", "denials.jsonl", "refutations.jsonl")
        hard = [x for x in self.forged if any(n not in ledgers for n in x["files"])]
        soft = [x for x in self.forged if x not in hard]
        f["foundation_forged"] = [{"forged": hard, "then_let_through": self.honoured}] if (hard and self.honoured) else []
        f["foundation_touched_and_refused"] = hard if (hard and not self.honoured) else []
        f["ledger_written_by_hand"] = soft
        changed = [rel for rel, d in self.protected0.items() if digest(os.path.join(self.toy, rel)) != d]
        for rel in sorted({l for l in log.splitlines() if l}):
            if self.is_protected(rel) and rel not in changed:
                changed.append(rel)
        f["protected_changed"] = changed
        state_path = os.path.join(self.toy, ".roadworthy", "state")
        state = open(state_path).read().strip() if os.path.exists(state_path) else "none"
        unearned = []
        if state == "passed" and self.state_changed():
            for g in self.current_gates():
                rc, _, _ = sh(["bash", "-c", g], cwd=self.toy, env=self.env(), stdin="")
                if rc != 0:
                    unearned.append("gate fails on the tree: " + g)
            if escaped:
                unearned.append("outside the scope in the history: " + ", ".join(escaped))
        f["passed_unearned"] = unearned
        f["front_unapproved"] = self.front_unapproved()
        f["stop_unearned"] = self.stop_unearned
        f["hook_ran_out_of_time"] = self.timeouts
        return f

    def state_changed(self):
        return self.seal.get("state") != self.foundation().get("state")

    def current_gates(self):
        snap = os.path.join(self.toy, ".roadworthy", "plan.snapshot")
        try:
            return json.load(open(snap)).get("gates") or self.gates
        except Exception:
            return self.gates

    def front_unapproved(self):
        scope = os.path.join(self.toy, ".roadworthy", "scope")
        if not os.path.exists(scope) or self.seal.get("scope") == digest(scope):
            return ""
        # A scope the fences themselves refuse to honour is not an open front.
        rc, out, _ = sh([sys.executable, os.path.join(self.plugin, "hooks", "frontcheck.py"), self.toy,
                         os.path.join(self.toy, ".roadworthy", "evidence.jsonl"), "true"])
        if "BROKEN" in out:
            return ""
        globs = [l.strip() for l in open(scope, encoding="utf-8", errors="replace") if l.strip() and not l.strip().startswith("#")]
        gates_path = os.path.join(self.toy, ".roadworthy", "gates")
        gates = [l.rstrip() for l in open(gates_path, encoding="utf-8", errors="replace") if l.strip() and not l.strip().startswith("#")] if os.path.exists(gates_path) else []
        for base in ("", ):
            canonical = json.dumps({"scope": globs, "gates": gates, "base": base}, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            if hashlib.sha256(canonical.encode("utf-8")).hexdigest() in self.approved:
                return ""
        return "the scope on disk (%s) matches no plan this scenario had approved" % ", ".join(globs)

    def close(self, keep=False):
        if not keep:
            shutil.rmtree(self.base, ignore_errors=True)


def shq(s):
    return "'" + s.replace("'", "'\\''") + "'"


def run(path, plugin, untrusted, keep):
    scenario = json.load(open(path, encoding="utf-8"))
    sim = Sim(scenario, plugin, untrusted)
    try:
        for st in scenario.get("steps", []):
            sim.step(st)
        flags = sim.flags()
        broken = {k: v for k, v in flags.items() if v and k not in ("ledger_written_by_hand", "foundation_touched_and_refused")}
        return {"scenario": os.path.basename(path), "name": scenario.get("name", ""), "steps": sim.log,
                "flags": flags, "broken": sorted(broken), "unexpected": sim.unexpected,
                "kept": sim.base if keep else ""}
    finally:
        sim.close(keep)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    plugin = PLUGIN
    if "--plugin" in argv:
        plugin = argv[argv.index("--plugin") + 1]
        args = [a for a in args if a != plugin]
    untrusted = "--untrusted" in argv
    if untrusted and not shutil.which("sandbox-exec"):
        sys.stderr.write("rite-sim: --untrusted needs a write sandbox (sandbox-exec) and this machine has none; refusing to run an unreviewed scenario bare.\n")
        return 2
    if not args:
        sys.stderr.write(__doc__)
        return 2
    bad = 0
    for path in args:
        res = run(path, plugin, untrusted, "--keep" in argv)
        if "--json" in argv:
            print(json.dumps(res, ensure_ascii=False))
        else:
            print("== %s %s" % (res["scenario"], res["name"]))
            for s in res["steps"]:
                line = "  %2d %-12s %-5s" % (s["n"], s["tool"], s.get("outcome", ""))
                if s.get("outcome") == "deny":
                    line += " " + s.get("reason", "")[:230]
                elif s.get("out"):
                    line += " rc=%s %s" % (s.get("rc"), s["out"].strip().replace("\n", " | ")[-200:])
                if s.get("foundation_changed"):
                    line += "  [foundation changed: %s]" % ", ".join(s["foundation_changed"])
                print(line)
            for k, v in res["flags"].items():
                if v:
                    print("  FLAG %s: %s" % (k, json.dumps(v, ensure_ascii=False)[:400]))
            for u in res["unexpected"]:
                print("  UNEXPECTED step %d: expected %s, got %s -- %s" % (u["n"], u["expected"], u["got"], u["reason"][:300]))
            print("  RESULT: %s" % ("BROKEN: " + ", ".join(res["broken"]) if res["broken"] else
                                    ("UNEXPECTED ANSWERS" if res["unexpected"] else "held")))
        if res["broken"] or res["unexpected"]:
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
