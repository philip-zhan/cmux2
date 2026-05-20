# Release Fork

Full end-to-end release built locally and published to the personal fork
(`philip-zhan/cmux`). Bumps version, updates changelog, tags, then
builds/signs/notarizes/publishes via `scripts/build-fork-release.sh`.

Unlike `/release-local` (which targets `manaflow-ai/cmux` and needs Apple's restricted
passkey provisioning profile), this signs with the fork's own Developer ID cert,
points Sparkle auto-update at the fork's releases, and publishes the GitHub release to
the fork.

## Steps

### 1. Determine the new version number

- Get the current version from `cmux.xcodeproj/project.pbxproj` (look for `MARKETING_VERSION`)
- Bump the minor version unless the user specifies otherwise (e.g., 0.54.0 → 0.55.0)

### 2. Gather changes since the last release

- Find the most recent git tag: `git describe --tags --abbrev=0`
- Get commits since that tag: `git log --oneline <last-tag>..HEAD --no-merges`
- **Filter for end-user visible changes only** — ignore developer tooling, CI, docs, tests
- Categorize changes into: Added, Changed, Fixed, Removed
- If there are no user-facing changes, ask the user if they still want to release

### 3. Update the changelog

- Add a new section at the top of `CHANGELOG.md` with the new version and today's date
- **Only include changes that affect the end-user experience**
- Write clear, user-facing descriptions (not raw commit messages)
- The docs changelog page (`web/app/docs/changelog/page.tsx`) is rendered from `CHANGELOG.md`

### 4. Bump the version

- Run: `./scripts/bump-version.sh` (bumps minor by default)
- This updates both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (build number).
  The build number is auto-incremented and is required for Sparkle auto-update to work.

### 5. Commit, run the pre-tag guard, then tag and push

- Stage: `CHANGELOG.md`, `cmux.xcodeproj/project.pbxproj`
- Commit message: `Bump version to X.Y.Z`
- Run: `./scripts/release-pretag-guard.sh`
- If it fails, run `./scripts/bump-version.sh`, commit the build-number bump, and rerun the guard
- Create tag: `git tag vX.Y.Z`
- Push: `git push origin <branch> && git push origin vX.Y.Z`

### 6. Build, sign, notarize, and publish to the fork

```bash
set -a; source ~/.secrets/cmux-fork.env; set +a
./scripts/build-fork-release.sh vX.Y.Z
```

This script handles: prebuilt GhosttyKit download, universal Release xcodebuild,
Sparkle key injection + fork feed URL, codesigning, notarization (app + DMG), appcast
generation, GitHub release publish/upload on the fork, and cleanup.

If the script fails, run `say "cmux fork release failed"`.

### 7. Verify

- Confirm the release appears at `https://github.com/philip-zhan/cmux/releases/tag/vX.Y.Z`
- Check that `cmux-macos.dmg` and `appcast.xml` are attached to the release
- On success, run `say "cmux fork release complete"`

## Environment

Required env, loaded from `~/.secrets/cmux-fork.env`:

- `APPLE_ID` — Apple ID email for notarization
- `APPLE_TEAM_ID` — Developer team ID (e.g. `D22PZDCXY5`)
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for `notarytool`
- `SPARKLE_PRIVATE_KEY` — base64 Sparkle EdDSA private key

Optional env:

- `CMUX_FORK_REPO` — GitHub repo to publish to (default: `philip-zhan/cmux`)
- `CMUX_FORK_SIGN_IDENTITY` — codesign identity (default: the fork's Developer ID Application cert)

First-time Sparkle key setup:

```bash
SPARKLE_ENV_FILE=~/.secrets/cmux-fork.env ./scripts/sparkle_generate_keys.sh
```

## Changelog Guidelines

**Include only end-user visible changes:**
- New features users can see or interact with
- Bug fixes users would notice (crashes, UI glitches, incorrect behavior)
- Performance improvements users would feel
- UI/UX changes
- Breaking changes or removed features

**Exclude internal/developer changes:**
- Setup scripts, build scripts, reload scripts
- CI/workflow changes
- Documentation updates (README, CONTRIBUTING, CLAUDE.md)
- Test additions or fixes
- Internal refactoring with no user-visible effect
- Dependency updates (unless they fix a user-facing bug)

**Writing style:**
- Use present tense ("Add feature" not "Added feature")
- Group by category: Added, Changed, Fixed, Removed
- Be concise but descriptive
- Focus on what the user experiences, not how it was implemented
