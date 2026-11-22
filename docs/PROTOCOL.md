# NIIMBOT D11_H Bluetooth protocol notes

Observed on a NIIMBOT **D11_H** (advertises as `D11_H-<serial>`). Packet format and print sequence follow
[MultiMote/niimbluelib](https://github.com/MultiMote/niimbluelib) (MIT), which documents many NIIMBOT models.

## GATT

| Service | Characteristic | Properties |
|---|---|---|
| `E7810A71-73AE-499D-8C15-FAA9AEF0C3F2` | `BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F` | read, write, write without response, notify |

All commands are written to the characteristic, and replies arrive as notifications on it. Max write is 241 bytes.

## Packets

```
55 55  CMD  LEN  DATA…  CHECKSUM  AA AA        checksum = CMD ^ LEN ^ every DATA byte
```

Commands without arguments send `DATA = 01`. **Connect** (`C1`) is prefixed with one extra byte, `03`.

| Command | Request | Reply |
|---|---|---|
| Connect | `C1` | `C2` |
| Set label type (1 = with gaps) | `23 [type]` | `33` |
| Set density (1–5) | `21 [d]` | `31` |
| Print start | `01 [total u16, 0,0,0,0, color 0, speed 1, 0]` | `02` |
| Print status | `A3` | `B3 [page u16, print %, feed %, …]` |
| Page size | `13 [rows u16, cols u16, copies u16, 0 u16, 0, 0, 0, 0 u16]` | `14` |
| Bitmap row | `85 [pos u16, 0, count lo, count hi, repeats, bytes…]` | none |
| Empty rows | `84 [pos u16, repeats]` | none |
| Page end | `E3` | `E4` |
| Print end | `F3` | `F4` |
| Heartbeat | `DC [1]` | (not awaited) |

All u16 values are big-endian, except the black-pixel count in bitmap rows, which is `[0, lo, hi]`.

## Image

- 300 dpi, **142-pixel** print head (12 mm). Rows are padded to 144 columns (18 bytes), MSB first.
- Print direction "left": a label drawn in reading orientation (width = label length, height = 142) is rotated
  90° clockwise. Printer row `r`, column `c` takes source pixel `(x = r, y = 141 − c)`.
- Identical consecutive rows are sent once with a repeat count (≤ 255).
- On 15×50 mm labels the head covers the middle ~12 mm of the 15 mm height. Leaving **2 mm** clear at each end of the
  label prevents clipping at the leading edge.

## Print sequence (verified)

```
connect → label type 1 → density → print start (total = labels × copies)
for each label:
    print status (not awaited) → page size (rows, 144, copies) → rows (~10 ms apart) → page end
    poll print status every 300 ms until the page counter reaches the running total
print end → heartbeat (not awaited)
```

Hardware results:

- **3 labels in one session:** each label confirmed about 4 s apart; all three printed correctly.
- **Copies:** `copies = 2` in page size with total = 2 prints two identical labels; the counter jumps by 2.
- **Busy:** while the NIIMBOT phone app is connected, the printer stops advertising, so a Mac scan doesn't find it.
  LabelBridge reports "printer not found" after 15 s.

## Print dialog (CUPS)

The bundled PPD (`NIIMBOT_D11.ppd`) declares `*cupsFilter2: "application/pdf application/pdf 0 -"`, so CUPS runs no
driver filter and passes the job through as **PDF** (verified: the bytes arriving on the socket start with `%PDF-1.3`).
The queue uses `socket://127.0.0.1:9183`, where LabelBridge.app renders each PDF page onto one label.
