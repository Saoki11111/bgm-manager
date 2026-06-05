# GitHub PR Workflow

This repository is intended to use PR-based changes only.

## Rules

- Do not commit directly to `main`.
- Do not push directly to `origin/main`.
- Open a pull request for every change.
- CI must pass before merging.
- Add the `automerge` label to a PR when it should merge automatically after CI passes.

## Required GitHub settings

Set these on GitHub:

1. Open `Settings` > `General`.
2. Enable `Allow auto-merge`.
3. Open `Settings` > `Rules` > `Rulesets`.
4. Create a ruleset for branch name pattern `main`.
5. Enable these rules:
   - Require a pull request before merging.
   - Require status checks to pass.
   - Require branch to be up to date before merging.
   - Block force pushes.
   - Restrict deletions.
6. Add required status check `Build macOS app`.

With this setup, direct pushes to `main` are rejected, CI runs on PRs, and PRs labeled `automerge` are merged automatically when the required checks pass.

Note: GitHub may require GitHub Pro or a public repository to use rulesets or branch protection on private repositories. If the settings are unavailable while the repository is private, make the repository public first or use a plan that supports private-repository rules.
