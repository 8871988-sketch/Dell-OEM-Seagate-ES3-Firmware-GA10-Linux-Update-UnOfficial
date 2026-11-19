# Layout of Dell's `GA10.fwh` and how the header length was found

This page records what was observed in one file: `GA10.fwh` from Dell package HPG73 (1 691 952 bytes, dated 19 Feb 2016). Fields marked "guess" are interpretation, not documentation. Dell does not publish this format.

## Summary

```
+-------------------------------+  offset 0x000
| Dell header, fixed part       |  64 bytes
+-------------------------------+  offset 0x040
| Model table, N entries        |  N x 48 bytes   (N = 5 in GA10.fwh)
+-------------------------------+  offset 0x040 + N*48  = 0x130 = 304
| Seagate LOD image             |  1 691 648 bytes
+-------------------------------+
```

Dell header length = `64 + N * 48`. For `GA10.fwh`: `64 + 5 * 48 = 304` bytes.

## First bytes of `GA10.fwh`

```
00000000  20 20 20 20 44 45 4c 4c  09 47 41 31 30 47 41 30  |    DELL.GA10GA0|
00000010  30 78 02 00 00 00 00 00  00 00 00 00 00 00 00 00  |0x..............|
00000020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00000030  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 05  |................|
00000040  20 20 20 33 30 36 38 39  20 20 20 20 20 20 20 20  |   30689        |
00000050  20 20 20 20 20 20 20 20  20 20 20 20 20 53 54 34  |             ST4|
00000060  30 30 30 4e 4d 30 30 33  33 2d 39 5a 4d 31 37 30  |000NM0033-9ZM170|
00000070  20 20 31 30 30 30 33 30  20 20 20 20 20 20 20 20  |  100030        |
00000080  20 20 20 20 20 20 20 20  20 20 20 20 20 53 54 33  |             ST3|
00000090  30 30 30 4e 4d 30 30 33  33 2d 39 5a 4d 31 37 38  |000NM0033-9ZM178|
000000a0  20 20 31 30 30 30 32 39  20 20 20 20 20 20 20 20  |  100029        |
000000b0  20 20 20 20 20 20 20 20  20 20 20 20 20 53 54 32  |             ST2|
000000c0  30 30 30 4e 4d 30 30 33  33 2d 39 5a 4d 31 37 35  |000NM0033-9ZM175|
000000d0  20 20 31 30 30 30 32 38  20 20 20 20 20 20 20 20  |  100028        |
000000e0  20 20 20 20 20 20 20 20  20 20 20 20 20 53 54 31  |             ST1|
000000f0  30 30 30 4e 4d 30 30 33  33 2d 39 5a 4d 31 37 33  |000NM0033-9ZM173|
00000100  20 20 31 30 31 38 38 36  20 20 20 20 20 20 20 20  |  101886        |
00000110  20 20 20 20 20 20 20 20  20 20 20 20 20 20 53 54  |              ST|
00000120  35 30 30 4e 4d 30 30 30  33 2d 39 5a 4d 31 37 32  |500NM0003-9ZM172|
00000130  00 00 00 00 00 00 00 00  00 00 00 00 00 00 07 00  |................|   <- LOD image starts here
00000140  80 01 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00000150  00 00 00 00 00 d0 19 00  00 00 00 00 00 00 00 00  |................|
00000160  00 00 00 00 00 00 00 00  00 00 00 00 00 00 60 2e  |..............`.|
00000170  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
```

Reproduce with `hexdump -C -n 512 GA10.fwh`.

## Dell header, fixed part (64 bytes)

| Offset | Length | Value in GA10.fwh | Meaning |
|---|---|---|---|
| 0x00 | 8 | `"    DELL"` | Signature: four spaces and `DELL` |
| 0x08 | 1 | `09` | Unknown |
| 0x09 | 4 | `GA10` | Firmware revision contained in the file |
| 0x0D | 4 | `GA00` | Guess: lowest revision the update may be applied to |
| 0x11 | 2 | `78 02` | Unknown |
| 0x13 | 44 | zeros | Padding |
| 0x3F | 1 | `05` | Number of entries in the model table |

## Model table (48 bytes per entry)

Each entry is plain ASCII, padded with spaces:

| Offset in entry | Length | Content |
|---|---|---|
| 0 | 8 | A decimal number, right-aligned. Guess: a Dell component ID |
| 8 | 40 | Drive model string, right-aligned |

Entries in `GA10.fwh`, in file order:

| Number | Model |
|---|---|
| 30689 | ST4000NM0033-9ZM170 |
| 100030 | ST3000NM0033-9ZM178 |
| 100029 | ST2000NM0033-9ZM175 |
| 100028 | ST1000NM0033-9ZM173 |
| 101886 | ST500NM0003-9ZM172 |

One image serves all five capacities.

## Start of the Seagate LOD image (first 64 bytes)

| Offset in LOD | Length | Value | Meaning |
|---|---|---|---|
| 0x0E | 2 | `07 00` | Unknown |
| 0x10 | 2 | `80 01` | Unknown |
| 0x24 | 4 | `00 d0 19 00` | Little-endian 0x0019D000 = 1 691 648: the length of the whole LOD image |
| 0x3E | 2 | `60 2e` | Checksum: chosen so that the 32 little-endian 16-bit words of these 64 bytes add up to 0 (mod 65536) |

All other bytes of this block are zero.

## Why 304 bytes is right: three independent checks

1. **Structure.** The count byte at 0x3F says 5 entries. `64 + 5 * 48 = 304`.
2. **Length.** hdparm only accepts files whose length is a multiple of 512. `1 691 952 mod 512 = 304`, and `1 691 952 - 304 = 1 691 648 = 3304 * 512`.
3. **The LOD's own header.** Taking offset 304 as the start of the LOD image:
   - the 16-bit word sum of its first 64 bytes is `0x0007 + 0x0180 + 0xD000 + 0x0019 + 0x2E60 = 0x10000`, which is 0 mod 65536. At any other tested start offset (208, 256, 272) the sum is not 0;
   - the length stored at LOD offset 0x24 is 1 691 648, exactly the number of bytes that remain after removing 304.

`scripts/fwh2lod.sh` computes the header length from the count byte and then runs checks 2 and 3. It writes the `.lod` file only when both pass.

## Other Dell firmware files

Header lengths reported elsewhere differ (208 and 256 bytes have been mentioned on the HDD Guru forum for other drive families), which fits a variable-length model table: a file listing 4 models would have a `64 + 4 * 48 = 256`-byte header. This has not been verified on real files other than `GA10.fwh`. Newer drive generations also use signed LOD images with a different layout. Do not assume this page describes them, and never flash a file whose checks fail.
