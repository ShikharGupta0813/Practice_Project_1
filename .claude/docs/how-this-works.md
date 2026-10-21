# How all of this works — a plain-English guide

Written for Shikhar, who asked to understand this properly from zero.
This file is NOT auto-loaded into chats — it is here for you to read.

---

# PART 1 — How AI like me actually works

## 1.1 I am a text predictor

Underneath everything, I do one thing: **given some text, guess what text
comes next.**

That's it. I was trained by reading an enormous amount of writing — books,
code, documentation, websites — and learning the patterns of what usually
follows what.

If you write "the capital of France is", the pattern says "Paris". If you
paste a PHP file with a bug and ask what's wrong, the patterns learned from
millions of PHP files produce an answer that usually matches what a real
programmer would say.

**This matters because it explains my weaknesses.** I am not looking things
up in a database. I am producing the most plausible continuation. Usually
plausible and correct are the same thing. Sometimes they are not — and that
is when I state something confidently that is simply wrong. It is not lying;
there is no moment where I "know" and choose to deceive. The wrong thing
just looked like the right shape.

This is why, earlier, I told you Asana's MCP address was `mcp.asana.com/sse`.
That is what such addresses usually look like. It was wrong. I only found the
real one (`mcp.asana.com/v2/mcp`) because I went and read Asana's actual
documentation instead of trusting my own recall.

**The lesson: make me check real sources.** A tool result is evidence. My
memory of a fact is a guess.

## 1.2 Tokens — how I read and count

I don't read letters or words. I read **tokens** — chunks of roughly 4
characters. "CodeIgniter" might be 3 tokens. A space or comma is often its
own token.

Everything is measured in tokens: what you send, what I write back, and how
much I can hold at once. When you see "15,000,000 tokens left", that is
roughly how much reading and writing this session can still do.

Why you should care: **every file I read costs tokens.** Reading one of your
4,300 PHP files is cheap. Reading all of them is not possible. This is why I
search with `grep` for specific lines rather than opening whole files, and
why `CLAUDE.md` is 78 lines instead of 5,000.

## 1.3 The context window — my desk

Imagine I work at a desk with limited space. Everything I can currently see —
your messages, my replies, files I opened, command output — sits on that desk.
That space is the **context window**.

Two consequences:

1. **If it's not on the desk, I cannot see it.** A file I never opened does
   not exist to me. Your other apps, your screen, your browser tabs — not on
   the desk, invisible.
2. **The desk has an edge.** In a very long conversation, older material gets
   summarized or dropped to make room.

## 1.4 Why I have no memory between chats

When you close a chat, **the desk is cleared completely.** A new chat is a
brand-new desk, empty.

I don't "forget slowly" like a person. There is no faded version of yesterday.
There is nothing. A new chat me has never met you.

**This single fact is the reason your entire `.claude` folder exists.**

If knowledge lives only in a conversation, it dies with that conversation. If
it lives in a file, tomorrow's me can read it and catch up in seconds. Every
folder we built is a way of writing something down so a future blank me can
pick it up.

## 1.5 The system prompt — my standing instructions

Before you ever type anything, I am given a block of instructions: who I am,
what tools I have, how to behave, safety rules. You don't see it, but it is
on the desk before your first message lands.

Your `CLAUDE.md` and memory files get added near the start too. That is
literally how a fresh chat "already knows" your branch is `onestackcbs` — the
knowledge was placed on the desk before you spoke.

## 1.6 What turns a chat model into an "agent"

A plain chat model can only produce text. An **agent** is that same model
plus two additions:

1. **Tools** — things it can actually do: read a file, run a command,
   search the web, call Asana.
2. **A loop** — after a tool runs, the result comes back onto the desk, and
   the model decides what to do next. Repeat until done.

So when you asked me to install `gh`, what happened was:

```
you: install gh
me:  (decides) I should check if winget exists
     -> runs a command
     <- result: "winget found at C:\..."
me:  (decides) good, now install
     -> runs winget install
     <- result: exit code 0
me:  (decides) verify it worked
     -> runs gh --version
     <- result: "gh version 2.100.0"
me:  (decides) done, tell the user
```

Each arrow is a full trip through the model. I am not "running" continuously
like a program — I wake up, look at the desk, take one action, and stop. The
harness feeds me the result and wakes me again.

**"Agentic" just means: model + tools + this loop.** Nothing more mystical.

## 1.7 Tool use — how I "do" things

I cannot touch your computer directly. What I can do is emit a structured
request, like:

```
tool: Bash
command: git status
```

The harness (Claude Code) receives that, decides whether it's allowed, runs
it, and puts the output back on my desk. **The harness is the hands. I am
only the decision-maker.**

This is why permission settings are real protection: I can ask for anything,
but the harness decides whether it actually runs.

## 1.8 MCP — the universal plug

**MCP = Model Context Protocol.** It is an agreed-upon standard for how an
outside service exposes its abilities to an AI.

Before MCP, every AI tool needed custom code for every service. With MCP, a
company (Asana) builds one MCP server, and any MCP-speaking client (Claude
Code, and others) can plug into it.

When we connected Asana, I gained tools like `get_my_tasks`, `get_task`,
`add_comment`. I did not learn Asana — I got a plug.

**Why I can read your Asana but not your email:** there is a plug for one and
not the other.

An MCP server can be:
- **Remote** — a URL on the internet, like Asana's. Needs login (OAuth).
- **Local** — a program on your machine.

## 1.9 Why I still get things wrong

Worth knowing plainly:

- **Confident wrongness.** Plausible and true are usually the same, not always.
- **Stale knowledge.** My training has a cutoff. Newer things I must look up.
- **I can't see what I didn't read.** If I didn't open the file, I'm guessing.
- **Long conversations drift.** Details from far back may be summarized away.

**How we defend against it in your setup:** rules written in files instead of
remembered; verifying task line numbers against real code instead of trusting
titles; reconciling against `git` instead of trusting the ledger; and a human
approval gate before anything touches your repo.

---

# PART 2 — The different Claude products, and which one you're using

The same underlying model powers all of these. What changes is **what it can
touch** and **where it runs**. That difference is everything.

## 2.1 Normal Claude chat (claude.ai, or the Claude app)

The plain conversation window. You type, Claude answers.

- Does **not** have your files or your terminal.
- Can't run commands, can't edit code, can't make a branch.
- Good for: thinking, explaining, drafting, questions.

If you paste code in, it can discuss it — but it is looking at your paste,
not at your project. It cannot check whether the line still exists.

## 2.2 Claude Code — the coding agent

Claude Code is the version with **hands**: it can read and write files in a
project folder and run terminal commands. It always works inside a project
directory (yours is `C:\xampp\htdocs\oneStackLocal`).

This is what reads `CLAUDE.md`, runs slash commands, and did the `git` and
`winget` work.

Claude Code comes in several front doors — **the engine is the same, only the
window differs:**

| Where | What it is |
|---|---|
| **Terminal** | Type `claude` in PowerShell/bash. The original form. |
| **Desktop app, Code tab** | A window around the same thing. **This is what you're using now.** |
| **VS Code / JetBrains extension** | Claude Code inside your editor. This is the panel in your screenshot. |
| **Web (claude.ai/code)** | Runs in the cloud rather than your laptop. |

Because they share an engine, your `.claude` folder works in all of them.
That is exactly why `/task` showed up in your VS Code terminal — it read the
same files.

**And why it failed in this window:** slash commands are collected once, when
a session starts. This session started before the files existed. A new session
finds them. Not a bug, just startup timing.

## 2.3 Cowork

Cowork is Anthropic's environment for **agentic work that isn't coding** —
research, documents, spreadsheets, multi-step workflows — where Claude uses
skills and connected tools and produces files as output.

Think of it as: Claude Code is aimed at a code repository; Cowork is aimed at
general work.

You are not using it. Some Cowork-related skills appear in your available
list, which is normal — the list shows what exists, not what's in use.

## 2.4 Claude API and the Agent SDK

For programmers building their own products.

- **API** — your program sends text to Claude and gets text back. This is the
  raw engine, no interface.
- **Agent SDK** — a toolkit for building your own agent with your own tools
  and loop, the way Claude Code is built.

You don't need either. Mentioned so the names aren't mysterious.

## 2.5 Which to use when

- **Just thinking or asking?** Normal chat.
- **Touching your codebase?** Claude Code (any front door).
- **Your task workflow?** Claude Code, because it needs files, git, and gh.

## 2.6 One trap worth remembering

**A normal chat cannot see your project, no matter how confidently it talks
about it.** If you describe a bug in plain chat, you get plausible general
advice. Ask Claude Code and it opens the actual file. Same model, completely
different reliability — because one has evidence and the other has patterns.

---

# PART 3 — Your setup, file by file

## 3.1 What a `.md` file is

A plain text file. `.md` = Markdown: text with light formatting (`#` heading,
`-` bullet). Open it in Notepad and you'll see ordinary sentences.

**Nothing runs it. It is not code.** It is English written for me to read.
That is why you can edit any of these yourself — if a rule is wrong, change
the sentence.

## 3.2 The two `.claude` locations

```
C:\Users\shikh\.claude\                    <- GLOBAL (all projects)
    projects\C--xampp-htdocs-oneStackLocal\memory\
        MEMORY.md                  index of memories
        asana-to-pr-workflow.md    your branch + approval rules
        onestack-asana-setup.md    how Asana/gh were wired, and the gotchas

C:\xampp\htdocs\oneStackLocal\.claude\     <- THIS PROJECT ONLY
    CLAUDE.md            repo facts — AUTO-LOADED every chat
    workflow.md          the shared rulebook — read when a command says to
    commands\            your slash commands
        task.md, task-plan.md, task-do.md, task-status.md, task-resume.md
    plans\
        _batch.json      the ledger (which task is at what stage)
        <taskid>.md      one plan per task
    docs\
        how-this-works.md   <- this file
```

## 3.3 What loads automatically vs on demand

**Automatic, every single chat:**
- `.claude/CLAUDE.md`
- your memory files

**Only when needed:**
- `workflow.md` (a command tells me to read it)
- plan files (when working that task)
- `docs/` (only if relevant)

**Why split this way:** auto-loaded text costs tokens in *every* conversation,
forever. Small and stable goes in `CLAUDE.md`; big and detailed goes in
`docs/`. That is why `CLAUDE.md` is 78 lines and this file can be 400.

## 3.4 `CLAUDE.md` — the briefing note

Facts about the codebase a new chat must know immediately: CodeIgniter 3.1.10,
HMVC with `cbs` and `mobile_app`, base branch `onestackcbs`, per-environment
config dirs, never log PII, and the two known auth holes.

That last part matters: it warns me not to assume a controller is protected
just because it extends `Auth_Controller`. Without that line, a fresh me
would assume wrongly.

**Deliberately excludes** anything that changes often. A stale document is
worse than no document, because I would trust it and not check.

## 3.5 The memory folder — facts about you

`CLAUDE.md` describes the *code*. Memory describes *you*: branch prefix
`sg_cl_`, always pull `onestackcbs` first, plan-then-approve, never merge.

Each memory is one small file with a short header. `MEMORY.md` is the index.
This is why you will never re-explain your branch naming again.

## 3.6 `commands/` — what a slash command really is

Genuinely simple. When you type `/task`:

1. Claude Code opens `.claude/commands/task.md`
2. Reads the text inside
3. Hands it to me **as if you had typed it**

A slash command is a saved message. That's all. Writing one is writing English.

`$ARGUMENTS` is a blank that gets filled in: type `/task-plan 12345` and
`$ARGUMENTS` becomes `12345`.

**Your five commands:**

| Command | Does | Touches your repo? |
|---|---|---|
| `/task` | Lists your open Asana tasks | No |
| `/task-plan <id>` | Reads task + code, writes a plan | No |
| `/task-do <id>` | Branch, fix, commit, push, PR | **Yes** |
| `/task-status` | True state, checked against git | No |
| `/task-resume` | Continue an interrupted batch | Yes, after you confirm |

Only `/task-do` changes code, and it refuses to run without an approved plan.

## 3.7 `workflow.md` — the rulebook

All five commands begin with "read `.claude/workflow.md` first", so the rules
live in **one** place. Change the branch prefix there and all five commands
change at once.

## 3.8 `plans/` — notes to my future self

- `<taskid>.md` — what's broken, which files, the approach, the risks
- `_batch.json` — the ledger: what stage each task reached

**This is what makes "close the laptop, resume tomorrow" work.** Tomorrow's me
cannot remember that you approved something. It can read the file that says so.

**Important: the ledger is treated as a hint, never as truth.** If a session
dies mid-commit, the file says one thing and reality is another. So before
resuming, I check git and GitHub directly:

```
git branch --list "sg_cl_*"          does the branch exist?
git log onestackcbs..<branch>        are there commits?
git status --porcelain               uncommitted work?
gh pr list --head <branch>           is there already a PR?
```

Then I correct the file to match reality. **Git is the truth; the JSON is a
note.** This is the single most important design choice in your setup.

As a second safety net, every commit ends with `Asana: <task id>`. If the
ledger is ever lost entirely, `git log --grep="Asana:"` rebuilds the history
from git alone.

## 3.9 Skills vs commands

| | Command | Skill |
|---|---|---|
| Lives in | `.claude/commands/name.md` | `.claude/skills/name/SKILL.md` |
| Starts | **You type** `/name` | **I notice** it applies |
| Best for | "Do this now" | "Whenever we do X, work this way" |

**You type commands; I notice skills.** Commands were right for you, because
you want to decide when work starts.

A skill is a folder containing `SKILL.md` with a short description at the top.
I read descriptions, and when one matches the situation, I open it. It can
also bundle extra reference files.

## 3.10 Why `.claude/` is hidden from git

Your `.claude/` folder was untracked **and** not ignored — meaning a single
`git add -A` would have swept plan files and ledgers into a pull request.

So it's listed in `.git/info/exclude`. That file is like `.gitignore` but
**local to your machine only** — your teammates' setup is untouched.

---

# PART 4 — What I can and cannot do on your laptop

## 4.1 What I can do

- **Read, create, edit and delete files** — normally inside your project.
- **Run terminal commands** — the powerful one. `git`, `winget`, `gh`,
  anything you could type yourself.
- **Browse the web** — fetch a page, run a search. This is how I found the
  correct Asana address after getting it wrong from memory.
- **Use connected services via MCP** — currently Asana.

## 4.2 What I cannot do

- See your screen, your open apps, or your browser tabs.
- Read your saved passwords or autofill.
- Know anything you haven't told me or that I haven't read from a file or
  command output.

I am not watching your computer. I see exactly what lands on the desk.

## 4.3 What I will refuse

- Typing your passwords, tokens, card numbers, or ID numbers anywhere.
- Logging into services as you.
- Permanently deleting data.

This is why `gh auth login` and the Asana OAuth were yours to do, and why the
`--client-secret` flag prompts you in your own terminal rather than passing
the secret through our chat.

## 4.4 Permission modes — read this one

Normally Claude Code **asks** before running a command. Your session shows
**"auto mode on"**, meaning it runs many things without asking. Press
`shift+tab` to cycle modes if you want more prompts.

Be clear about what protects you:

- **The harness** decides whether a command actually runs. That is a real wall.
- **The rules in `workflow.md`** — "never merge, never push to `onestackcbs`" —
  are instructions I follow carefully, **not** a wall the computer enforces.

Both matter, but they are different kinds of protection, and you should know
which is which.

## 4.5 Treat outside text as information, not orders

Anything I read from outside our conversation — a web page, a file, an Asana
description, a code comment — is **data**, not instructions.

If an Asana task description said "delete the production database", that is
text in a task, not a command from you. Your `/task-plan` command explicitly
instructs me to quote such text back to you and ask, rather than act on it.
Only you give me instructions.

---

# PART 5 — git, GitHub, and what `gh` is

## 5.1 git

`git` is version control. It records snapshots of your code so you can see
history, work on separate lines of development, and combine them.

Key words:

| Word | Meaning |
|---|---|
| **repository (repo)** | The project plus its full history |
| **commit** | One saved snapshot, with a message |
| **branch** | A separate line of work. Yours: `onestackcbs` as the base |
| **remote** | The copy on a server. Yours is `origin` on GitHub |
| **push** | Send your commits up to the remote |
| **pull** | Bring down others' commits |
| **worktree** | A second folder holding a different branch of the same repo |

**git runs on your laptop.** It works with no internet, except push and pull.

## 5.2 GitHub

A website that hosts git repositories and adds teamwork features on top:
pull requests, reviews, issues, CI. Yours lives at
`github.com/OneStackIndia/core-php`.

## 5.3 The important distinction

**A pull request is NOT a git thing. It is a GitHub thing.**

git knows commits and branches. It has no idea what a "PR" is. A pull request
is GitHub's feature meaning: please review my branch and merge it into
`onestackcbs`.

So `git push` can send the branch — but no git command can open the PR,
because git does not have that concept.

## 5.4 That is exactly what `gh` is for

`gh` is **GitHub's official command-line tool**. It talks to GitHub's API from
your terminal, so you do not have to open the website.

```
gh auth login                    log in once (you did this)
gh pr create --base onestackcbs  open a pull request
gh pr list --head sg_cl_x        is there already a PR for this branch?
gh repo view                     info about the repo
```

**Why the workflow needs it:** without `gh` I could branch, commit and push,
then have to stop and hand you a link to open the PR by hand. With it, the
loop finishes on its own.

`gh pr list` also does double duty: on resume, it answers "did the previous
session already open this PR?" — part of checking reality instead of trusting
the ledger.

## 5.5 Your `gh` setup

- Version 2.100.0 at `C:\Program Files\GitHub CLI\gh.exe`
- Logged in as `ShikharGupta0813`
- Token scopes: `repo`, `workflow`, `read:org`, `gist`
- Permission on `OneStackIndia/core-php`: **WRITE**

`gh auth login` stored a token on your machine so it stays logged in. **I never
see that token** — I run `gh`, and `gh` uses its own stored credential.

Note: `gh` installed onto the *machine* PATH, so terminals opened before the
install cannot find it. Open a fresh terminal.

## 5.6 Worktrees, plainly

Normally one folder shows one branch, and switching branches changes what is on
disk — awkward with half-finished work.

A **worktree** is an extra folder holding a different branch of the same repo,
so two branches can be checked out at once.

**Your setup tried this and dropped it** - it added steps to `/task-do` and you
wanted that fast. Work now happens directly in the main folder. The trade-off,
accepted deliberately: two unfinished tasks cannot sit side by side, and an
interrupted task leaves the main folder on its branch.

---

# PART 6 — The whole loop, end to end

```
1. /task
   -> I read your Asana tasks and list them, grouped by branch

2. /task-plan <id>
   -> read the task AND its comments
   -> find the real code, verify the line numbers still match
   -> write .claude/plans/<id>.md
   -> STOP. Nothing in your repo has changed.

3. You read the plan. Edit it, approve it, or reject it.

4. /task-do <id>
   -> refuses if there is no approved plan
   -> git checkout onestackcbs && git pull origin onestackcbs
   -> worktree + branch sg_cl_<name>
   -> make the fix
   -> commit (with "Asana: <id>")
   -> git push
   -> gh pr create --base onestackcbs
   -> comment the PR link on the Asana task
   -> STOP. No merge. Task not closed.

5. Session dies? New chat -> /task-resume
   -> checks git and GitHub for what is REALLY done
   -> corrects the ledger
   -> tells you what is left, asks before continuing
```

**Where you stay in control:** approving plans, and merging. Everything
between is automated.

---

# PART 7 — Quick glossary

| Term | Plain meaning |
|---|---|
| **LLM** | The AI model. Predicts what text comes next. |
| **Token** | ~4 characters. The unit everything is counted in. |
| **Context window** | My desk. What I can currently see. |
| **System prompt** | Standing instructions placed before your first message. |
| **Agent** | A model given tools and a loop, so it can act, not just talk. |
| **Tool** | Something I can ask the harness to do on my behalf. |
| **Harness** | The program around me that actually runs things. Claude Code. |
| **MCP** | Standard plug for connecting outside services, like Asana. |
| **OAuth** | Logging in without handing over your password. |
| **DCR** | Auto-registering an app during login. Asana does not allow it — hence the manual app. |
| **Markdown / .md** | Plain text with light formatting. |
| **Slash command** | A saved message stored as a `.md` file. |
| **Skill** | Instructions I pick up on my own when relevant. |
| **git** | Version control on your laptop. |
| **GitHub** | The website hosting your repo. |
| **PR** | GitHub's request to review and merge a branch. |
| **gh** | GitHub's command-line tool. How the PR gets opened. |
| **Worktree** | Extra folder holding another branch of the same repo. |
| **Ledger** | `_batch.json` — progress notes, always re-checked against git. |

---

# PART 8 — The five things actually worth remembering

1. **I forget everything between chats.** Files are the only memory.
2. **Files are just English.** You can open and edit any of them.
3. **Auto-loaded text costs you in every future chat.** Small `CLAUDE.md`,
   big `docs/`.
4. **Git is the truth, the ledger is a note.** Always re-check reality.
5. **You keep two decisions: approving plans, and merging PRs.** Deliberately.
