---
name: second-opinion
description: Get a black-box product review of a running web app from the other coding agent (Codex reviews Claude Code's work, Claude Code reviews Codex's), fix what it finds, and repeat until two reviews in a row clear the bar. Use when the user asks for a second opinion, a cross-review, an independent or outside review, "have Codex/Claude look at this", or wants to know whether a user-facing web feature is really done.
---

# Second opinion

You built something. Now a different model uses it the way a stranger would, with no access
to the code, and tells you what's wrong. You fix the worst of it and ask again.

## Before the first review

1. **Get the app running** and note its URL: a local dev server (`http://localhost:5173`) or a
   deployed preview. The reviewer opens this URL in a browser, so it must load on this machine.
2. **Write a short brief** (2–4 sentences): what the app is, who it's for, and what to focus on
   this round. Describe the product the way you'd describe it to a tester. Don't describe the
   code and don't defend design choices.
3. Pick the reviewer: **the other agent**. If you're Claude Code, it's `codex`; if you're
   Codex, it's `claude`. The script picks this automatically from its environment; pass
   `--reviewer` only if you need to override that.

## Run a review

```bash
bash <this skill's folder>/scripts/review.sh --url <URL> --brief "<brief>"
```

It takes 3–10 minutes. Use a long timeout (15 minutes) or run it in the background and wait.
The script:

- gives the reviewer an empty folder containing only the review instructions, the URL and
  your brief, plus the previous review if there is one, so it can check what you fixed;
- saves the review to `.second-opinion/review-NN.md`, the scores to `scores-NN.json` and
  screenshots to `shots-NN/` in the current directory;
- prints the review and a verdict: `KEEP GOING` or `DONE`.

**The bar:** a round passes when *Works*, *Usefulness* and *Polish* are all 7 or higher and
the reviewer found no blocking bugs. The verdict is `DONE` when two rounds in a row pass.
Pass `--bar 8` for a stricter bar.

## Between reviews

1. Read the whole review, then look at the screenshots it mentions.
2. Fix the **blocking bugs**, then the **top problems** in order. Reproduce each one before
   fixing it. If you think a finding is wrong, say why to the user. Don't silently skip it.
3. Don't fix the review: never edit the reviewer's instructions, the scores or old reviews to
   change the outcome.
4. Run the next review.

Stop after **3 rounds** unless the user asked for more. Each round uses the reviewer's quota.

## Report to the user

Finish with a short scoreboard across rounds and what changed between them:

| Round | Works | Usefulness | Polish | Wow | Blocking bugs |
|---|---|---|---|---|---|

Then list the problems still open and the final verdict. If the reviewer couldn't run (CLI
missing, not logged in, quota used up), say so plainly instead of reviewing your own work.
