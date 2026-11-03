# tuibox

Ada binding to [tuibox](https://github.com/Cubified/tuibox), a small
mouse-aware TUI library in one C header. `Tuibox` in `src/tuibox.ads` is
the API, and its header comment lists what the library expects of you.

`vendor/tuibox.h` is upstream commit `28035a9`, unmodified.
`src/tuibox_stub.c` compiles it and wraps what Ada cannot call directly.

Upstream has no license file and no license statement in its README or
header, apart from the MIT notice on the `vec.h` part. The Apache-2.0 in
`alire.toml` covers this binding only. Sort out the terms with upstream
before publishing this crate or redistributing it.
