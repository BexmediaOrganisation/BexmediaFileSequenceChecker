# Contributing / Maintaining

Internal notes for Bexmedia staff who maintain this tool.

## Repository layout

| File | Purpose |
|------|---------|
| `BexmediaFileSequenceChecker_Win.ps1` | Windows script (PowerShell) |
| `BexmediaFileSequenceChecker_Mac.command` | Mac script (bash + awk) |
| `HOW-TO-USE.txt` | Plain-English guide, bundled into the release zip |
| `README.md` | Main documentation |
| `.github/workflows/release.yml` | Builds the release zip on a self-hosted runner |

Both scripts implement the **same** behaviour and should be kept in sync:

- Ask for a folder to scan (drag-and-drop friendly).
- Check the sequence FIRST. Only if gaps are found: offer to save a report
  (default location = the scanned folder; ask "save somewhere else? (Y/N)" and
  only prompt for a folder if Y). A complete sequence writes nothing and never
  prompts.
- On screen, draw the whole sequence with present numbers green and missing
  numbers red (ANSI colours in bash / `Write-Host -ForegroundColor` in PS).
- On save, write BOTH `MissingFiles_<stamp>.txt` (plain) and
  `MissingFiles_<stamp>.html` (colour-coded green/red chips with a "Show
  missing only" filter button; self-contained, no external assets). In the Mac
  script the HTML is built in bash from `SEQ\t...` lines the awk emits to
  stdout; keep those lines out of the `.txt`.
- Scan **every** file type.
- Auto-detect the sequence number: reduce each name to a "shape" by replacing
  digit-runs with `#`, group by shape, and pick the digit slot that **varies**
  the most across the group. This ignores dates and fixed indices like `M01`.
- Report gaps as a collapsed summary + a full reconstructed filename list, and
  save a `MissingFiles_<timestamp>.txt` report.

## Testing locally

Create a folder with a deliberate gap and run each script against it.

Windows:

```powershell
.\BexmediaFileSequenceChecker_Win.ps1 -Path "C:\some\test\folder" -OutFolder "C:\temp"
```

Mac:

```bash
./BexmediaFileSequenceChecker_Mac.command "/path/to/test/folder" "/path/to/output"
```

Good cases to cover: a plain `...5348.MP4` gap, Sony `...5348M01.XML`
sidecars (number in the middle), image sequences `IMG_0001.JPG`, files with
no number, and duplicate numbers.

## Cutting a release

Releases are built by the org's **self-hosted** runner (never GitHub-hosted).

1. Bump nothing in code that isn't ready — the tag is the version.
2. Create and push a tag:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. The `release.yml` workflow runs on `[self-hosted, Windows]`, zips the two
   scripts plus `HOW-TO-USE.txt` into `BexmediaFileSequenceChecker.zip`, and
   publishes a GitHub Release with that zip attached.

You can also build the zip manually and attach it to a release by hand if the
runner is offline:

```powershell
mkdir dist
Copy-Item BexmediaFileSequenceChecker_Win.ps1, BexmediaFileSequenceChecker_Mac.command, HOW-TO-USE.txt dist\
Compress-Archive -Path dist\* -DestinationPath BexmediaFileSequenceChecker.zip -Force
gh release create v1.0.0 BexmediaFileSequenceChecker.zip --title "v1.0.0" --notes "..."
```

## Runners

The workflow is pinned to the organisation's self-hosted runners by label.
Current runners (Org → Settings → Actions → Runners):

- **TZV** — `self-hosted`, `Windows`, `X64`
- **MacMiniServers-Mac-mini** — `self-hosted`, `macOS`, `ARM64`

The release job only needs Windows, so it targets `[self-hosted, Windows]`.
