# second-opinion

**Your coding agent shouldn't grade its own homework.**

A skill for Claude Code and OpenAI Codex. When your agent finishes a web feature, it hands
the running app to the *other* agent, which uses it in a real browser like a first-time
visitor, with no access to the code. It scores the app, lists what's broken, and your agent
fixes it and asks again. It stops when two reviews in a row clear the bar.

```
  Claude Code builds  ──►  Codex uses the live app  ──►  scores + top problems
        ▲                                                       │
        └──────────────── fixes the worst of it ◄───────────────┘
                 (stops when 2 rounds in a row score 7+)
```

Code review tools read the diff. This one checks whether the **product** works.

## Why

This comes from [agent-garage](https://github.com/ramzyraz/agent-garage), where Claude Code
and Codex built five web apps on their own over 26 sessions. After every session, the other
company's model reviewed the live site. It was the most useful part of the whole setup,
because the two models catch very different things:

> "The green checks overstate how much has been reviewed."
> Codex, reviewing Claude's work

> "I had no sound, so the 'hear it' hook was a silent caption box."
> Claude, reviewing Codex's work

Builders also tend to declare victory early. A fixed bar from someone else keeps them honest.

## Install

You need both CLIs installed and logged in (`claude` and `codex`), plus `python3`, Node.js
(`npm`) and Google Chrome or Chromium for the reviewer's browser.

```bash
# Claude Code
git clone https://github.com/ramzyraz/second-opinion ~/.claude/skills/second-opinion

# Codex
git clone https://github.com/ramzyraz/second-opinion ~/.codex/skills/second-opinion
```

Install it in both if you switch between them. It always calls the other agent.

## Use

Start your app, then ask your agent:

```
Get a second opinion on the checkout page at http://localhost:5173
```

The agent writes a short brief, runs the review, fixes what comes back and repeats, up to 3
rounds. Each round saves `review-NN.md`, `scores-NN.json` and screenshots to
`.second-opinion/` in your project, and ends with a scoreboard:

```
Round  first impression  works  usefulness  polish  wow  blocking bugs  pass
    1                 8      5           7       6    6              1  no
    2                 8      8           8       7    6              0  yes
    3                 8      8           8       8    7              0  yes
VERDICT: DONE (two rounds in a row at 7+ with no blocking bugs)
```

You can also run a single review yourself:

```bash
bash ~/.claude/skills/second-opinion/scripts/review.sh \
  --url http://localhost:5173 \
  --brief "A trip cost splitter for groups. Focus on adding expenses on a phone."
```

| Option | Default | |
|---|---|---|
| `--reviewer` | the other agent | `codex` or `claude` |
| `--bar` | `7` | minimum for Works, Usefulness and Polish |
| `--out` | `.second-opinion` | where reviews are saved |
| `SECOND_OPINION_MODEL` | CLI default | model the reviewer uses |
| `SECOND_OPINION_FULL_ACCESS=1` | off | run Codex without its sandbox (only if a review can't work otherwise) |

## How it stays independent

- The reviewer runs in an empty temporary folder. It sees the URL, your agent's short brief
  and the review instructions ([REVIEWER.md](REVIEWER.md)), never the code or the chat.
- From round 2 it also gets the previous review, so it can check what was fixed.
- The script starts a headless Chrome itself and the reviewer drives it with puppeteer-core,
  so Codex can stay inside its workspace sandbox (which can't launch Chrome on macOS).
  Claude reviews with a limited tool list.
- If the reviewer couldn't use a real browser, the round never counts as a pass.
- The verdict is calculated from `scores.json` by the script, not by the builder.

## Limits

- Web apps only, reachable from your machine (a local dev server or a deployed preview).
- Each round takes 3–10 minutes and uses the reviewer's quota.
- A reviewer is still a model: it can be wrong. The builder is told to push back with
  reasons rather than skip a finding silently.

MIT licence.
