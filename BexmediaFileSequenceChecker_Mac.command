#!/bin/bash
#
#  BexmediaFileSequenceChecker_Mac.command
#  Bexmedia File Sequence Checker (Mac)
#
#  Scans a folder and reports any missing numbers in the filename sequence,
#  for ANY file type - video, images, XML sidecars, anything.
#
#  It auto-detects which number in the name is the running sequence number
#  (so BEXFX30_20260721_5348M01.XML is read as clip 5348, not the date and
#  not the M01), by looking at which digit-position changes across the files.
#
#  HOW TO USE (non-technical):
#    1. Double-click this file. A Terminal window opens.
#    2. Drag the FOOTAGE folder to check into the window and press Return.
#    3. It asks if the report can go to your Downloads folder. Press Return
#       for yes, or type N and drag a different folder in.
#    4. Read the report. A "MissingFiles_<date>.txt" file is saved in the
#       output folder so you can keep or share the list.
#
#  ADVANCED (from Terminal):
#    ./BexmediaFileSequenceChecker_Mac.command "/Volumes/Footage/CLIP"
#    ./BexmediaFileSequenceChecker_Mac.command "/Volumes/Footage/CLIP" "/Users/me/Reports"
#    ./BexmediaFileSequenceChecker_Mac.command "/Volumes/Footage" --recurse
#

RECURSE=0
SCAN_PATH=""
OUT_FOLDER=""

for arg in "$@"; do
    case "$arg" in
        --recurse|-r) RECURSE=1 ;;
        *)
            if [ -z "$SCAN_PATH" ]; then SCAN_PATH="$arg"
            else OUT_FOLDER="$arg"; fi
            ;;
    esac
done

strip_quotes() {
    local s="$1"
    s="${s%\"}"; s="${s#\"}"
    s="${s%\'}"; s="${s#\'}"
    # trim trailing whitespace
    echo "$s" | sed 's/[[:space:]]*$//'
}

html_escape() {
    printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# --- Ask for the folder to check --------------------------------------------
if [ -z "$SCAN_PATH" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    echo ""
    echo "  Bexmedia File Sequence Checker"
    echo "  =============================="
    echo ""
    echo "  1) Drag the FOOTAGE folder to check into this window, then press Return."
    echo "     (Or just press Return to check: $SCRIPT_DIR)"
    echo ""
    printf "  Folder to check: "
    read -r SCAN_PATH
    SCAN_PATH="$(strip_quotes "$SCAN_PATH")"
    [ -z "$SCAN_PATH" ] && SCAN_PATH="$SCRIPT_DIR"
fi

if [ ! -d "$SCAN_PATH" ]; then
    echo ""
    echo "  ERROR: '$SCAN_PATH' is not a folder."
    echo ""
    read -r -p "  Press Return to close." _
    exit 1
fi

# We check the sequence FIRST. The report is only written (and you're only
# asked where to save it) if gaps are actually found. By default it saves next
# to the folder you checked; a second path argument is honoured without asking.
DEFAULT_OUT="$SCAN_PATH"

# --- Build the file list (every file type) ----------------------------------
if [ $RECURSE -eq 1 ]; then DEPTH=(); else DEPTH=("-maxdepth" "1"); fi

FILES=$(find "$SCAN_PATH" "${DEPTH[@]}" -type f ! -name '.*' 2>/dev/null \
        | while IFS= read -r f; do basename "$f"; done | sort)

if [ -z "$FILES" ]; then
    echo ""
    echo "  No files found in '$SCAN_PATH'."
    echo ""
    read -r -p "  Press Return to close." _
    exit 0
fi

# ===========================================================================
#  Parsing / auto-detect is done in awk so it's fast and portable (BSD awk).
#
#  Approach:
#    - shape = filename with every digit-run replaced by '#'  (grouping key)
#    - within each shape, find which digit-slot varies the most across files;
#      that slot is the sequence number (falls back to the last slot).
#    - then report gaps per (shape, slot).
# ===========================================================================

STAMP=$(date +%Y%m%d_%H%M%S)

REPORT=$(printf '%s\n' "$FILES" | awk -v scanpath="$SCAN_PATH" '
function basenum(s,   n){ n=s+0; return n }   # strip leading zeros for math

{
    file=$0
    # split name and extension
    ext=""; name=file
    if (match(file, /\.[^.\/]+$/)) { ext=substr(file, RSTART); name=substr(file,1,RSTART-1) }

    # walk the name, collecting digit runs and building the shape
    shape=""; nd=0; rest=name
    while (match(rest, /[0-9]+/)) {
        pre=substr(rest,1,RSTART-1)
        dig=substr(rest,RSTART,RLENGTH)
        shape=shape pre "#"
        nd++
        # store per (file) the digit values and their padding
        digval[file,nd]=dig
        rest=substr(rest,RSTART+RLENGTH)
    }
    shape=shape rest ext
    if (nd==0) { nonum[++nnum]=file; next }   # no digits at all -> ignore
    fkey[NR]=file
    fshape[file]=shape
    fnd[file]=nd
    ext_of[file]=ext
    name_of[file]=name
    files[NR]=file
    if (NR>total) total=NR

    # track shape membership and max slots
    shapes[shape]=1
    if (nd>maxslot[shape]) maxslot[shape]=nd
    scount[shape]++
    # remember one member order for later reconstruction template
}

END {
    # Report files with no number at all.
    if (nnum>0) {
        print ""                                                  > "/dev/stderr"
        print "  Files with no detectable number (ignored):"      > "/dev/stderr"
        for (i=1;i<=nnum;i++) printf "    %s\n", nonum[i]         > "/dev/stderr"
    }

    # For each shape, choose the slot with the most distinct values.
    for (s in shapes) {
        best=-1; bestd=1
        for (slot=1; slot<=maxslot[s]; slot++) {
            delete seen
            d=0
            for (i=1;i<=total;i++) {
                f=files[i]
                if (fshape[f]!=s) continue
                if (fnd[f]<slot) continue
                v=digval[f,slot]+0
                if (!(v in seen)) { seen[v]=1; d++ }
            }
            if (d>bestd) { bestd=d; best=slot }
        }
        if (best<0) best=maxslot[s]   # nothing varied -> last slot
        chosen[s]=best
    }

    # Build per-shape sorted number lists and metadata.
    header_printed=0
    grand=0
    for (s in shapes) {
        slot=chosen[s]
        # gather numbers, find min/max/padding, template prefix+suffix
        n=0; mn=1e18; mx=-1; pad=0
        delete present
        tmpl_prefix=""; tmpl_suffix=""; tmpl_ext=""
        for (i=1;i<=total;i++) {
            f=files[i]
            if (fshape[f]!=s) continue
            if (fnd[f]<slot) continue
            val=digval[f,slot]+0
            plen=length(digval[f,slot])
            if (plen>pad) pad=plen
            present[val]=1
            if (val<mn) mn=val
            if (val>mx) mx=val
            n++
            # derive prefix/suffix from THIS file at the chosen slot
            # re-walk to find the slot boundaries
            rest=name_of[f]; k=0; pfx=""
            while (match(rest, /[0-9]+/)) {
                k++
                if (k==slot) {
                    pfx=pfx substr(rest,1,RSTART-1)
                    sfx=substr(rest,RSTART+RLENGTH)
                    if (tmpl_prefix=="" && tmpl_suffix=="") { tmpl_prefix=pfx; tmpl_suffix=sfx; tmpl_ext=ext_of[f] }
                    break
                } else {
                    pfx=pfx substr(rest,1,RSTART+RLENGTH-1)
                    rest=substr(rest,RSTART+RLENGTH)
                }
            }
        }
        if (n==0) continue

        label=tmpl_prefix "#" tmpl_suffix tmpl_ext

        # console section
        print ""                                                   > "/dev/stderr"
        print "  ===================================================" > "/dev/stderr"
        printf "  Sequence: %s\n", label                           > "/dev/stderr"
        printf "    Files : %d\n", n                               > "/dev/stderr"
        printf "    Range : %d to %d\n", mn, mx                    > "/dev/stderr"

        # find missing
        misscount=0
        # build missing list into array
        delete miss
        for (v=mn; v<=mx; v++) if (!(v in present)) { misscount++; miss[misscount]=v }

        if (misscount>0) {
            printf "    MISSING (%d):\n", misscount                > "/dev/stderr"
            printf "    Summary:\n"                                > "/dev/stderr"
            # collapse ranges
            start=miss[1]; prev=miss[1]
            for (j=2;j<=misscount;j++) {
                if (miss[j]==prev+1) { prev=miss[j] }
                else {
                    printrange(start,prev,pad)
                    start=miss[j]; prev=miss[j]
                }
            }
            printrange(start,prev,pad)

            printf "    Full list:\n"                              > "/dev/stderr"
            # to stdout (captured) we emit the report body
            if (!header_printed) {
                print "Missing files report"
                print "Scanned : " scanpath
                print "SECTIONS_FOLLOW"
                header_printed=1
            }
            printf "[%s]  (%d missing)\n", label, misscount
            for (j=1;j<=misscount;j++) {
                fn=recon(tmpl_prefix, miss[j], pad, tmpl_suffix, tmpl_ext)
                printf "      %s\n", fn                            > "/dev/stderr"
                printf "  %s\n", fn
                grand++
            }
            print ""

            # --- On-screen colour map (green present / red missing) ---
            printf "    Sequence (\033[32mgreen = present\033[0m, \033[31mred = MISSING\033[0m):\n" > "/dev/stderr"
            printf "    "                                         > "/dev/stderr"
            col=0
            for (v=mn; v<=mx; v++) {
                tok=sprintf("%0" pad "d", v)
                if (v in present) printf "\033[32m%s\033[0m ", tok > "/dev/stderr"
                else              printf "\033[31m%s\033[0m ", tok > "/dev/stderr"
                col++
                if (col%10==0) { printf "\n    "                  > "/dev/stderr" }
            }
            printf "\n"                                           > "/dev/stderr"

            # --- Machine-readable line for the HTML builder ---
            # SEQ <tab> label <tab> min <tab> max <tab> pad <tab> prefix <tab>
            #     suffix <tab> ext <tab> space-joined-present-numbers
            plist=""
            for (v=mn; v<=mx; v++) if (v in present) plist=plist v " "
            printf "SEQ\t%s\t%d\t%d\t%d\t%s\t%s\t%s\t%s\n", label, mn, mx, pad, tmpl_prefix, tmpl_suffix, tmpl_ext, plist
        } else {
            print "    No gaps - sequence is complete."           > "/dev/stderr"
        }

        # duplicates
        delete dcount
        for (i=1;i<=total;i++) {
            f=files[i]
            if (fshape[f]!=s) continue
            if (fnd[f]<slot) continue
            dcount[digval[f,slot]+0]++
        }
        dprinted=0
        for (v in dcount) if (dcount[v]>1) {
            if (!dprinted) { print "    DUPLICATE numbers:" > "/dev/stderr"; dprinted=1 }
            printf "      %d (x%d)\n", v, dcount[v]               > "/dev/stderr"
        }
    }
    print "TOTAL " grand
}

function printrange(a,b,pad,   fa,fb) {
    fa=sprintf("%0" pad "d", a)
    fb=sprintf("%0" pad "d", b)
    if (a==b) printf "      %s\n", fa                             > "/dev/stderr"
    else printf "      %s - %s   (%d files)\n", fa, fb, b-a+1     > "/dev/stderr"
}

function recon(pfx,num,pad,sfx,ext,   p) {
    p=sprintf("%0" pad "d", num)
    return pfx p sfx ext
}
' 2> >(cat >&2))

# REPORT (stdout) holds the file body; console output went to stderr already.
GRAND=$(printf '%s\n' "$REPORT" | sed -n 's/^TOTAL //p')

if [ "${GRAND:-0}" -gt 0 ] 2>/dev/null; then
    # Gaps were found - NOW decide where to save (only prompt if no folder was
    # passed as an argument).
    if [ -z "$OUT_FOLDER" ]; then
        OUT_FOLDER="$DEFAULT_OUT"
        echo ""
        echo "  Gaps were found - a report will be saved in the folder you checked:"
        echo "     $DEFAULT_OUT"
        printf "     Save it somewhere else instead? (Y/N) "
        read -r ANS
        case "$ANS" in
            y|Y|yes|YES)
                echo ""
                echo "     Drag the folder where you want the report into this window, then press Return."
                printf "     Save report to: "
                read -r PICKED
                PICKED="$(strip_quotes "$PICKED")"
                [ -n "$PICKED" ] && OUT_FOLDER="$PICKED"
                ;;
        esac
    fi

    if [ ! -d "$OUT_FOLDER" ]; then
        echo "  '$OUT_FOLDER' is not a folder - saving report next to the checked folder instead."
        OUT_FOLDER="$DEFAULT_OUT"
    fi

    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
    OUT_FILE="$OUT_FOLDER/MissingFiles_$STAMP.txt"
    HTML_FILE="$OUT_FOLDER/MissingFiles_$STAMP.html"

    # --- Plain text report (SEQ lines are skipped) ---
    {
        echo "Missing files report"
        echo "Scanned : $SCAN_PATH"
        echo "Created : $CREATED"
        echo "Total missing : $GRAND"
        echo ""
        printf '%s\n' "$REPORT" | awk '
            /^SECTIONS_FOLLOW$/ { on=1; next }
            /^TOTAL /           { on=0 }
            /^SEQ\t/            { next }        # machine data, not for the txt
            on { print }
        '
    } > "$OUT_FILE"

    # --- Colour HTML report (green present / red missing, with a filter) ---
    {
        cat <<HTMLHEAD
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Missing Files Report</title>
<style>
  body { font-family: -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 24px; color: #1c1c1e; background: #fff; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .meta { color: #666; font-size: 13px; margin-bottom: 16px; line-height: 1.5; }
  .controls { position: sticky; top: 0; background: #fff; padding: 10px 0; border-bottom: 1px solid #eee; margin-bottom: 16px; z-index: 5; }
  button { font-size: 14px; padding: 8px 14px; border: 1px solid #ccc; border-radius: 8px; background: #f6f6f6; cursor: pointer; }
  button.active { background: #1c1c1e; color: #fff; border-color: #1c1c1e; }
  .legend { display: inline-block; margin-left: 12px; font-size: 13px; color: #555; }
  .swatch { display: inline-block; width: 12px; height: 12px; border-radius: 3px; vertical-align: middle; margin: 0 4px 0 10px; }
  .swatch.present { background: #e4f7e4; } .swatch.missing { background: #fde3e3; }
  .grp { margin-bottom: 32px; }
  .grp .sub { color: #666; font-size: 12px; margin: 0 0 8px; }
  table { border-collapse: collapse; font-family: Consolas, monospace; font-size: 13px; }
  th { text-align: left; padding: 6px 10px; border-bottom: 2px solid #ddd; font-size: 13px; white-space: nowrap; }
  td { padding: 3px 10px; white-space: nowrap; }
  td.present { color: #1a7f1a; }
  td.missing { color: #c62222; font-weight: 700; background: #fde3e3; }
  td.num { color: #999; text-align: right; border-right: 1px solid #eee; }
  body.missing-only tr.allpresent { display: none; }
</style></head><body>
<h1>Missing files report</h1>
<div class="meta">
  Scanned: $(html_escape "$SCAN_PATH")<br>
  Created: $(html_escape "$CREATED")<br>
  Total missing: $GRAND
</div>
<div class="controls">
  <button id="btnAll" class="active" onclick="setFilter(false)">Show all</button>
  <button id="btnMiss" onclick="setFilter(true)">Show missing only</button>
  <span class="legend"><span class="swatch present"></span>present<span class="swatch missing"></span>missing</span>
</div>
HTMLHEAD

        # Build one table per range group. Sequences sharing a number range
        # (e.g. an MP4 and its M01.XML sidecar) become side-by-side columns,
        # one row per number, each cell the full reconstructed filename.
        printf '%s\n' "$REPORT" | awk -F'\t' '
            function esc(s){ gsub(/&/,"\\&amp;",s); gsub(/</,"\\&lt;",s); gsub(/>/,"\\&gt;",s); return s }
            /^SEQ\t/ {
                # $2 label $3 min $4 max $5 pad $6 prefix $7 suffix $8 ext $9 plist
                n++
                s_label[n]=$2; s_min[n]=$3; s_max[n]=$4; s_pad[n]=$5
                s_prefix[n]=$6; s_suffix[n]=$7; s_ext[n]=$8; s_plist[n]=$9
                key=$3 "-" $4
                if (!(key in gseen)) { gseen[key]=1; gorder[++gcount]=key }
                # append this sequence index to the group
                gmembers[key]=gmembers[key] n " "
            }
            END {
                for (gi=1; gi<=gcount; gi++) {
                    key=gorder[gi]
                    cnt=split(gmembers[key], mem, " ")
                    # trailing empty token from split
                    realcnt=0
                    for (m=1;m<=cnt;m++) if (mem[m]!="") { realcnt++; idx[realcnt]=mem[m]+0 }
                    if (realcnt==0) continue
                    # Sort columns by label so order is stable (.MP4 before M01.XML)
                    for (a=1;a<realcnt;a++) for (b=a+1;b<=realcnt;b++)
                        if (s_label[idx[b]] < s_label[idx[a]]) { t=idx[a]; idx[a]=idx[b]; idx[b]=t }
                    first=idx[1]
                    mn=s_min[first]; mx=s_max[first]; pad=s_pad[first]

                    # per-member present sets + total missing
                    totmiss=0
                    for (c=1;c<=realcnt;c++) {
                        si=idx[c]
                        split(s_plist[si], parr, " ")
                        delete pres
                        for (p in parr) if (parr[p]!="") pres[parr[p]+0]=1
                        # store into a 2D-ish keyed array
                        for (v=mn; v<=mx; v++) { P[c SUBSEP v] = (v in pres) ? 1 : 0; if (!(v in pres)) totmiss++ }
                    }

                    plural=(realcnt==1)?"":"s"
                    printf "<div class=\"grp\">"
                    printf "<div class=\"sub\">Range %d to %d &middot; %d missing across %d file type%s</div>", mn, mx, totmiss, realcnt, plural
                    printf "<table><thead><tr><th>#</th>"
                    for (c=1;c<=realcnt;c++) printf "<th>%s</th>", esc(s_label[idx[c]])
                    printf "</tr></thead><tbody>"

                    for (v=mn; v<=mx; v++) {
                        tok=sprintf("%0" pad "d", v)
                        anymiss=0
                        for (c=1;c<=realcnt;c++) if (!P[c SUBSEP v]) { anymiss=1; break }
                        rowcls = anymiss ? "" : " class=\"allpresent\""
                        printf "<tr%s><td class=\"num\">%s</td>", rowcls, tok
                        for (c=1;c<=realcnt;c++) {
                            si=idx[c]
                            fname=s_prefix[si] tok s_suffix[si] s_ext[si]
                            if (P[c SUBSEP v]) printf "<td class=\"present\">%s</td>", esc(fname)
                            else               printf "<td class=\"missing\">%s</td>", esc(fname)
                        }
                        printf "</tr>"
                    }
                    printf "</tbody></table></div>\n"
                    # clear P for next group
                    delete P
                }
            }
        '

        cat <<'HTMLFOOT'
<script>
function setFilter(missingOnly){
  document.body.classList.toggle('missing-only', missingOnly);
  document.getElementById('btnMiss').classList.toggle('active', missingOnly);
  document.getElementById('btnAll').classList.toggle('active', !missingOnly);
}
</script>
</body></html>
HTMLFOOT
    } > "$HTML_FILE"

    echo ""
    echo "  Saved plain list to : $OUT_FILE"
    echo "  Saved colour report: $HTML_FILE"
else
    echo ""
    echo "  All sequences complete - no gaps found. Nothing to save."
fi

echo ""
read -r -p "  Done. Press Return to close." _
