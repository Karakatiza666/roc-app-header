## A lexical scan of the `import` lines of a Roc module.
Imports :: [].{

	## The module imports of a source file, in source order.
	##
	## An import line is a line whose first word is `import`, outside a
	## comment and outside a string. `from` is `Package(alias)` for
	## `import json.Parser` and `Local` for `import Helper`. `name` is the
	## module name: `Parser` for `import json.Parser.ParseErr as PE`, `Url` for
	## `import Url.ParseErr`, and `Internal/Nibble` for
	## `import Internal/Nibble as Nibble`. A path prefix stays in `name`:
	## `./Internal/Parser`, `../Shared/Codec`, `/Hex`. `line` is the line number of the
	## `import` word, from 1. A file import (`import "data.json" as data : Str`)
	## names no module and is not in the list.
	scan : Str -> List({ from : [Local, Package(Str)], name : Str, line : U64 })
	scan = |source| {
		var $found = []
		var $line = 1
		for text in source.split_on("\n") {
			match import_of(text.to_utf8()) {
				Ok({ from, name }) => {
					$found = $found.append({ from, name, line: $line })
				}

				Err(_) => {}
			}
			$line = $line + 1
		}
		$found
	}
}

is_space : U8 -> Bool
is_space = |b| b == ' ' or b == '\t' or b == '\r'

is_lower : U8 -> Bool
is_lower = |b| b >= 'a' and b <= 'z'

is_upper : U8 -> Bool
is_upper = |b| b >= 'A' and b <= 'Z'

is_digit : U8 -> Bool
is_digit = |b| b >= '0' and b <= '9'

## A byte of a module path: a name, `/` and `.`.
is_path_byte : U8 -> Bool
is_path_byte = |b| is_lower(b) or is_upper(b) or is_digit(b) or b == '_' or b == '/' or b == '.'

## The bytes after the leading spaces and tabs.
drop_spaces : List(U8) -> List(U8)
drop_spaces = |bytes| match bytes.find_first_index(|b| !is_space(b)) {
	Ok(i) => bytes.drop_first(i)
	Err(_) => []
}

## The module of one line, when its first word is `import`.
import_of : List(U8) -> Try({ from : [Local, Package(Str)], name : Str }, [NotImport])
import_of = |line| {
	text = drop_spaces(line)
	keyword = "import".to_utf8()
	if !text.starts_with(keyword) or !is_space(text.get(keyword.len()) ?? 0) {
		return Err(NotImport)
	}
	rest = drop_spaces(text.drop_first(keyword.len()))
	path = rest.take_first(rest.find_first_index(|b| !is_path_byte(b)) ?? rest.len())
	module_of(path)
}

## The text before the first `.` of a list.
before_dot : List(U8) -> List(U8)
before_dot = |bytes| bytes.take_first(bytes.find_first_index(|b| b == '.') ?? bytes.len())

## `alias.Module.Type` gives `Package(alias)` and `Module`. A path such as `../Shared/Codec.Type`
## gives `Local` and `../Shared/Codec`.
module_of : List(U8) -> Try({ from : [Local, Package(Str)], name : Str }, [NotImport])
module_of = |path| match path {
	[first, ..] if is_lower(first) => {
		alias = before_dot(path)
		mod_name = before_dot(path.drop_first(alias.len() + 1))
		match mod_name {
			[m, ..] if is_upper(m) and alias.all(|b| is_lower(b) or is_digit(b) or b == '_') =>
				Ok({ from: Package(Str.from_utf8_lossy(alias)), name: Str.from_utf8_lossy(mod_name) })

			_ => Err(NotImport)
		}
	}

	_ => {
		prefix = path_prefix(path)
		mod_name = before_dot(path.drop_first(prefix))
		match mod_name {
			[m, ..] if is_upper(m) => Ok({ from: Local, name: Str.from_utf8_lossy(path.take_first(prefix + mod_name.len())) })
			_ => Err(NotImport)
		}
	}
}

## The length of a leading `/`, or of leading `./` and `../` parts.
path_prefix : List(U8) -> U64
path_prefix = |path| {
	var $n = 0
	while Bool.True {
		rest = path.drop_first($n)
		if rest.starts_with(['.', '.', '/']) {
			$n = $n + 3
		} else if rest.starts_with(['.', '/']) or ($n == 0 and rest.starts_with(['/'])) {
			$n = $n + if rest.starts_with(['/']) 1 else 2
		} else {
			break
		}
	}
	$n
}
