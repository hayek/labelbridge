# LabelBridge — design

Status: approved by the owner · 2026-11-22

## Intent

NIIMBOT Bluetooth label printers (starting with the **D11_H** the owner has) can only be used from the NIIMBOT phone app. LabelBridge lets a Mac print to them over Bluetooth, in three ways:

1. **Batch labels:** paste a list (for example, names) and print one label per item.
2. **Command line:** a `labelbridge` command that AI agents (and scripts) can run to print labels, replacing a local HTTP API.
3. **Any app:** the printer appears in the normal macOS Print dialog.

It is a separate open-source project and repo from PeriPage Bridge (`hayek/peripage-bridge`), shipped as a signed, notarized **.dmg**.

Why: the owner wants to print lots of labels quickly from the Mac (lists of names and the like), including in Hebrew/Arabic, and wants AI assistants to be able to do it by running a command.

## Goals

- Print to a NIIMBOT **D11_H** over Bluetooth LE from a Mac, reliably, with content centered on the label.
- **Batch:** a list of strings becomes one label per string. Each label's text is auto-sized to fill the printable area. Input is **one label per line** everywhere (window, file, stdin, arguments). A literal `\n` (backslash + n) inside an item becomes a line break on that label (*my call*).
- **Every language:** correct shaping and direction for RTL (Hebrew, Arabic), mixed-direction text, CJK and emoji.
- **CLI for agents:** non-interactive, scriptable, clear exit codes, optional JSON output, a preview mode that needs no printer.
- **Print dialog:** a printer queue "NIIMBOT D11 (Bluetooth)" with label paper sizes, usable from any app.
- **Distribution:** notarized universal .dmg (Apple Silicon and Intel, macOS 13+). First launch sets everything up.
- **Docs:** README with a banner image and social preview, like PeriPage Bridge.

## Non-goals

- A label designer or templates (QR codes, barcodes, icons, multiple styled fields). Images and complex layouts are possible through the Print dialog, not the batch tool.
- A local HTTP/network API. The CLI replaces it.
- Printers from other brands. PeriPage stays in its own project.
- Windows or Linux.
- Grayscale or two-color printing.

## Anti-goals (would count as failure even if it "works")

- Broken RTL: reversed letters, disconnected Arabic, wrong word order in mixed text.
- Content clipped, shifted, or running onto the next label.
- The CLI reporting success when nothing printed, or hanging forever.
- Any port reachable by websites in the browser that accepts print commands.
- Needing the phone app, or a terminal, for normal use.

## Constraints and facts already verified

**Printer (D11_H, verified on the owner's unit):**
- Advertises over BLE as `D11_H-<serial>`, with service `E7810A71-73AE-499D-8C15-FAA9AEF0C3F2` and one characteristic `BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F` (write without response + notify). Max write 241 bytes.
- 300 dpi, **142-pixel** print head (12.0 mm), print direction "left" (the image is rotated 90° clockwise into rows), darkness 1–5 (3 is good).
- The owner's labels are **15×50 mm**. The 12 mm head covers only part of the 15 mm height, so content must stay inside the head's band. A **2 mm safety margin at each end** of the label stops clipping at the leading edge.
- Protocol: NIIMBOT packets `55 55 cmd len data… xor-checksum AA AA` (Connect is prefixed with `03`). Most replies use the command ID + 0x10. The print sequence that worked (the "D110M v4" task in niimbluelib):
  connect `C1` → set label type `23 [1]` → set density `21 [d]` → print start `01 [pages u16, 0,0,0,0, color 0, speed 1, 0]` → print status `A3` (no wait) → page size `13 [rows u16, cols u16, copies u16, 0 u16, 0, 0, 0, 0 u16]` → rows (`85` bitmap rows with pixel count `[0, lo, hi]`, `84` empty runs, repeats ≤ 255, about 10 ms apart) → page end `E3` → poll print status `A3`/`B3` until the page count is reached → print end `F3` → heartbeat `DC` (no wait).
  Reference: MultiMote/niimbluelib (MIT). Credit it in the README.
- The printer accepts only **one** BLE connection. The phone app must be disconnected. LabelBridge connects per job and disconnects after.

**macOS:**
- Only an **app bundle** with `NSBluetoothAlwaysUsageDescription` can use Bluetooth. A CLI process started from Terminal is killed by privacy protection (observed earlier). So the CLI cannot talk to the printer itself.
- Ad-hoc signatures lose Bluetooth permission on every rebuild. Sign with the Developer ID (identity supplied by environment variable, never hard-coded).
- Printing from any app goes through CUPS. NIIMBOT has no macOS driver.

## Approaches considered

- **A. Fold into PeriPage Bridge** (one menu-bar app for both brands). Shared code, but one growing app and a name that no longer fits.
- **B. Separate app and repo** for NIIMBOT. Simple to explain and ship; some setup/signing code is copied from PeriPage Bridge. **← chosen by the owner**
- **C. Background app with a browser-based UI.** Least UI code, but not a Mac app, and it needs a local web server.

## Decided by the owner

- Separate app, separate repo, open source.
- Notarized .dmg. Installing also installs the "driver" (the Print-dialog printer).
- A CLI instead of a local server API, so AI agents can print.
- Batch: **one text item per label**, auto-sized.
- Must support any language, including RTL.

## Design

### Pieces

1. **LabelBridge.app** (a regular **Dock app** with a main window — decided by the owner, not a menu-bar app)
   - Owns Bluetooth: the only process that talks to the printer.
   - A **print service**: a queue of jobs, each a list of label images plus settings. One job at a time: connect, print all labels, disconnect.
   - **Main window ("Print Labels"):** printer status (found / printing / not found) at the top; a text area (one label per line); label size picker, darkness, copies, alignment, font; a live preview of the first labels at real proportions; a Print button with progress ("Label 12 of 40").
   - Standard menus: Settings (⌘,), Open Log, Quit. Closing the window keeps the app running so CLI and Print-dialog jobs still work; Quit stops it.
   - Optional "Open at login (hidden)" setting, on by default, so the CLI and the Print dialog work without opening the app first. When the app isn't running, the CLI launches it in the background, and CUPS keeps retrying a Print-dialog job until the app is up.
2. **`labelbridge` CLI** (inside the app bundle, symlinked to `/usr/local/bin/labelbridge` during setup)
   - A thin client: renders nothing and touches no Bluetooth. It sends a request to the app over a **Unix domain socket** in `~/Library/Application Support/LabelBridge/` (permissions 0600, owner only), waits for the result, and prints it.
   - If the app isn't running, it launches it (`open -g -b <bundle id>`) and waits up to 10 s for the socket.
3. **Print-dialog printer**
   - A CUPS queue `NIIMBOT_D11` ("NIIMBOT D11 (Bluetooth)") using a PPD that ships with the app. The PPD passes **PDF straight through** (no raster filter needs installing), lists the label sizes, and uses `socket://127.0.0.1:<port>`.
   - The app listens on that loopback port **only for CUPS jobs**. It accepts data starting with `%PDF` and nothing else, so it isn't an API. Each PDF page is rendered with PDFKit, fitted and centered onto one label, then printed.
   - **Risk:** PDF passthrough on modern macOS CUPS must be verified first with a short spike. Fallback: accept CUPS/PWG raster instead of PDF.
4. **Renderer** (shared by the window, the CLI and the Print dialog)
   - Label canvas = label length × printable height at 300 dpi (for 15×50: 591 × 142 px), minus the 2 mm end margins.
   - Text rendered with Core Text (via AppKit attributed strings), using natural direction per paragraph. Font size is the largest that fits both width and height (binary search). There's a minimum size; if the text still doesn't fit, it's truncated with "…" and reported as a warning.
   - 1-bit conversion with a threshold, rotated into printer rows (verified mapping: source pixel `(x = row, y = H-1-col)`, MSB-first bytes).

### CLI (proposed)

```
labelbridge print "Dana" "Yossi" "محمد"            # one label per argument
labelbridge print --file names.txt                  # one label per line
cat names.txt | labelbridge print -                 # stdin
  options: --size 50x15 (mm, default from settings) --density 1-5 --copies N
           --align center|leading|trailing --font "Arial Hebrew" --bold
           --dry-run (render only)  --json (machine-readable result)
labelbridge preview "Dana" --out /tmp/labels/       # writes PNGs, no printer needed
labelbridge status [--json]                          # app running? printer found? queue?
labelbridge sizes                                    # label sizes known
```

Exit codes: 0 printed; 2 bad input; 3 printer not found / busy (phone connected); 4 printing failed mid-job (reports how many labels printed); 5 app not available. `--json` returns `{ok, printed, total, warnings[], error?}`. Long batches stream progress to stderr.

Example for agent instructions (README): "To print labels, run `labelbridge print --json` with one label per argument."

### Setup on first launch (from the .dmg)

1. If not running from `/Applications`, offer to move there.
2. Ask for Bluetooth permission (explaining why first).
3. Add the CUPS queue (no admin needed for admin users; fall back to an admin prompt).
4. Install the CLI symlink in `/usr/local/bin` (admin prompt once). If declined, show the full path to use instead.
5. Enable launch at login.
6. Find the printer and offer a test label.

Settings: default label size (15×50), darkness (3), font, alignment, and "keep connected between jobs" (off by default, so the phone app can still connect).

### Label sizes

Built in: 15×50 (default), 12×40, 14×40, 15×30, 12×22, 14×22, 15×40, plus custom W×L. Width larger than 12 mm still uses the 12 mm band, centered (it's a physical limit).

## Testing

The owner has the D11_H and 15×50 labels on hand and can check physical output (photos), and the builder can drive the printer directly over Bluetooth from this Mac. Early milestones are hardware checks:
1. a multi-label job (several pages in one session) and the `copies` field,
2. "busy" behaviour (phone app connected) and failure partway through a job,
3. PDF passthrough through CUPS.

A small simulated printer (replaying recorded replies) covers protocol encoding and the CLI in unit tests.

## Left to the builder

Code layout, module boundaries, packet retry and timeout values, UI details, logging format, and how the D11 is matched (by name prefix plus the service UUID).

## My calls (reviewed by the owner)

- **Name:** "LabelBridge" (repo `hayek/labelbridge`, CLI `labelbridge`). It avoids putting the NIIMBOT trademark in the product name; the README says "for NIIMBOT label printers".
- Only the D11_H is verified. Other D11-family models (D11, D110, D11 Pro) listed as untested, using the same code path where the protocol matches.
- Default 15×50 mm, darkness 3, centered text, system font.
- The CLI installs into `/usr/local/bin` with one admin prompt.
- Multi-line labels use a literal `\n` inside an item; otherwise one line = one label.
- Sandboxed agent shells (e.g. Claude Code's sandbox) may block the socket or auto-launch. The CLI then exits with code 5 and a message saying what to allow; the README documents it. The design is not changed for sandboxes.
- PeriPage Bridge's README gets a "See also: LabelBridge" link once LabelBridge is released.
