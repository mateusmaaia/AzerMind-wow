# Known issues

## Sending message stalls on Windows

On an affected Windows setup, the addon can stay on **Sending message** while the pixel strip is visible and the bridge reports `capture: attached to ...`. The console may show repeated `strip seen but rejected: checksum` warnings or no matching `strip #N` line. A green connection light means the addon has recently heard from the bridge through a reply slot or presence signal. A matching `(pixel) ... starting` line confirms that an outgoing request reached the bridge.

### Diagnose and recover

1. Keep WoW visible in windowed or borderless mode with the top-left corner unobstructed. Check the bridge console or its redirected stdout for `strip #N`, followed by the request's `(pixel) ... starting` line.
2. Run `/azermind diag` in game to check the sound channel, reply slot polls and connection state. When sharing diagnostics, redact session tokens, private paths and chat text.
3. If the request stays on **Sending message**, run `/reload` when out of combat. The addon saves its pending outbox to SavedVariables for the bridge to read. A matching `(reload) ... starting` line confirms that the fallback delivered the request.

If the reply says **Selected model is at capacity**, the bridge has already dispatched the request to the AI agent. The provider can return that error after either a pixel or a reload submission. Retry later or select another model supported by the installed CLI and account. If changing `agents.codex.model` in `bridge/config.json`, restart the bridge for it to take effect.

### Cause and fix

On the affected machine, Windows GDI returned RGB channel values of 0 for off pixels and 64 for on pixels. The fixed threshold of 128 read both as off. The decoder now calibrates each channel from the known header cells when the default threshold misses the header. It requires sufficient contrast and still checks the full header, length and checksum.

For large frames, decode time plus the capture sleep could exceed the 750 ms each fragment remains visible. Moving the Windows decoder to C# reduced the median decode time for a 2,392-byte frame from 672 ms to 4.2 ms on Windows PowerShell 5.1.

As of 2026-11-12, both Windows reader fixes are in an open pull request. The change passed 164 Node tests and 16 codec cases. In WoW, a live test produced `strip #29`, a `(pixel) ... starting` entry, and `#29 ... done`. The reply appeared in the addon. [Windows capture fix](https://github.com/mateusmaaia/AzerMind-wow/pull/5)

A separate open pull request refreshes the pixel strip scale after the game window is resized. [Window resize fix](https://github.com/mateusmaaia/AzerMind-wow/pull/6)

To apply the Windows reader fix, update to a build containing PR #5 and restart the bridge. For the resize fix, also install the addon files from a build containing PR #6 and run `/reload`. Until the PRs are merged, updating the default branch alone does not include these fixes. A successful `/reload` fallback does not verify the pixel transport: confirm a new request reaches `(pixel) ... starting` and its reply appears without another reload.
