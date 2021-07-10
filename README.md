
# Syzygy.jl

Probing code for [Syzygy](https://syzygy-tables.info) tablebases based on [Python Chess Syzygy](https://github.com/niklasf/python-chess/blob/master/chess/syzygy.py
).

Download tablebases from [here](https://chess.massimilianogoi.com/download/tablebases/).

## Installation
```
(@v1.6) pkg> add https://github.com/markus7800/Syzygy.jl.git
```

## Usage
```
using Chess
using Syzygy

tb = open_tablebase("syzygy/3-4-5")

b = fromfen("8/2K5/4B3/3N4/8/8/4k3/8 b - - 0 1")

probe_wdl(tb, b)

probe_dtz(tb, b)

```
