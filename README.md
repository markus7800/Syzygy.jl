
# Syzygy.jl

Probing code for Syzygy tablebases based on [Python Chess Syzygy](https://github.com/niklasf/python-chess/blob/master/chess/syzygy.py
).

```
tb = open_tablebase("syzygy/3-4-5")

b = fromfen("8/2K5/4B3/3N4/8/8/4k3/8 b - - 0 1")

probe_wdl(tb, b)

probe_dtz(tb, b)

```
