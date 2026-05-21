# Run Local

Build the Debug app with `scripts/reload.sh` and launch it as an isolated tagged instance so it runs side-by-side with the user's main app.

## Steps

### 1. Choose a tag

- Default to a slug derived from the current git branch: `git rev-parse --abbrev-ref HEAD`
- If the branch is `main` (or detached), use a short descriptive slug for the work in progress instead
- The user may pass an explicit tag as an argument — if so, use that

### 2. Clean up stale tags from this session

- Before launching a new tagged run, quit any older tagged apps you started earlier and remove their `/tmp` socket / derived data
- `reload.sh` prints a "Tag cleanup status" section in its log with the exact cleanup commands

### 3. Build and launch

```bash
./scripts/reload.sh --tag <slug> --launch
```

- This builds the Debug app, terminates any running app with the same tag, and opens the freshly built binary
- Never run bare `xcodebuild` or `open` an untagged `cmux DEV.app` — untagged builds share the default socket and bundle id with other agents

### 4. Give the user a cmd-clickable app link

- Grab the path from the `App path:` line in the `reload.sh` output
- Prepend `file://` and URL-encode spaces as `%20` (do not hardcode any part of the path)
- Output it as a markdown link wrapped in separators:

```markdown
=======================================================
[cmux DEV <slug>.app](file:///Users/.../Debug/cmux%20DEV%20<slug>.app)
=======================================================
```

- Never use `/tmp/cmux-<tag>/...` paths in chat output

## Notes

- Pass no `--launch` if the user only wants a build (the script prints the path so they can cmd-click it themselves)
- For a build-only compile check, use a tagged derived data path:
  `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-<tag> build`
- Tagged Debug log lives at `/tmp/cmux-debug-<slug>.log`; `reload.sh` writes the current path to `/tmp/cmux-last-debug-log-path`
