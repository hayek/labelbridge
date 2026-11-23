# LabelBridge

![LabelBridge: print labels to a NIIMBOT D11 from your Mac over Bluetooth](docs/banner.jpg)

Print labels from your Mac to a **NIIMBOT D11 or D110** label printer **over Bluetooth**. NIIMBOT printers normally work only with the NIIMBOT phone app.

- **Batch labels:** paste a list, such as names, and get one label per line. Each label's text is sized to fill the label.
- **Any language:** Hebrew, Arabic and other right-to-left scripts, mixed-direction text, CJK and emoji.
- **Command line for AI agents and scripts:** `labelbridge print "Oliver" "Emily"`.
- **Any app's Print dialog:** a printer called **NIIMBOT D11 (Bluetooth)** with label paper sizes.

## Install

1. Download **LabelBridge.dmg** from the [latest release](../../releases/latest), open it, and drag **LabelBridge** to **Applications**.
2. Open LabelBridge and click **Start Setup**. Setup:
   - moves the app to Applications if needed,
   - asks for Bluetooth access,
   - adds the printer **NIIMBOT D11 (Bluetooth)**,
   - installs the `labelbridge` command in `/usr/local/bin`. macOS asks for your password.
3. Turn the D11 on and disconnect the NIIMBOT phone app. The printer accepts only one Bluetooth connection at a time. LabelBridge shows **Ready to print** when it sees the printer.

Requires macOS 13 or later, on Apple Silicon or Intel. LabelBridge is signed and notarized by Apple.

**Updates:** choose LabelBridge › Check for Updates…. LabelBridge also checks this repo's GitHub releases once a day and tells you when a new version is out. Nothing else is sent. You can turn this off in LabelBridge › Settings.

## Print from the window

<p align="center"><img src="docs/screenshot.png" width="760" alt="The LabelBridge window: two labels typed on the left, their previews in the middle, and the size, copies, darkness and text options on the right"></p>

Type or paste labels on the left, one per line. The middle shows a preview of each label at its real proportions. On the right you choose:
- the label size,
- copies,
- darkness,
- the font, bold and alignment.

Then click **Print** (⌘P). To put a line break inside a label, type `\n`.

## Design circular stickers and icon labels

Choose **Sticker designer** at the top of the window:

1. Pick a template: **Appliances**, **Icons + text**, **Names**, **Blank circles**, or **Blank rectangle**.
2. Use **Add Text** and **Add Icon** to add as many objects as needed. The icon library includes household appliances, lights and common symbols.
3. Click an object to select it. Drag it to move it, or drag its blue bottom-right handle to resize it. The inspector also provides exact X, Y, width and height in millimetres.
4. For text objects, edit the words in **Text content** on the right. Choose a font, bold, italic and alignment. Keep **Auto-fit text** on to fit the object, or turn it off to choose an exact **Font size** in physical points (1–72 pt). Oversized text produces a preview warning.
5. Choose **Transparent** for your transparent roll, set copies and print. **Print 1 Pair** prints one feed unit containing both circles.

The circular template is two **14 mm circles** on a **14 × 28 mm** feed unit. Either circle can contain multiple independent text and icon objects, or remain blank. Circle outlines and selection handles are preview-only. The D110's print band is about 12 mm wide; the preview shows the actual printable ink and warns when content is clipped or text does not fit.

The current draft is saved automatically on this Mac. **Save Template** adds a named design to **My Templates**, ready to reuse. Undo and redo cover template changes, object edits, moves and resizing. The original one-label-per-line workflow remains under **Text batch**; CLI and Print-dialog jobs are unchanged and do not implicitly print the visual design.

## Print from the command line

```sh
labelbridge print "Oliver" "Emily" "محمد"         # one label per argument
labelbridge print --file names.txt                # one label per line
cat names.txt | labelbridge print -               # from stdin
labelbridge print "Spices\nTop shelf"             # two lines on one label
labelbridge print --copies 2 --density 4 --bold --font "Arial Hebrew" "Oliver"
labelbridge print --size 14x28 --media transparent "Spices"
labelbridge print --json "Oliver"                 # {"ok":true,"printed":1,"total":1,...}
labelbridge print --dry-run --file names.txt      # render only, don't print
labelbridge preview "Oliver" --out /tmp/labels    # write PNGs, no printer needed
labelbridge status                                # app and printer status
labelbridge sizes                                 # built-in label sizes
```

**Options**

| Option | Default | Meaning |
|---|---|---|
| `--size 15x50` | the app's setting (15×50) | label size in mm |
| `--density 1-5` | 3 | darkness |
| `--media gaps\|transparent` | the app's setting (gaps initially) | label material/sensor mode |
| `--copies N` | 1 | copies of each label |
| `--align center\|leading\|trailing` | center | leading means the start of the line, which is the right side for Hebrew and Arabic |
| `--font "<family>"` | system font | any installed font family |
| `--bold` | off | bold text |

**Exit codes:**
- `0` printed
- `2` bad input
- `3` printer not found or busy
- `4` printing failed, for example the printer stopped answering (the JSON output says how many labels printed)
- `5` LabelBridge.app not available

The command talks to LabelBridge.app, which owns the Bluetooth connection. If the app isn't running, the command opens it in the background.

<details>
<summary><b>Full command reference</b> (<code>labelbridge --help</code>)</summary>

```text
OVERVIEW: Print labels to a NIIMBOT Bluetooth label printer through
LabelBridge.app.

One label per argument, or one per line with --file or stdin (-). Type \n
inside a label for a line break. Any language works, including Hebrew and
Arabic. Defaults (size, media, darkness, font, alignment) come from the app's window.

EXAMPLES:
  labelbridge print "Dana" "Yossi" "محمد"
  labelbridge print --file names.txt --copies 2
  cat names.txt | labelbridge print -
  labelbridge print --json "Spices\nTop shelf"
  labelbridge preview "Dana" --out /tmp/labels

FOR AI AGENTS:
  Add to the agent's instructions:
  "To print labels, run `labelbridge print --json`
   with one label per argument."

EXIT CODES:
  0  printed
  2  bad input
  3  printer off, asleep, or busy (phone app connected)
  4  printing failed (the JSON says how many labels printed)
  5  LabelBridge.app not available

USAGE: labelbridge <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  print (default)         Print labels (default command).
  preview                 Write label images (PNG) without printing.
  status                  Show whether LabelBridge.app and the printer are
                          available.
  sizes                   List built-in label sizes (width x length, mm).

  See 'labelbridge help <subcommand>' for detailed help.

────────

OVERVIEW: Print labels (default command).

Prints one label per item and waits until they're done. Progress goes to
stderr. With --json, prints {"ok", "printed", "total", "skipped", "warnings",
"error"} to stdout. Blank lines are skipped. Text that doesn't fit is shortened
with "…" and reported as a warning.

USAGE: labelbridge print [<items> ...] [--file <file>] [--size <size>] [--density <density>] [--media <media>] [--copies <copies>] [--align <align>] [--font <font>] [--bold] [--dry-run] [--json]

ARGUMENTS:
  <items>                 Label texts. Use - to read lines from stdin.

OPTIONS:
  -f, --file <file>       Read labels from a file, one per line.
  --size <size>           Label size in mm, width x length, e.g. 15x50 (see
                          `labelbridge sizes`).
  --density <density>     Darkness 1–5 (default 3).
  --media <media>         Label media: gaps or transparent (default: the app's
                          setting).
  --copies <copies>       Copies of each label. (default: 1)
  --align <align>         center, leading or trailing. Leading is the start of
                          the line: the right side for Hebrew and Arabic.
  --font <font>           Font family name, e.g. "Arial Hebrew".
  --bold                  Bold text.
  --dry-run               Render only; don't print.
  --json                  Print the result as JSON.
  -h, --help              Show help information.


────────

OVERVIEW: Write label images (PNG) without printing.

USAGE: labelbridge preview [<items> ...] [--file <file>] [--size <size>] [--density <density>] [--copies <copies>] [--align <align>] [--font <font>] [--bold] [--out <out>]

ARGUMENTS:
  <items>                 Label texts. Use - to read lines from stdin.

OPTIONS:
  -f, --file <file>       Read labels from a file, one per line.
  --size <size>           Label size in mm, width x length, e.g. 15x50 (see
                          `labelbridge sizes`).
  --density <density>     Darkness 1–5 (default 3).
  --copies <copies>       Copies of each label. (default: 1)
  --align <align>         center, leading or trailing. Leading is the start of
                          the line: the right side for Hebrew and Arabic.
  --font <font>           Font family name, e.g. "Arial Hebrew".
  --bold                  Bold text.
  --out <out>             Output directory. (default: .)
  -h, --help              Show help information.


────────

OVERVIEW: Show whether LabelBridge.app and the printer are available.

USAGE: labelbridge status [--json]

OPTIONS:
  --json                  Print as JSON.
  -h, --help              Show help information.
```

</details>

### Instructions for AI agents

Add this to your agent's instructions (for example `CLAUDE.md`):

> To print labels, run `labelbridge print --json` with one label per argument.

The agent's shell must be able to reach `~/Library/Application Support/LabelBridge/` and launch apps. Some sandboxed agent shells block this. You'll then see exit code `5`. Allow that folder, or run the command outside the sandbox.

## Print from any app

Choose **NIIMBOT D11 (Bluetooth)** in the Print dialog and pick a label size under **Paper Size**. Each page becomes one label, fitted and centred. LabelBridge must be running. Turn on **Open at login** in LabelBridge › Settings if you want the Print dialog to work without opening the app first.

## Label sizes

- Built in, width × length in mm: 15×50 (default), 12×40, 14×40, 15×30, 12×22, 14×22, 15×40 and 14×28.
- For **TT14×28-220 transparent** rolls, select **14 × 28 mm** and **Media: Transparent** in the window. The “220” is the label count. The CLI uses these saved settings, or you can pass `--size 14x28 --media transparent`. Print-dialog jobs use the window's Media setting; choose 14 × 28 mm as their Paper Size. Existing installations need **Settings › Repair Setup** to refresh the Print-dialog paper sizes.
- Any other size: pass `--size WxL`.
- The D11's print head is 12 mm wide. On wider labels, the print stays in the 12 mm band in the middle.
- The original D110 is selected automatically by its Bluetooth name (`D110-…`), using its legacy protocol, 203 dpi and 96-dot head. Darkness values above 3 use the D110's maximum of 3. Previews use the D11_H canvas and are resized for the D110 when printing.
- LabelBridge leaves 2 mm empty at each end of the label so nothing gets cut off.

## Troubleshooting

- **"Looking for your D11…" or exit code 3:** the printer is off, asleep or out of range, or the NIIMBOT phone app is connected to it. Close the app or turn off Bluetooth on the phone, then turn the printer on.
- **The printer's light turns red and printing stops:** the printer found a problem, usually labels not seated, so it can't find the next label, or the lid not fully closed. LabelBridge shows the printer's reason. Open the lid, reseat the roll, close it firmly, and turn the printer off and on if the light stays red.
- **Bluetooth access needed:** allow LabelBridge in System Settings › Privacy & Security › Bluetooth.
- **Text looks too light:** raise the darkness.
- **Logs:** `~/Library/Logs/LabelBridge.log`. Open them from Help › Open Log.
- **More help:** Help › LabelBridge Help (⌘?) in the app covers printing, the command line, AI agents and troubleshooting.
- **Repair or uninstall:** LabelBridge › Settings.

## Supported printers

| Printer | Status |
|---|---|
| NIIMBOT D11_H | tested |
| NIIMBOT D110 | tested with the legacy protocol and 203 dpi, 96-dot head |
| NIIMBOT D11, D11 Pro, D110_M | untested; may work if they use the same protocol |

## Build from source

```sh
swift test
scripts/dev-bundle.sh                                   # debug app in build/dev/
SIGN_ID="Developer ID Application: …" scripts/build.sh  # universal release build in build/
scripts/make-dmg.sh
NOTARY_PROFILE=<profile> scripts/notarize.sh            # or ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID
```

Without `SIGN_ID`, the app is signed ad hoc. macOS then asks for Bluetooth access again after every build.

The Bluetooth protocol is described in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## Credits

- The NIIMBOT protocol details come from [MultiMote/niimbluelib](https://github.com/MultiMote/niimbluelib) (MIT).
- See also [PeriPage Bridge](https://github.com/hayek/peripage-bridge), which prints to a PeriPage P81 from a Mac over Bluetooth.

This is an independent project and is not affiliated with NIIMBOT. MIT licensed.
