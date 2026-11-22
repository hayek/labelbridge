# LabelBridge

![LabelBridge: print labels to a NIIMBOT D11 from your Mac over Bluetooth](docs/banner.jpg)

Print labels from your Mac to a **NIIMBOT D11** label printer **over Bluetooth**. NIIMBOT printers normally work only with the NIIMBOT phone app.

- **Batch labels:** paste a list, such as names, and get one label per line. Each label's text is sized to fill the label.
- **Any language:** Hebrew, Arabic and other right-to-left scripts, mixed-direction text, CJK and emoji.
- **Command line for AI agents and scripts:** `labelbridge print "Dana" "Yossi"`.
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

## Print from the window

Type or paste labels on the left, one per line. The middle shows a preview of each label at its real proportions. On the right you choose:
- the label size,
- copies,
- darkness,
- the font, bold and alignment.

Then click **Print** (⌘P). To put a line break inside a label, type `\n`.

## Print from the command line

```sh
labelbridge print "Dana" "יוסי" "محمد"            # one label per argument
labelbridge print --file names.txt                # one label per line
cat names.txt | labelbridge print -               # from stdin
labelbridge print "Spices\nTop shelf"             # two lines on one label
labelbridge print --copies 2 --density 4 --bold --font "Arial Hebrew" "Dana"
labelbridge print --json "Dana"                   # {"ok":true,"printed":1,"total":1,...}
labelbridge print --dry-run --file names.txt      # render only, don't print
labelbridge preview "Dana" --out /tmp/labels      # write PNGs, no printer needed
labelbridge status                                # app and printer status
labelbridge sizes                                 # built-in label sizes
```

**Options**

| Option | Default | Meaning |
|---|---|---|
| `--size 15x50` | the app's setting (15×50) | label size in mm |
| `--density 1-5` | 3 | darkness |
| `--copies N` | 1 | copies of each label |
| `--align center\|leading\|trailing` | center | leading means the start of the line, which is the right side for Hebrew and Arabic |
| `--font "<family>"` | system font | any installed font family |
| `--bold` | off | bold text |

**Exit codes:**
- `0` printed
- `2` bad input
- `3` printer not found or busy
- `4` printing failed partway (the JSON output says how many labels printed)
- `5` LabelBridge.app not available

The command talks to LabelBridge.app, which owns the Bluetooth connection. If the app isn't running, the command opens it in the background.

### Instructions for AI agents

Add this to your agent's instructions (for example `CLAUDE.md`):

> To print labels, run `labelbridge print --json` with one label per argument.

The agent's shell must be able to reach `~/Library/Application Support/LabelBridge/` and launch apps. Some sandboxed agent shells block this. You'll then see exit code `5`. Allow that folder, or run the command outside the sandbox.

## Print from any app

Choose **NIIMBOT D11 (Bluetooth)** in the Print dialog and pick a label size under **Paper Size**. Each page becomes one label, fitted and centred. LabelBridge must be running. Turn on **Open at login** in LabelBridge › Settings if you want the Print dialog to work without opening the app first.

## Label sizes

- Built in, width × length in mm: 15×50 (default), 12×40, 14×40, 15×30, 12×22, 14×22 and 15×40.
- Any other size: pass `--size WxL`.
- The D11's print head is 12 mm wide. On wider labels, the print stays in the 12 mm band in the middle.
- LabelBridge leaves 2 mm empty at each end of the label so nothing gets cut off.

## Troubleshooting

- **"Looking for your D11…" or exit code 3:** the printer is off, asleep or out of range, or the NIIMBOT phone app is connected to it. Close the app or turn off Bluetooth on the phone, then turn the printer on.
- **Bluetooth access needed:** allow LabelBridge in System Settings › Privacy & Security › Bluetooth.
- **Text looks too light:** raise the darkness.
- **Logs:** `~/Library/Logs/LabelBridge.log`. Open them from Help › Open Log.
- **Repair or uninstall:** LabelBridge › Settings.

## Supported printers

| Printer | Status |
|---|---|
| NIIMBOT D11_H | tested |
| NIIMBOT D11, D110, D11 Pro | untested; may work if they use the same protocol |

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
