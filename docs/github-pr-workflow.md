# GitHub PR Workflow

This repository is intended to use PR-based changes only.

## Rules

- Do not commit directly to `main`.
- Do not push directly to `origin/main`.
- Open a pull request for every change.
- CI must pass before merging.
- Add the `automerge` label to a PR when it should merge automatically after CI passes.

## Local Branch Flow

For normal work:

```sh
git switch -c feature/name
# edit files
./scripts/check.sh
git add ...
git commit -m "..."
git push -u origin feature/name
gh pr create
```

Do not merge locally. Ask the AI or run the explicit merge flow only when the PR should be merged.

## Merge Flow

When a PR should be merged:

1. Confirm the PR number and CI status.
2. Squash merge the PR.
3. Switch local checkout to `main`.
4. Pull `origin/main`.
5. Delete the merged local branch.
6. Prune remote tracking branches.
7. Confirm `git status --short --branch` and `git branch -a`.

This repository includes a helper:

```sh
./scripts/merge-pr.sh <pr-number>
```

Example:

```sh
./scripts/merge-pr.sh 3
```

## What CI Checks

The CI workflow runs `./scripts/check.sh` on GitHub-hosted macOS.

It checks:

- shell script syntax with `bash -n`
- README/App feature contract with `scripts/check-docs.sh`
- macOS app build with `macos/BGMManager/build.sh`
- ad-hoc signature validity with `codesign --verify`

Run the same checks locally before pushing:

```sh
./scripts/check.sh
```

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
