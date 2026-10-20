# Building and testing

Use Godot 4.6.3 standard, plus the matching official export templates.

```sh
godot --headless --path editions/godot --editor --import --quit
godot --path editions/godot
```

Run a unit suite with:

```sh
godot --headless --path editions/godot --script tests/test_gamepad_model.gd
```

Export through Project → Export in the editor. Select a preset and choose an output location outside `editions/godot/`. Web exports need an HTTP server; opening `index.html` directly with a file URL is not supported.

## Packaging caveats

Raw Godot exports do not reproduce the release wrapper and license bundle automatically. Preserve third-party notices in every distribution. Windows builds are unsigned; macOS release builds are not Developer ID notarized. This repository does not claim platform certification or that Windows/macOS runtime tests were executed.

For Night Caretaker, the version-specific loader patch in `scripts/patch-web-loader.py` and associated Node checks must be applied to the Web export. Native import of the three knock reply WAVs must preserve PCM16 for exact phrase assembly.

## Automated checks

The Source checks workflow uses read-only repository permission, a pinned official checkout action and the checksum-verified official Godot 4.6.3 binary. It imports the project, runs a short headless startup and focused regression suites. This is not a release export, graphical playthrough or platform-certification check. CI status should be read from the actual workflow run, not inferred from this file.
