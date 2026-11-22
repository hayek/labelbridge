# LabelBridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A notarized macOS Dock app plus a `labelbridge` CLI that print text labels (batch, any language) and Print-dialog jobs to a NIIMBOT D11_H over Bluetooth LE.

**Architecture:** A Swift package with a pure library (`LabelCore`: packets, row encoding, text rendering, IPC messages, print-session logic over an abstract link), a SwiftUI Dock app (`LabelBridgeApp`: owns CoreBluetooth, the job queue, the window, a Unix-socket server for the CLI and a loopback PDF listener for CUPS), and a thin CLI (`labelbridge`) that talks to the app over the socket. Scripts bundle, sign, notarize and package a .dmg.

**Tech Stack:** Swift 6 / SwiftPM, SwiftUI + AppKit (Core Text), CoreBluetooth, PDFKit, Network/POSIX sockets, swift-argument-parser, XCTest, CUPS (`lpadmin`), `hdiutil`, `notarytool`, jj.

**Spec:** `docs/superpowers/specs/2026-11-22-labelbridge-design.md`

## Global Constraints

- macOS 13+, universal binary (arm64 + x86_64). Regular **Dock app** with a main window (not a menu-bar app).
- Names: app `LabelBridge.app`, bundle id `io.github.hayek.labelbridge`, CLI `labelbridge`, repo `hayek/labelbridge`, CUPS queue `NIIMBOT_D11` described as "NIIMBOT D11 (Bluetooth)".
- Socket: `~/Library/Application Support/LabelBridge/labelbridge.sock`, mode 0600. CUPS loopback port: `127.0.0.1:9183` (PeriPage Bridge uses 9181). Accept only data starting with `%PDF`.
- Printer: BLE name prefix `D11`, service `E7810A71-73AE-499D-8C15-FAA9AEF0C3F2`, characteristic `BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F`; 300 dpi; head 142 px (rows padded to 144 cols); print direction "left"; density 1–5, default 3; 2 mm safety margin at each label end.
- Label sizes (W×L mm): 15×50 (default), 12×40, 14×40, 15×30, 12×22, 14×22, 15×40, plus custom. Printable height is always min(W, 12 mm) → 142 px, centered.
- Input is one label per line; a literal `\n` in an item is a line break on that label. Blank/whitespace-only items are skipped.
- CLI exit codes: 0 printed · 2 bad input · 3 printer not found/busy · 4 failed mid-job (report printed count) · 5 app not available. `--json` → `{ok, printed, total, warnings[], error?}`.
- Signing identity, notary credentials: environment variables only (`SIGN_ID`, `NOTARY_PROFILE` or `ASC_KEY_PATH`/`ASC_KEY_ID`/`ASC_ISSUER_ID`). No personal names, IDs or paths in committed files.
- Protocol reference MultiMote/niimbluelib (MIT): credit in README.
- VCS: jj (colocated). Commits as `hayek <217989+hayek@users.noreply.github.com>`; messages end with the Co-Authored-By / Claude-Session lines.

## Review Focus

1. **Blank or whitespace-only lines in a pasted list:** skipped, never printed as empty labels; the result reports how many were skipped. → test in Task 3 (`testBatchSkipsBlankItems`).
2. **Text too long for the label:** shrinks to the minimum size, then truncates with "…" and returns a warning; ink never reaches the 2 mm end margins. → Task 3 (`testLongTextTruncatesWithinMargins`).
3. **Mixed-direction and complex scripts** ("דנה 3א", "محمد 12", "東京", "🎉 Party"): renders without crashing, ink present, and leading alignment for RTL lands on the right. → Task 3 (`testMixedScriptsRender`, `testLeadingAlignmentFollowsRTL`).
4. **Printer drops or stops replying mid-batch** (turned off, phone grabs it): the session fails within a bounded time with `.failedMidJob(printed:)`, never hangs. → Task 4 (`testLinkDropMidBatchReportsPrintedCount`).
5. **Two jobs arrive at once** (CLI while the window is printing, or a Print-dialog job): jobs run one after another, never interleaved on the link. → Task 6 (`testJobsAreSerialized`).

---

### Task 1: Package scaffold and NIIMBOT packets

**Files:**
- Create: `Package.swift`, `Sources/LabelCore/Packet.swift`, `Sources/LabelCore/FrameParser.swift`, `Tests/LabelCoreTests/PacketTests.swift`, `.gitignore` (`.build/`, `build/`, `*.app`, `*.dmg`)

**Interfaces:**
- Produces: `enum Cmd: UInt8` (connect 0xC1, setLabelType 0x23, setDensity 0x21, printStart 0x01, printStatus 0xA3, setPageSize 0x13, bitmapRow 0x85, emptyRow 0x84, pageEnd 0xE3, printEnd 0xF3, heartbeat 0xDC); `struct Packet { cmd: UInt8; data: [UInt8]; func bytes() -> [UInt8]; static func u16(_: Int) -> [UInt8] }` (default data `[1]`, Connect prefixed with `0x03`); `Packet.expectedReply(for: Cmd) -> UInt8?` (cmd+0x10 for commands that reply, nil for rows); `struct FrameParser { mutating func feed(_: [UInt8]) -> [Packet] }`.
- Package products: library `LabelCore`, executables `LabelBridgeApp`, `labelbridge`; dependency swift-argument-parser ≥ 1.3.

- [ ] **Step 1: Write failing tests** — `testDensityPacketBytes`: `Packet(cmd: 0x21, data: [3]).bytes() == [0x55,0x55,0x21,0x01,0x03,0x23,0xAA,0xAA]`; `testConnectHasPrefix`: first byte `0x03`, then `55 55 C1 01 01 C1 AA AA`; `testExpectedReplies`: setDensity→0x31, printStart→0x02, pageEnd→0xE4, printStatus→0xB3, bitmapRow→nil; `testParserSplitsAndJoinsFrames`: feeding `55 55 31 01 01 31 AA AA 55 55` then `02 01 01 02 AA AA` yields two packets (0x31 and 0x02); garbage bytes before a frame are skipped.
- [ ] **Step 2: Run** `swift test --filter PacketTests` — expected: FAIL (types missing).
- [ ] **Step 3: Implement** `Packet`, `Cmd`, `FrameParser` (checksum = XOR of cmd, len, data; drop frames with bad checksum).
- [ ] **Step 4: Run** `swift test --filter PacketTests` — expected: PASS.
- [ ] **Step 5: Commit** `jj describe -m "LabelCore: NIIMBOT packet encoding and frame parser" && jj new`

### Task 2: Row encoder

**Files:**
- Create: `Sources/LabelCore/Bitmap.swift`, `Sources/LabelCore/RowEncoder.swift`, `Tests/LabelCoreTests/RowEncoderTests.swift`

**Interfaces:**
- Produces: `struct Bitmap { width: Int; height: Int; isBlack(x:y:) -> Bool; init(width:height:pixels: [Bool]) }` (landscape: width = label length px, height = 142); `struct EncodedPage { rows: Int; cols: Int; packets: [Packet] }`; `RowEncoder.encode(_ bitmap: Bitmap) -> EncodedPage`.

- [ ] **Step 1: Write failing tests** — `testRotationMapping`: a 10×142 bitmap with only pixel (x: 2, y: 141) black → the row at pos 2 has byte 0 == 0x80 (col 0 = source y 141, MSB first); `testColsPaddedTo144`: cols == 144; `testRunsCompressRepeats`: 300 identical black rows → two bitmapRow packets with repeats 255 and 45; `testBlankRowsUseEmptyRow`: an all-white bitmap → only `0x84` packets; `testPixelCountTotalMode`: a fully black row (142 px) → count bytes `[0, 142, 0]`.
- [ ] **Step 2: Run** `swift test --filter RowEncoderTests` — FAIL.
- [ ] **Step 3: Implement** `RowEncoder.encode` (source pixel for row r, col c is `(x: r, y: height-1-c)`; bitmap row data = `[pos u16, 0, count lo, count hi, repeats, bytes…]`; empty run = `[pos u16, repeats]`; repeats ≤ 255).
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `jj describe -m "LabelCore: rotate and encode bitmaps into printer rows" && jj new`

### Task 3: Label sizes and text renderer

**Files:**
- Create: `Sources/LabelCore/LabelSize.swift`, `Sources/LabelCore/TextRenderer.swift`, `Sources/LabelCore/Batch.swift`, `Tests/LabelCoreTests/TextRendererTests.swift`

**Interfaces:**
- Produces: `struct LabelSize: Codable, Hashable { widthMM: Double; lengthMM: Double; static let builtIn: [LabelSize]; static let defaultSize = LabelSize(15, 50); init?(parsing: String) /* "50x15" or "15x50" → width = smaller */ ; var canvasPixels: (length: Int, height: Int) /* 50mm → 591 × 142 */ }`; `enum Alignment: String, Codable { center, leading, trailing }`; `struct TextStyle: Codable { fontName: String?; bold: Bool; alignment: Alignment }`; `struct RenderResult { bitmap: Bitmap; warning: String? }`; `TextRenderer.render(_ text: String, size: LabelSize, style: TextStyle) -> RenderResult`; `Batch.items(from: String) -> (items: [String], skipped: Int)` (split lines, unescape literal `\n`, drop blank).

- [ ] **Step 1: Write failing tests** — `testCanvasFor15x50`: (591, 142); `testParseSize`: "50x15" and "15x50" both → width 15 length 50, "abc" → nil; `testBatchSkipsBlankItems`: "Dana\n\n  \nYossi" → ["Dana","Yossi"], skipped 2; `testEscapedNewline`: "Dana\\nCohen" → one item containing "\n"; `testInkStaysInsideEndMargins`: render "WWWWWWWW" → no black pixel in x < 24 or x ≥ 567 (2 mm = 24 px); `testLongTextTruncatesWithinMargins`: 200-char string → warning non-nil, margins still clean; `testMixedScriptsRender`: each of "דנה 3א", "محمد 12", "東京", "🎉 Party" renders with ink and no warning; `testLeadingAlignmentFollowsRTL`: "שלום" with `.leading` has its ink centroid in the right half, "Hello" with `.leading` in the left half; `testTwoLinesUseTwoBands`: "A\nB" has ink in both the top and bottom halves.
- [ ] **Step 2: Run** `swift test --filter TextRendererTests` — FAIL.
- [ ] **Step 3: Implement** — draw into an 8-bit gray `NSBitmapImageRep` (white background, threshold < 128 = black) with `NSAttributedString` + `NSParagraphStyle` (`baseWritingDirection = .natural`; leading/trailing mapped per paragraph direction); binary-search the largest font size whose bounding rect fits (length − 2×24 px) × 142 px; minimum 14 px, then truncate with `lineBreakMode = .byTruncatingTail` and set the warning.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `jj describe -m "LabelCore: label sizes, batch parsing and auto-fit text rendering (RTL-aware)" && jj new`

### Task 4: Print session over an abstract link

**Files:**
- Create: `Sources/LabelCore/PrinterLink.swift`, `Sources/LabelCore/PrintSession.swift`, `Tests/LabelCoreTests/PrintSessionTests.swift`, `Tests/LabelCoreTests/SimulatedPrinter.swift`

**Interfaces:**
- Consumes: `Packet`, `EncodedPage` (Tasks 1–2).
- Produces: `protocol PrinterLink: AnyObject { func send(_ bytes: [UInt8]) async throws; var replies: AsyncStream<Packet> { get }; func close() async }`; `struct PrintSettings: Codable { density: Int; copies: Int }`; `enum PrintError: Error, Equatable { notFound, busy, failedMidJob(printed: Int), timeout }`; `final class PrintSession { init(link: PrinterLink, replyTimeout: Duration = .seconds(2), statusTimeout: Duration = .seconds(20)); func run(pages: [EncodedPage], settings: PrintSettings, progress: (Int, Int) -> Void) async throws -> Int /* labels printed */ }`.
- Sequence (from spec): connect → labelType 1 → density → printStart(pages × copies total, color 0, speed 1) → per page: printStatus (no wait), setPageSize13b(rows, cols, copies), rows with ~10 ms spacing, pageEnd (retry ×5) → poll printStatus every 300 ms until the page counter reaches the running total → printEnd → heartbeat (no wait).

- [ ] **Step 1: Write failing tests** with `SimulatedPrinter: PrinterLink` (replies cmd+0x10 with `[1]`; printStatus returns the page counter it advances after each pageEnd): `testSingleLabelSequence` asserts the command order exactly; `testThreeLabelsOneSession`: one connect/printStart (total pages 3), three setPageSize/pageEnd, returns 3, progress ends at (3, 3); `testCopiesMultiplyTotal`: copies 2 × 2 pages → printStart total 4; `testLinkDropMidBatchReportsPrintedCount`: simulator stops replying after page 2 → throws `.failedMidJob(printed: 2)` within 25 s of fake time; `testNoConnectReplyIsBusy`: no reply to connect → `.busy`.
- [ ] **Step 2: Run** `swift test --filter PrintSessionTests` — FAIL.
- [ ] **Step 3: Implement** `PrintSession.run` (one reply waiter at a time; unsolicited packets logged and ignored).
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `jj describe -m "LabelCore: print session with multi-page jobs and bounded failures" && jj new`

### Task 5: Bluetooth link and hardware check

**Files:**
- Create: `Sources/LabelBridgeApp/Bluetooth/BLEPrinterLink.swift`, `Sources/LabelBridgeApp/Bluetooth/PrinterScanner.swift`

**Interfaces:**
- Consumes: `PrinterLink`, `PrintSession`, `TextRenderer`, `RowEncoder`.
- Produces: `final class PrinterScanner { func findPrinter(timeout: Duration) async throws -> CBPeripheral /* name prefix "D11" or service UUID; throws PrintError.notFound */ ; var state: AsyncStream<PrinterState> }`; `enum PrinterState { unauthorized, poweredOff, searching, found(name: String), printing(Int, Int), notFound }`; `final class BLEPrinterLink: PrinterLink { static func connect(_ p: CBPeripheral) async throws -> BLEPrinterLink }` (write without response, notifications parsed with `FrameParser`).

- [ ] **Step 1: Add a hidden debug launch argument** `--debug-print "<text>" <count> <copies>` to the app target that renders, encodes and runs a `PrintSession` once, logging to `~/Library/Logs/LabelBridge.log`.
- [ ] **Step 2: Build an ad-hoc dev bundle** (`scripts/build.sh` from Task 10 is not ready yet: use `swift build -c release` and the bundle layout from Task 10's Info.plist; sign with `$SIGN_ID` so Bluetooth permission survives rebuilds).
- [ ] **Step 3: Hardware check with the owner** — run `--debug-print "Test" 3 1`, then `"Test" 1 2`. Expected: 3 labels, then 2 identical labels, each centered on 15×50 mm; ask the owner for a photo. Then with the phone app connected: expected log `notFound` or `busy` within 20 s. Record the observed behaviour in `docs/PROTOCOL.md` (create it: GATT table, packet sequence, multi-page and copies findings).
- [ ] **Step 4: If multi-page or copies behave differently**, adjust `PrintSession` and its tests to match the hardware, re-run `swift test`.
- [ ] **Step 5: Commit** `jj describe -m "App: Bluetooth link for the D11 and verified multi-label printing" && jj new`

### Task 6: Dock app, job queue and main window

**Files:**
- Create: `Sources/LabelBridgeApp/LabelBridgeApp.swift`, `Sources/LabelBridgeApp/PrintService.swift`, `Sources/LabelBridgeApp/Settings.swift`, `Sources/LabelBridgeApp/Views/MainWindow.swift`, `Sources/LabelBridgeApp/Views/LabelPreview.swift`, `Sources/LabelBridgeApp/Views/SettingsView.swift`, `Tests/LabelCoreTests/PrintServiceTests.swift` (PrintService's queue logic lives in `Sources/LabelCore/JobQueue.swift` so it is testable)

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: `struct LabelJob: Codable { items: [String]; size: LabelSize; style: TextStyle; settings: PrintSettings; source: JobSource /* window, cli, cups */ }`; `struct JobResult: Codable { ok: Bool; printed: Int; total: Int; skipped: Int; warnings: [String]; error: String? }`; `actor JobQueue { init(makeLink: @escaping () async throws -> PrinterLink); func submit(_ job: LabelJob, progress: @Sendable (Int, Int) -> Void) async -> JobResult }`; `@MainActor final class PrintService: ObservableObject { @Published state: PrinterState; func print(_ job: LabelJob) async -> JobResult }`; `Settings` (UserDefaults: default size 15×50, density 3, font nil, alignment center, openAtLogin true, keepConnected false — when true, `JobQueue` keeps the link open between jobs instead of closing it).

- [ ] **Step 1: Write failing tests** — `testJobsAreSerialized`: two jobs submitted concurrently to a `JobQueue` over a recording fake link → the link sees job A's printEnd before job B's connect; `testResultCountsSkippedAndWarnings`: items ["A", "", "<200 chars>"] → printed 2, skipped 1, warnings 1.
- [ ] **Step 2: Run** `swift test --filter PrintServiceTests` — FAIL.
- [ ] **Step 3: Implement** `JobQueue` (render with `TextRenderer`, encode with `RowEncoder`, run one `PrintSession` per job) and `PrintService` wrapping it.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Build the window** (SwiftUI `WindowGroup`, regular activation policy, closing the window keeps the app running): status line from `PrintService.state`; `TextEditor` (one label per line, accepts RTL); size picker (built-ins + custom), density stepper 1–5, copies, alignment, font; a preview strip of the first 6 labels rendered by `TextRenderer` at true proportion; Print button with "Label N of M" progress and an error banner. Settings window (⌘,) and "Open Log" menu item.
- [ ] **Step 6: Manual check** — launch, paste "Dana\nיוסי\nمحمد", preview shows three labels with correct RTL, Print produces three labels.
- [ ] **Step 7: Commit** `jj describe -m "App: Dock app with batch label window and serialized job queue" && jj new`

### Task 7: CLI and socket IPC

**Files:**
- Create: `Sources/LabelCore/IPC.swift`, `Sources/LabelBridgeApp/IPCServer.swift`, `Sources/labelbridge/main.swift`, `Sources/labelbridge/Commands.swift`, `Sources/labelbridge/IPCClient.swift`, `Tests/LabelCoreTests/IPCTests.swift`

**Interfaces:**
- Consumes: `LabelJob`, `JobResult`, `Batch`, `TextRenderer`, `LabelSize`.
- Produces: `enum IPCRequest: Codable { print(LabelJob), status }`, `enum IPCMessage: Codable { progress(Int, Int), result(JobResult), status(StatusInfo) }` framed as newline-delimited JSON; `IPCPaths.socketURL`; `IPCServer(service:)` listening on the socket (mode 0600); CLI subcommands `print`, `preview`, `status`, `sizes` per the spec's CLI section.

- [ ] **Step 1: Write failing tests** — `testRequestRoundTrip` (encode/decode `print` with Hebrew items); `testServerClientRoundTrip`: an `IPCServer` on a temp socket path with a fake service returning `printed 2` → client receives progress then result; `testExitCodes`: mapping `JobResult`/`PrintError` → 0, 3 (notFound/busy), 4 (failedMidJob), 2 (no items), 5 (connection refused after launch wait).
- [ ] **Step 2: Run** `swift test --filter IPCTests` — FAIL.
- [ ] **Step 3: Implement** server, client and commands: arguments, `--file`, `-` for stdin; `--size --density --copies --align --font --bold --dry-run --json`; progress lines to stderr; `preview --out DIR` writes `label-001.png`… locally without the app; if the socket is missing run `open -g -b io.github.hayek.labelbridge` and wait up to 10 s.
- [ ] **Step 4: Run** — PASS; then manually `labelbridge print "Dana" "דנה" --json` prints two labels and outputs `{"ok":true,"printed":2,...}`.
- [ ] **Step 5: Commit** `jj describe -m "CLI: labelbridge print/preview/status over a private Unix socket" && jj new`

### Task 8: Print-dialog printer (CUPS)

**Files:**
- Create: `Resources/NIIMBOT_D11.ppd`, `Sources/LabelBridgeApp/CUPSListener.swift`, `Sources/LabelCore/PDFLabels.swift`, `Tests/LabelCoreTests/PDFLabelsTests.swift`

**Interfaces:**
- Consumes: `JobQueue`, `LabelSize`, `RowEncoder`.
- Produces: `PDFLabels.bitmaps(from data: Data, size: LabelSize) throws -> [Bitmap]` (each page fitted, aspect kept, centered inside the margins); `CUPSListener(port: 9183, service:)` accepting only payloads starting with `%PDF`; PPD with `*cupsFilter2: "application/pdf application/pdf 0 -"`, `*PageSize`/`*PaperDimension` entries for every built-in size named like `15x50mm` (width × length in points, e.g. 42.52 × 141.73 for 15×50), default `15x50mm`.

- [ ] **Step 1: Spike** — install the PPD by hand: `lpadmin -p NIIMBOT_D11_TEST -E -v socket://127.0.0.1:9183 -P Resources/NIIMBOT_D11.ppd`; run `nc -l 9183 > /tmp/job.bin`; print from TextEdit. Expected: `/tmp/job.bin` starts with `%PDF`. If not (raster arrives), switch the PPD to `application/vnd.cups-raster` and make `PDFLabels` a raster decoder instead; note the result in `docs/PROTOCOL.md`. Remove the test queue.
- [ ] **Step 2: Write failing tests** — `testTwoPagePDFGivesTwoLabels` (generate a 2-page PDF with Core Graphics) → 2 bitmaps of 591×142; `testRejectsNonPDF`: data "POST / HTTP/1.1" → throws.
- [ ] **Step 3: Run** `swift test --filter PDFLabelsTests` — FAIL.
- [ ] **Step 4: Implement** `PDFLabels` and `CUPSListener` (read to EOF, submit a `.cups` job, close the socket when the job finishes).
- [ ] **Step 5: Run** — PASS; then print a document from TextEdit to "NIIMBOT D11 (Bluetooth)" with 50×15 selected → one centered label.
- [ ] **Step 6: Commit** `jj describe -m "Print dialog: CUPS queue with PDF pass-through to the D11" && jj new`

### Task 9: First-launch setup

**Files:**
- Create: `Sources/LabelBridgeApp/Setup/SetupFlow.swift`, `Sources/LabelBridgeApp/Views/SetupView.swift`

**Interfaces:**
- Consumes: `PrinterScanner`, `PrintService`, `Settings`, the PPD resource.
- Produces: `SetupFlow.needsSetup() -> Bool`; `SetupFlow.run()` steps: offer moving to `/Applications` (`NSWorkspace` + relaunch); Bluetooth permission (explain, then trigger); add CUPS queue (`lpadmin`, admin prompt via `osascript … with administrator privileges` on failure); CLI symlink `/usr/local/bin/labelbridge` → `Contents/MacOS/labelbridge` (one admin prompt; if declined, show the full path); `SMAppService.mainApp.register()` when `openAtLogin`; find the printer and offer a test label. Settings has "Repair setup" and "Uninstall" (remove queue, symlink, login item).

- [ ] **Step 1: Implement** the flow and view; every step reports success/failure in the view.
- [ ] **Step 2: Manual check on this Mac** — remove existing queue/symlink, launch from a copy outside `/Applications`: all six steps complete; `which labelbridge` resolves; `lpstat -p NIIMBOT_D11` succeeds; test label prints. Then "Uninstall" removes all three.
- [ ] **Step 3: Commit** `jj describe -m "App: first-launch setup, repair and uninstall" && jj new`

### Task 10: Build, sign, notarize, .dmg

**Files:**
- Create: `Resources/Info.plist` (bundle id, `LSMinimumSystemVersion` 13.0, `NSBluetoothAlwaysUsageDescription`, regular app), `Resources/AppIcon.icns`, `scripts/build.sh`, `scripts/notarize.sh`, `scripts/make-dmg.sh`

**Interfaces:**
- Produces: `build/LabelBridge.app` (universal; `Contents/MacOS/LabelBridge` + `Contents/MacOS/labelbridge`; PPD in Resources); `build/LabelBridge.dmg` (app + Applications symlink), signed, notarized, stapled.

- [ ] **Step 1: Implement** `build.sh` (`swift build -c release --arch arm64 --arch x86_64`, assemble bundle, sign nested CLI then app with hardened runtime using `$SIGN_ID`, default ad-hoc `-`), `make-dmg.sh` (`hdiutil create -format UDZO`), `notarize.sh` (adapt `peripage-bridge/scripts/notarize.sh`: submit the .dmg, staple the .dmg).
- [ ] **Step 2: Verify** — `spctl -a -vv -t open --context context:primary-signature build/LabelBridge.dmg` → "accepted, source=Notarized Developer ID"; mount it on this Mac, drag to Applications, launch: setup runs.
- [ ] **Step 3: Commit** `jj describe -m "Release: universal build, signing, notarized dmg" && jj new`

### Task 11: Docs and release

**Files:**
- Create: `README.md`, `LICENSE` (MIT, "hayek"), `docs/banner.png`, `docs/social-preview.png` (1280×640, < 1 MB)
- Modify (other repo): `~/Developer/PeriPageBridge/README.md` — add "See also: LabelBridge".

- [ ] **Step 1: Write README** — what it is, install from the .dmg, the window, CLI reference with the agent instruction line ("To print labels, run `labelbridge print --json` with one label per argument"), sandbox note (exit 5 and what to allow), label sizes, RTL note, troubleshooting (phone app connected), build from source, credit to niimbluelib, not affiliated with NIIMBOT.
- [ ] **Step 2: Banner** — ask the owner for a photo of the D11 with a printed label; cut out with Vision and compose like peripage-bridge's banner (title, tagline, four features: batch labels, any language incl. RTL, CLI for AI agents, Print dialog); strip metadata; render 1920×1080 and 1280×640.
- [ ] **Step 3: Scan for personal data** — `grep -rn -i -E "<team id>|<key id>|<issuer>|/Users/" .` over committed files → no hits.
- [ ] **Step 4: Publish (owner already approved open-sourcing)** — `gh repo create hayek/labelbridge --public`, push with jj (`jj git push`), `gh release create v1.0.0 build/LabelBridge.dmg`, upload social preview in repo settings, add the PeriPage "See also" link and push.
- [ ] **Step 5: Commit** `jj describe -m "Docs: README, banner and release" && jj new`
