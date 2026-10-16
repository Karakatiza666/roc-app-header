app [main!] { pkg: "../package/main.roc" }

import pkg.Imports
import "fixtures/seeds/app-webserver.main.roc.txt" as app_webserver : Str
import "fixtures/seeds/roc-ray-0.10.0.main.roc.txt" as roc_ray : Str

main! = |_args| Ok({})

## The scan result as (from, name, line).
scanned : Str -> List(([Local, Package(Str)], Str, U64))
scanned = |source| Imports.scan(source).map(|i| (i.from, i.name, i.line))

# R-UM1, roc-syntax `imports` topic: a package-qualified import and a local import, with line numbers from 1
expect scanned("app [main!] { pf: platform \"x\" }\n\nimport pf.Stdout\nimport Helper\n") == [(Package("pf"), "Stdout", 3), (Local, "Helper", 4)]

# R-UM1, roc-syntax `imports` topic: `.` after the module selects a nested type, so the module is the first name
expect scanned("import json.Parser.ParseErr as PE\nimport Url.ParseErr\n") == [(Package("json"), "Parser", 1), (Local, "Url", 2)]

# R-UM1, roc-syntax `imports` topic: `/` selects a file in a subdirectory, and `as` and `exposing` do not change the module
expect scanned("import Internal/Nibble as Nibble\nimport Http exposing [Request, Response]\nimport pkg.Json exposing [to_str]\n") == [(Local, "Internal/Nibble", 1), (Local, "Http", 2), (Package("pkg"), "Json", 3)]

# R-UM1, roc-syntax `imports` topic: a path prefix stays in the module name
expect scanned("import ./Internal/Parser\nimport ../Shared/Codec\nimport /Public/Api\n") == [(Local, "./Internal/Parser", 1), (Local, "../Shared/Codec", 2), (Local, "/Public/Api", 3)]

# R-UM1, roc-syntax `imports` topic: a file import names no module
expect scanned("import \"data.json\" as data : Str\nimport \"logo.png\" as logo : List(U8)\nimport Color\n") == [(Local, "Color", 3)]

# R-UM1 (lexical scan): an import word in a comment or a doc comment is not an import
expect scanned("# import pf.Old\n## import pf.Doc\nimport pf.Stdout # import pf.Tail\n") == [(Package("pf"), "Stdout", 3)]

# R-UM1 (lexical scan): an import word in a string or a multi-line string is not an import
expect scanned("x = \"import pf.Str\"\ny =\n\t\\\\import pf.Multi\n\t\\\\more\nimport pf.Real\n") == [(Package("pf"), "Real", 5)]

# R-UM1 (lexical scan): a word that starts with import is not an import
expect scanned("importer = 5\nimports = [1]\n") == []

# R-UM1 (lexical scan): the word import must end before the module name, so importFoo is not an import of Foo
expect scanned("importFoo = 1\nimport\tBar\n") == [(Local, "Bar", 2)]

# R-UM1, R-LD7: a type module with no header (layout-probe Hex.roc)
expect scanned("import Internal/Nibble as Nibble\n\n## Lowercase hex text for bytes.\nHex :: [].{\n\tencode = |_b| \"\"\n}\n") == [(Local, "Internal/Nibble", 1)]

# R-UM1: a file with no import
expect scanned("main! = |_args| Ok({})\n") == []

# R-UM1, R-RV2 (seed app-webserver): the import lines of a real app, as the file shows them
expect scanned(app_webserver) == [(Package("pf"), "Stdout", 7), (Package("pf"), "Server", 8), (Package("pf"), "UnixTime", 9), (Package("http"), "Response", 10)]

# R-UM1, R-LD7 (seed roc-ray-0.10.0): 35 local imports on lines 228 to 262. The 3 imports in the doc comment on lines 29 to 31 do not count.
expect {
	found = scanned(roc_ray)
	found.len() == 35 and found.first() == Ok((Local, "Draw", 228)) and found.last() == Ok((Local, "Permission", 262)) and found.all(|(from, _, _)| from == Local)
}
