# Bexmedia File Sequence Checker

A simple tool that checks a folder of files and tells you if any numbers are
**missing** from the sequence — so you can spot a lost or un-copied file
before it becomes a problem.

It works with **any file type** — video, images, XML sidecars, anything — and
with camera-style filenames like:

```
BEXFX30_20260721_5348.MP4
BEXFX30_20260721_5349.MP4
BEXFX30_20260721_5350.MP4   <-- 5351 is missing!
BEXFX30_20260721_5352.MP4
```

It gives you:

- a short summary of the gaps (e.g. `5354 - 5355 (2 files)`),
- a full list of every missing file's name, and
- a saved text file (`MissingFiles_<date>.txt`) you can keep or send on.

There is nothing to install, and **nothing ever leaves your computer** — the
tool only reads filenames.

---

## Download

Grab the latest version from the **[Releases page](../../releases/latest)**.

Download **`BexmediaFileSequenceChecker.zip`**, then unzip it. Inside:

| File | For |
|------|-----|
| `BexmediaFileSequenceChecker_Win.ps1` | **Windows** |
| `BexmediaFileSequenceChecker_Mac.command` | **Mac** |
| `HOW-TO-USE.txt` | A plain-English quick start |

---

## How to use it — Windows

1. Unzip the download and open the folder.
2. **Right-click** `BexmediaFileSequenceChecker_Win.ps1` → **Run with PowerShell**.
   *(If you see a red "execution policy" error, see
   [Troubleshooting](#troubleshooting-windows).)*
3. A window opens. **Drag your footage folder** into it and press **Enter**.
4. It asks if the report can go to your **Downloads** folder — press **Enter**
   for yes, or type **N** and drag a different folder in.
5. Read the report. A `MissingFiles_<date>.txt` file is saved where you chose.

---

## How to use it — Mac

The very first time only, you need to allow the file to run:

1. Unzip the download and open the folder.
2. **Right-click** (or Control-click) `BexmediaFileSequenceChecker_Mac.command` → **Open**.
3. Mac warns it's from an unidentified developer — click **Open** again.
   *(You only do this once.)*
4. A Terminal window opens. **Drag your footage folder** into it and press
   **Return**.
5. It asks if the report can go to your **Downloads** folder — press **Return**
   for yes, or type **N** and drag a different folder in.
6. Read the report. A `MissingFiles_<date>.txt` file is saved where you chose.

From then on you can just double-click it.

> If double-clicking says *"permission denied"*, open Terminal, type
> `chmod +x ` (with a trailing space), drag the `.command` file in, press
> Return — then try again.

---

## What the report looks like

```
===================================================
Sequence: 'BEXFX30_20260721_#.MP4'
  Files : 43
  Range : 5348 to 5393
  MISSING (3):
  Summary:
    5351
    5354 - 5355   (2 files)
  Full list:
    BEXFX30_20260721_5351.MP4
    BEXFX30_20260721_5354.MP4
    BEXFX30_20260721_5355.MP4

Saved full list to: ...\Downloads\MissingFiles_20260724_143022.txt
```

---

## Good to know

- **It works out which number matters automatically.** Even when a name also
  has a date in it (`BEXFX30_20260721_5348.MP4`), it correctly reads the clip
  number (`5348`) by spotting which number actually changes across the files —
  it doesn't just take the last one.
- **Each file type is its own sequence.** Your `.MP4` clips and their `.XML`
  sidecars are counted separately, so they never clash and confuse the count.
- **A gap at the very start or end might be normal.** If the lowest number is
  flagged, the clip may simply have continued from the previous card. Always
  sanity-check gaps at the top and bottom of the range against your other
  cards.
- **By default it does not look in sub-folders.** This is deliberate so a
  `Proxy` sub-folder doesn't get mixed in with your originals. (Advanced users
  can turn this on — see below.)
- **Files with no number are listed and skipped**, not counted.

---

## Advanced use (optional)

Run either script from a terminal and point it straight at a folder.

**Windows (PowerShell):**

```powershell
.\BexmediaFileSequenceChecker_Win.ps1 -Path "Z:\Footage\CLIP"
.\BexmediaFileSequenceChecker_Win.ps1 -Path "Z:\Footage\CLIP" -OutFolder "Z:\Reports"
.\BexmediaFileSequenceChecker_Win.ps1 -Path "Z:\Footage" -Recurse
.\BexmediaFileSequenceChecker_Win.ps1 -Path "Z:\Footage\CLIP" -Extensions mp4,xml
```

**Mac (Terminal):**

```bash
./BexmediaFileSequenceChecker_Mac.command "/Volumes/Footage/CLIP"
./BexmediaFileSequenceChecker_Mac.command "/Volumes/Footage/CLIP" "/Users/me/Reports"
./BexmediaFileSequenceChecker_Mac.command "/Volumes/Footage" --recurse
```

---

## Troubleshooting (Windows)

If Windows blocks the script with a red **execution policy** error, open
PowerShell and run this once, then try again:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

This only affects the current window and is the safe, standard way to run a
trusted local script.

---

## For developers

See [CONTRIBUTING.md](CONTRIBUTING.md). Releases are built by the
organisation's **self-hosted** runner: push a version tag (`v1.0.0`) and the
workflow packages the two scripts plus the guide into
`BexmediaFileSequenceChecker.zip` and attaches it to a GitHub Release.

---

*Made by Bexmedia. Free to use — including inside a company or on paid client
work. The only thing you can't do is sell the tool itself or make money from
it directly. See [LICENSE](LICENSE). No footage or data ever leaves your
computer; this tool only reads filenames.*
