# MP4 / fMP4 Media Source Extensions (outline)

**Status:** outline only — not wired into the Ladybird build yet
(`enableMp4Mse` defaults to `false`).

## Motivation

Ladybird’s packaged build can play many YouTube **VODs** via MSE + WebM/VP9/Opus.
YouTube **live** (e.g. [`yT5Jx87JIGk`](https://www.youtube.com/watch?v=yT5Jx87JIGk))
typically needs **fragmented MP4** (`avc1` / `mp4a`) over MSE. Upstream only ships
`WebMByteStreamParser`; MP4 MSE is still maintainer backlog
([LadybirdBrowser/ladybird#9025](https://github.com/LadybirdBrowser/ladybird/issues/9025)).

This overlay will add a YouTube-capable MP4 MSE subset as a packaging-tree patch
(same pattern as `webauthn/` / `passwordmgr/`). Upstream no longer accepts public PRs.

## Goal

Play YouTube live DASH in Ladybird: audio + video, sustained append/eviction,
basic quality SourceBuffer rebuilds.

## Non-goals (v1)

- Native HLS (`m3u8`)
- H.265 / AV1-in-MP4 MSE
- EME / Widevine
- Full MSE / ISOBMFF WPT compliance
- Upstreamable Ladybird contribution path

## Architecture

```text
YouTube live DASH
  → SourceBuffer.appendBuffer(init|media)
  → MP4ByteStreamParser  (new; MSE ISOBMFF byte-stream format)
  → TrackBufferDemuxer   (existing)
  → PlaybackManager      (existing)
  → FFmpeg H.264 / AAC decoders (existing for progressive MP4)
```

`FFmpegDemuxer` is **not** reused for segment parsing: it expects a continuous
`MediaStream`, not discrete MSE init (`ftyp`/`moov`) + media (`moof`/`mdat`)
appends. FFmpeg stays on the decode side only.

## Milestones

| ID | Name | Exit criteria |
|----|------|---------------|
| **M0** | Gate | `isTypeSupported` accepts `video/mp4` + `audio/mp4` with `avc1`/`avc3`/`mp4a`; stub `MP4ByteStreamParser`; YouTube live creates MP4 SourceBuffers and starts appending (parser may error). **Kill switch:** if YouTube only offers HLS for the target stream, stop before investing in M1. |
| **M1** | fMP4 parser | Init + one video `moof`/`mdat` → `CodedFrame`s in a local harness (recorded YouTube live segments). |
| **M2** | A/V playback | Separate audio/video SourceBuffers; AVCC + `esds` extradata; finite fMP4 MSE clip plays in Ladybird. |
| **M3** | Live | `MediaSource.duration = Infinity` safe through HTML media element + `PlaybackManager`; soak on live URL without leak/crash. |
| **M4** | Package | Overlay applied from `default.nix` when `enableMp4Mse = true`; documented rebuild / manual test checklist. |

## Planned touch points

Overlay copies / patches (against Ladybird pin in `default.nix`):

| Path | Change |
|------|--------|
| `Libraries/LibWeb/MediaSourceExtensions/MP4ByteStreamParser.{h,cpp}` | New parser |
| `Libraries/LibWeb/MediaSourceExtensions/Isobmff/*` | Minimal box reader (`ftyp`, `moov`/`trak`/…, `avcC`, `esds`, `moof`/`traf`/`tfhd`/`tfdt`/`trun`, `mdat`) |
| `Libraries/LibWeb/MediaSourceExtensions/MediaSource.cpp` | Extend `is_type_supported` |
| `Libraries/LibWeb/MediaSourceExtensions/SourceBuffer.cpp` | Construct `MP4ByteStreamParser` for `mp4` subtype |
| `Libraries/LibWeb/CMakeLists.txt` | Add new `.cpp` sources |
| `Libraries/LibMedia/PlaybackManager*` (if needed) | Infinite duration / live edge |

Reference implementation size: upstream `WebMByteStreamParser` is ~330 LOC on top of
an existing Matroska stack. Expect ~1.5–3k LOC for a YouTube-capable fMP4 subset.

## Apply (future)

```bash
./packages/ladybird/mp4mse/apply-overlay.sh /path/to/ladybird
```

Nix package (once M4 lands):

```nix
ladybird.override { enableMp4Mse = true; }
```

## Manual test checklist (when implemented)

- [ ] VOD control: a WebM YouTube video still plays (no regression)
- [ ] Finite fMP4 MSE test page / recorded DASH segments play A/V
- [ ] Live: https://www.youtube.com/watch?v=yT5Jx87JIGk — video + audio start
- [ ] Live soak ≥ 30 minutes (append + SourceBuffer eviction)
- [ ] Quality change / SourceBuffer rebuild does not crash

## Risks

- YouTube live dialect (default-base-is-moof, TFDT, multi-`trun`) may need iteration
- `AK::Duration` / playback pipeline may not tolerate `Infinity` today
- A/V sync across separate SourceBuffers
- AVCC length-prefixed H.264 vs decoder expectations
- Large LibWeb rebuild; keep behind `enableMp4Mse` until M2+
