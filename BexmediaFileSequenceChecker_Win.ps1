<#
    BexmediaFileSequenceChecker_Win.ps1
    Bexmedia File Sequence Checker (Windows)

    Scans a folder and reports any missing numbers in the filename sequence,
    for ANY file type - video, images, XML sidecars, anything.

    Files are grouped by their name prefix AND their extension, so e.g.
    ...5348.MP4 and ...5348.XML are checked as two separate sequences and
    never clash. That means it works whatever kinds of file are in the folder.

    Just run it and follow the prompts (drag a folder in). Or from PowerShell:
        .\BexmediaFileSequenceChecker_Win.ps1 -Path "D:\Footage\CLIP"
        .\BexmediaFileSequenceChecker_Win.ps1 -Path "D:\Footage" -Recurse
        .\BexmediaFileSequenceChecker_Win.ps1 -Path "D:\Footage\CLIP" -OutFolder "D:\Reports"
        .\BexmediaFileSequenceChecker_Win.ps1 -Path "D:\Footage\CLIP" -Extensions mp4,xml
#>

param(
    # Folder to scan. If not given, the script asks you to drag a folder in.
    [string]$Path,

    # Where to save the report. If not given, you're asked; defaults to Downloads.
    [string]$OutFolder,

    # Optionally limit to certain extensions (no dots). Default = every file type.
    [string[]]$Extensions,

    # Scan subfolders too.
    [switch]$Recurse
)

$interactive = ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected)

function Read-Folder([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { return '' }
    return $v.Trim().Trim('"').Trim("'")
}

# --- Ask for the folder to check (drag-and-drop friendly) -------------------
if ([string]::IsNullOrWhiteSpace($Path)) {
    Write-Host ""
    Write-Host "  Bexmedia File Sequence Checker" -ForegroundColor Cyan
    Write-Host "  ==============================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Drag the FOOTAGE folder to check into this window, then press Enter."
    Write-Host "     (Or just press Enter to check the current folder.)"
    Write-Host ""
    $Path = Read-Folder "  Folder to check"
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = (Get-Location).Path }
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Warning "'$Path' is not a folder."
    if ($interactive) { Read-Host "  Press Enter to close" }
    return
}
$Path = (Resolve-Path -LiteralPath $Path).Path

# We check the sequence FIRST. The report is only written (and you're only
# asked where to save it) if gaps are actually found. By default it saves next
# to the folder you checked; an -OutFolder passed on the command line is
# honoured without prompting.
$defaultOut = $Path

# --- Build the file list (every file type by default) -----------------------
$files = Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse
if ($Extensions) {
    $want = $Extensions | ForEach-Object { $_.TrimStart('.').ToLower() }
    $files = $files | Where-Object { $want -contains $_.Extension.TrimStart('.').ToLower() }
}

if (-not $files) {
    Write-Warning "No files found in '$Path'."
    if ($interactive) { Read-Host "  Press Enter to close" }
    return
}

# --- Parse each filename ----------------------------------------------------
# Auto-detect which number is the sequence number:
#   1. Replace every run of digits with '#' to get the file's "shape"
#      e.g. BEXFX30_20260721_5348M01.XML -> BEXFX30_#_#M#.XML
#   2. Group files that share the same shape + extension.
#   3. Within a group, whichever digit-position actually CHANGES across files
#      is the real sequence number. (Ties or single-file groups fall back to
#      the last number, which is right for plain ...5348.MP4 names.)

# First pass: record every digit run and the shape of each file.
$records = foreach ($f in $files) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $ext  = $f.Extension
    $matches = [regex]::Matches($name, '\d+')
    $shape = [regex]::Replace($name, '\d+', '#')
    [pscustomobject]@{
        File   = $f.Name
        Name   = $name
        Ext    = $ext
        Shape  = $shape + '|' + $ext.ToLower()
        Digits = @($matches | ForEach-Object { $_ })   # regex Match objects, in order
    }
}

# For each shape-group, decide which digit slot is the sequence number.
$slotForShape = @{}
foreach ($sg in ($records | Group-Object Shape)) {
    $maxSlots = ($sg.Group | ForEach-Object { $_.Digits.Count } | Measure-Object -Maximum).Maximum
    $chosen = -1
    # Prefer the slot with the most distinct values across the group (i.e. it varies).
    $bestDistinct = 1
    for ($s = 0; $s -lt $maxSlots; $s++) {
        $vals = $sg.Group |
            Where-Object { $_.Digits.Count -gt $s } |
            ForEach-Object { [int64]$_.Digits[$s].Value }
        $distinct = ($vals | Select-Object -Unique).Count
        if ($distinct -gt $bestDistinct) { $bestDistinct = $distinct; $chosen = $s }
    }
    # Nothing varied (all single-file or identical) -> use the LAST digit run.
    if ($chosen -lt 0) { $chosen = $maxSlots - 1 }
    $slotForShape[$sg.Name] = $chosen
}

# Second pass: build the parsed objects using the chosen slot per shape.
$parsed = foreach ($r in $records) {
    $slot = $slotForShape[$r.Shape]
    if ($r.Digits.Count -eq 0 -or $slot -lt 0 -or $slot -ge $r.Digits.Count) {
        [pscustomobject]@{ File = $r.File; Prefix = $null; Ext = $r.Ext; Key = $null; Number = $null; Padding = 0; Suffix = '' }
        continue
    }
    $d = $r.Digits[$slot]
    $prefix = $r.Name.Substring(0, $d.Index)
    $suffix = $r.Name.Substring($d.Index + $d.Length)   # text after the number (e.g. 'M01')
    [pscustomobject]@{
        File    = $r.File
        Prefix  = $prefix
        Ext     = $r.Ext
        Suffix  = $suffix
        Key     = $r.Shape + '|slot' + $slot
        Number  = [int64]$d.Value
        Padding = $d.Value.Length
    }
}

# Files with no number at all
$noNumber = $parsed | Where-Object { $null -eq $_.Number }
if ($noNumber) {
    Write-Host "`nFiles with no detectable number (ignored):" -ForegroundColor Yellow
    $noNumber | ForEach-Object { Write-Host "  $($_.File)" }
}

$groups = $parsed | Where-Object { $null -ne $_.Number } | Group-Object Key
$missingReport = [System.Collections.Generic.List[object]]::new()
# Per-sequence data captured for the colour HTML report (only groups with gaps).
$sequenceData  = [System.Collections.Generic.List[object]]::new()

foreach ($g in $groups) {
    $nums    = $g.Group.Number | Sort-Object
    $min     = $nums[0]
    $max     = $nums[-1]
    $padding = ($g.Group.Padding | Measure-Object -Maximum).Maximum
    $prefix  = $g.Group[0].Prefix
    $ext     = $g.Group[0].Ext
    # Most common suffix (text between the number and the extension, e.g. 'M01')
    $suffix  = ($g.Group.Suffix | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
    $label   = "$prefix#$suffix$ext"

    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "Sequence: '$label'" -ForegroundColor Cyan
    Write-Host "  Files : $($nums.Count)"
    Write-Host "  Range : $min to $max"

    $present = [System.Collections.Generic.HashSet[int64]]::new()
    $nums | ForEach-Object { [void]$present.Add($_) }

    $missing = for ($i = $min; $i -le $max; $i++) {
        if (-not $present.Contains($i)) { $i }
    }

    if ($missing) {
        Write-Host "  MISSING ($($missing.Count)):" -ForegroundColor Red

        # Collapse consecutive missing numbers into ranges for the summary
        $ranges = @()
        $start = $missing[0]; $prev = $missing[0]
        foreach ($n in $missing[1..($missing.Count-1)]) {
            if ($n -eq $prev + 1) { $prev = $n }
            else { $ranges += ,@($start,$prev); $start = $n; $prev = $n }
        }
        $ranges += ,@($start,$prev)

        Write-Host "  Summary:" -ForegroundColor Red
        foreach ($r in $ranges) {
            $a = ([string]$r[0]).PadLeft($padding,'0')
            $b = ([string]$r[1]).PadLeft($padding,'0')
            if ($r[0] -eq $r[1]) { Write-Host "    $a" }
            else                 { Write-Host "    $a - $b   ($([int64]$r[1]-[int64]$r[0]+1) files)" }
        }

        Write-Host "  Full list:" -ForegroundColor Red
        foreach ($n in $missing) {
            $fname = "$prefix$(([string]$n).PadLeft($padding,'0'))$suffix$ext"
            Write-Host "    $fname"
            $missingReport.Add([pscustomobject]@{
                Sequence = $label
                Number   = $n
                Filename = $fname
            })
        }

        # --- On-screen colour map: whole sequence, present green / missing red ---
        Write-Host "  Sequence (" -ForegroundColor Gray -NoNewline
        Write-Host "green = present" -ForegroundColor Green -NoNewline
        Write-Host ", " -ForegroundColor Gray -NoNewline
        Write-Host "red = MISSING" -ForegroundColor Red -NoNewline
        Write-Host "):" -ForegroundColor Gray
        Write-Host "    " -NoNewline
        $col = 0
        for ($i = $min; $i -le $max; $i++) {
            $token = ([string]$i).PadLeft($padding,'0')
            if ($present.Contains($i)) {
                Write-Host "$token " -ForegroundColor Green -NoNewline
            } else {
                Write-Host "$token " -ForegroundColor Red -NoNewline
            }
            $col++
            if ($col % 10 -eq 0) { Write-Host ""; Write-Host "    " -NoNewline }  # wrap every 10
        }
        Write-Host ""

        # Capture for the HTML report
        $sequenceData.Add([pscustomobject]@{
            Label   = $label
            Min     = $min
            Max     = $max
            Padding = $padding
            Present = $present
            Missing = @($missing)
        })
    }
    else {
        Write-Host "  No gaps - sequence is complete." -ForegroundColor Green
    }

    $dupes = $g.Group | Group-Object Number | Where-Object { $_.Count -gt 1 }
    if ($dupes) {
        Write-Host "  DUPLICATE numbers:" -ForegroundColor Magenta
        foreach ($d in $dupes) {
            Write-Host "    $($d.Name): $($d.Group.File -join ', ')"
        }
    }
}

# --- Only if gaps were found: work out where to save, then export -----------
if ($missingReport.Count -gt 0) {

    # Decide the output folder. If -OutFolder was given, use it as-is. Otherwise
    # default to the scanned folder, and (interactively) offer to change it -
    # but ONLY now that we know there's actually something to save.
    if ([string]::IsNullOrWhiteSpace($OutFolder)) {
        $OutFolder = $defaultOut
        if ($interactive) {
            Write-Host ""
            Write-Host "  Gaps were found - a report will be saved in the folder you checked:" -ForegroundColor Yellow
            Write-Host "     $defaultOut" -ForegroundColor Gray
            $change = Read-Host "     Save it somewhere else instead? (Y/N)"
            if ($change -match '^(y|yes)$') {
                Write-Host ""
                Write-Host "     Drag the folder where you want the report into this window, then press Enter."
                $picked = Read-Folder "     Save report to"
                if (-not [string]::IsNullOrWhiteSpace($picked)) { $OutFolder = $picked }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $OutFolder -PathType Container)) {
        Write-Warning "'$OutFolder' is not a folder - saving report next to the checked folder instead."
        $OutFolder = $defaultOut
    }
    $OutFolder = (Resolve-Path -LiteralPath $OutFolder).Path

    $stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
    $created  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $outFile  = Join-Path $OutFolder "MissingFiles_$stamp.txt"
    $htmlFile = Join-Path $OutFolder "MissingFiles_$stamp.html"

    # --- Plain text report (quick reading) ---
    $lines = @()
    $lines += "Missing files report"
    $lines += "Scanned : $Path"
    $lines += "Created : $created"
    $lines += "Total missing : $($missingReport.Count)"
    $lines += ""
    foreach ($grp in $missingReport | Group-Object Sequence) {
        $lines += "[$($grp.Name)]  ($($grp.Count) missing)"
        $grp.Group | ForEach-Object { $lines += "  $($_.Filename)" }
        $lines += ""
    }
    $lines | Set-Content -Path $outFile -Encoding UTF8

    # --- Colour HTML report (green = present, red = missing, with a filter) ---
    $sb = [System.Text.StringBuilder]::new()
    function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
    [void]$sb.Append(@"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Missing Files Report</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 24px; color: #1c1c1e; background: #fff; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .meta { color: #666; font-size: 13px; margin-bottom: 16px; line-height: 1.5; }
  .controls { position: sticky; top: 0; background: #fff; padding: 10px 0; border-bottom: 1px solid #eee; margin-bottom: 16px; }
  button { font-size: 14px; padding: 8px 14px; border: 1px solid #ccc; border-radius: 8px; background: #f6f6f6; cursor: pointer; }
  button.active { background: #1c1c1e; color: #fff; border-color: #1c1c1e; }
  .legend { display: inline-block; margin-left: 12px; font-size: 13px; color: #555; }
  .swatch { display: inline-block; width: 12px; height: 12px; border-radius: 3px; vertical-align: middle; margin: 0 4px 0 10px; }
  .seq { margin-bottom: 28px; }
  .seq h2 { font-size: 15px; margin: 0 0 2px; font-family: Consolas, monospace; }
  .seq .sub { color: #666; font-size: 12px; margin-bottom: 8px; }
  .grid { display: flex; flex-wrap: wrap; gap: 4px; }
  .num { font-family: Consolas, monospace; font-size: 13px; padding: 4px 7px; border-radius: 5px; }
  .present { background: #e4f7e4; color: #1a7f1a; }
  .missing { background: #fde3e3; color: #c62222; font-weight: 700; }
  body.missing-only .present { display: none; }
</style></head><body>
<h1>Missing files report</h1>
<div class="meta">
  Scanned: $(Enc $Path)<br>
  Created: $(Enc $created)<br>
  Total missing: $($missingReport.Count)
</div>
<div class="controls">
  <button id="btnAll" class="active" onclick="setFilter(false)">Show all</button>
  <button id="btnMiss" onclick="setFilter(true)">Show missing only</button>
  <span class="legend"><span class="swatch present"></span>present<span class="swatch missing"></span>missing</span>
</div>
"@)
    foreach ($sd in $sequenceData) {
        [void]$sb.Append("<div class=`"seq`"><h2>$(Enc $sd.Label)</h2>")
        [void]$sb.Append("<div class=`"sub`">Range $($sd.Min) to $($sd.Max) &middot; $($sd.Missing.Count) missing</div>")
        [void]$sb.Append("<div class=`"grid`">")
        for ($i = $sd.Min; $i -le $sd.Max; $i++) {
            $token = ([string]$i).PadLeft($sd.Padding,'0')
            if ($sd.Present.Contains([int64]$i)) {
                [void]$sb.Append("<span class=`"num present`">$token</span>")
            } else {
                [void]$sb.Append("<span class=`"num missing`">$token</span>")
            }
        }
        [void]$sb.Append("</div></div>")
    }
    [void]$sb.Append(@"
<script>
function setFilter(missingOnly){
  document.body.classList.toggle('missing-only', missingOnly);
  document.getElementById('btnMiss').classList.toggle('active', missingOnly);
  document.getElementById('btnAll').classList.toggle('active', !missingOnly);
}
</script>
</body></html>
"@)
    $sb.ToString() | Set-Content -Path $htmlFile -Encoding UTF8

    Write-Host "`nSaved plain list to : $outFile" -ForegroundColor Green
    Write-Host "Saved colour report: $htmlFile" -ForegroundColor Green
}
else {
    Write-Host "`nAll sequences complete - no gaps found. Nothing to save." -ForegroundColor Green
}

Write-Host ""

# Keep the window open when double-clicked, but don't block non-interactively.
if ($interactive) {
    Read-Host "  Done. Press Enter to close"
}
