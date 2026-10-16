# mojo-kiln

Kiln is a positional little-endian serializer for [Mojo](https://mojolang.org/). The encoder and the decoder are generated from the fields of a Mojo struct when the program compiles. The bytes do not carry field names.

The library is written in Mojo. It does not wrap a C, C++, or Rust serializer. `spec/reference/kiln_ref.py` is a slow reference codec used to produce golden files. It is not used at run time.

Documentation: [leo-gan.github.io/gld-kiln](https://leo-gan.github.io/gld-kiln/).

## Install

The published package is `mojo-kiln` for linux-64, on [prefix.dev/leo-gan/leo-gan](https://prefix.dev/leo-gan/leo-gan).

```bash
pixi add --channel https://prefix.dev/leo-gan/leo-gan mojo-kiln
```

The import name is `kiln`. The generator command is `gld-kilngen-mojo`.

## Develop

```bash
git clone https://github.com/leo-gan/gld-kiln.git
cd gld-kiln
pixi install
pixi run test
```

If `pixi install` fails with HTTP 401 on `conda.modular.com`, put `PREFIX_API_KEY` in a local `.env` file and run `scripts/ci-setup.sh`. That file is not part of the repository.

## License

MIT. Copyright (c) 2026 Leonid Ganeline.
