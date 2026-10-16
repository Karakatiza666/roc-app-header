# roc-app-header

Read and edit the header of a Roc app, package or platform, scan its `import` lines, read a package release URL, and do the minimal version selection (MVS) of the Roc compiler. Pure Roc, no dependencies.

| Module | Functions | Result |
| --- | --- | --- |
| `Header` | `parse`, `kind`, `exposed`, `entries`, `span` | The header kind (`App`, `Package`, `Platform`), the exposed names, and each dependency entry with the byte span of the entry and of its value (end not included) |
| `Header` | `set_value`, `add_entry`, `remove_entry` | New source text. An edit changes only the bytes of its entry. All other bytes, comments and the layout stay the same. |
| `Imports` | `scan` | Each `import` line: `Local` or `Package(alias)`, the module name, the line |
| `PackageUrl` | `parse`, `to_str`, `version`, `hash`, `url_form`, `series`, `group` | The one `X.Y.Z` run in the URL, the hash, and the group key |
| `Mvs` | `select` | One URL for each group: the highest version that the build needs, or the conflicts |

## Package URL rules

| Rule | Example |
| --- | --- |
| The version is the one `X.Y.Z` run in the URL. No run, two runs, or `0.0.0` is an error. | `.../download/4.2.0/<hash>.tar.zst` is `4.2.0` |
| The series is the major, or `0.minor` below 1.0 | `4.2.0` is `4`, `0.25.1` is `0.25` |
| The group is the URL with no scheme, `{v}` in place of the run and no hash, plus the series | `github.com/roc-lang/unicode/releases/download/{v}/` and `4` |
| The text around the run is part of the group | Tags `v1.2.0` and `1.2.0` give two groups |

`Mvs.select` errors: `Cycle`, `RootConflict`, `ContentConflict` (two hashes for one version), `VersionConflict`, `PlatformMismatch`.

## Usage

Add the release to the header of your app, package or platform:

```roc
header: "https://github.com/Karakatiza666/roc-app-header/releases/download/0.1.0/HDQnwrX2Bcm8Jsf8RMC9ZdbVGwPiqD2nCLP7Zf1osfgU.tar.zst",
```

Then:

```roc
import header.Header
import header.Imports
import header.PackageUrl

expect {
	url = PackageUrl.parse("https://github.com/roc-lang/unicode/releases/download/4.2.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst")?
	url.group() == { form: "github.com/roc-lang/unicode/releases/download/{v}/", series: "4" }
}

expect {
	text = "app [main!] { pf: platform \"https://example.com/1.0.0/abc.tar.zst\" }\n"
	edited = Header.set_value(text, "pf", "https://example.com/1.1.0/def.tar.zst")?
	edited == "app [main!] { pf: platform \"https://example.com/1.1.0/def.tar.zst\" }\n"
}

expect Imports.scan("import pf.Stdout\nimport Geo\n").map(|i| i.name) == ["Stdout", "Geo"]
```

## Tests

| Layer | Files | Tool |
| --- | --- | --- |
| L0 | `tests/*.roc`. `tests/seeds.roc` compares with real headers (`tests/fixtures/seeds/`, sources and licenses in `SOURCES.tsv`) and with the output of `roc fmt`. | `roc test` |
| L1 | `fuzz/*.roc` (properties: parse never crashes, an edit changes only its span, parse after an edit, the group key, MVS against an independent oracle) | [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) 0.4.3 |

`scripts/test.sh [ROC [FUZZ_ROC]]` runs `roc check`, `roc fmt --check`, the L0 tests and the L1 targets. `scripts/seeds.sh` makes the expected seed values again with `roc`. Use the nightly in `.roc-version`. CI (`.github/workflows/ci.yml`) runs the same checks on that nightly.

This package is a clean-room rewrite. It contains no code from the Roc compiler. It follows the documented behavior of the compiler.

## Release

`.github/workflows/release.yml` makes a release with [roc-lang/release-package](https://github.com/roc-lang/release-package): `gh workflow run release.yml --ref main -f release_version=X.Y.Z`. The tag is `X.Y.Z` with no prefix, and the one package asset is `<hash>.tar.zst` from `roc bundle`.

## License

UPL-1.0, see `LICENSE`.
