<h1 align="center">pattern.mq</h1>

Search and rewrite Markdown with patterns written as Markdown, as an [mq](https://github.com/harehare/mq) module and a compiled command.
Inspired by [ast-grep](https://ast-grep.github.io/): write the shape you are looking for and bind parts of it with `$VAR` metavariables.

> [!NOTE]
> This module is under development. APIs and behavior may change without notice.

## Quick start

Compile the command once. The `.mqc` format is tied to the mq version, so recompile after upgrading mq.

```sh
mq compile -L . -f cli.mq -o pattern.mqc
```

Search:

```sh
mq pattern.mqc --args pattern '[$text]($url)' docs/*.md
```

```
docs/a.md:12:5
> [docs](http://example.com)
  $text = docs
  $url = http://example.com
```

Preview a rewrite, then apply it:

```sh
P='[$text](http://$rest)'; R='[$text](https://$rest)'
mq pattern.mqc --args pattern "$P" --args rewrite "$R" docs/*.md                    # preview
mq -R -W pattern.mqc --args pattern "$P" --args rewrite "$R" --args write true docs/*.md   # write files
```

`-R` and `-W` grant `read_file` and `write_file`, which only `output doc` and `write` use. Only the matched text is replaced; the rest of the file is kept byte for byte.

## Command line

| Argument | Description |
|---|---|
| `--args pattern P` | Pattern to search for (required unless `--argjson rule` has one) |
| `--args rewrite T` | Template to replace each match with. Without it, matches are printed |
| `--args kind K` | Type of the first matched node: `link`, `image`, `code`, `list`, `h2`, ... |
| `--args lang L` | Language of the first matched node when it is a code block |
| `--args inside H` | Match only under a heading that matches pattern `H`. Its metavariables join the captures |
| `--args not_inside H` | Match only outside headings that match `H` |
| `--argjson constraints '{"u":"^https"}'` | Regex each captured variable must match |
| `--argjson not_constraints '{...}'` | Regex each captured variable must not match |
| `--argjson rule '{...}'` | All of the above as one dict (`pattern`, `kind`, `lang`, `inside`, ...). Other arguments override it |
| `--args output text\|json\|count\|doc` | Output format. Default `text` (`doc` needs `rewrite`). Add `-F json` for valid JSON |
| `--args write true` | Write the rewritten files in place (needs `rewrite`, `-R` and `-W`) |

Quoting:

- Use single quotes so the shell leaves `$` alone.
- Write `\n` for a line break. A blank line (`\n\n`) separates blocks in a multi-node pattern.
- A value starting with `-` is taken as an option by mq. Put a space in front of it: `--args pattern ' - [ ] $item'`. Spaces around patterns and templates are ignored.
- Without a file argument the command reads stdin and reports `<stdin>`. `output doc` and `write` need a file.

## Patterns

- `$name` captures the text at that position (`[A-Za-z_][A-Za-z0-9_]*`). Everything else is matched literally.
- The same name twice must capture the same text: `[$t]($t)`.
- The pattern is parsed as Markdown and matched against the document tree.
  - Links, images and every node with children (headings, list items, emphasis, blockquotes, ...) are compared by kind, attributes and children. `**$x**` does not match `**a** and **b**`, and `- [$t]($u)` does not match an item that has text after the link.
  - Other nodes (text, inline code, code blocks, ...) are compared by their Markdown source.
  - A metavariable that is the only content of a node, as in `[$t]($u)`, `# $title` or `**$x**`, captures all of its children as Markdown source.
  - A metavariable inside other text, as in `See $x now`, captures within that one text node.
  - `$url` captures the url itself (`http://e.org/a_(b)`), not its escaped source.
- Nodes that do not match are searched through their children, so a link inside a heading, a list item, a blockquote or a table cell is found. A match is not searched again inside itself.
- Links and images are compared by text, url and title separately. `[$text]($url)` ignores the title; `[$text]($url "$title")` requires and captures it.
- A list item pattern must say whether it is a task: `- $item` matches only items without a checkbox, `- [ ] $item` only unchecked ones, `- [x] $item` only checked ones. The kind of list (`-` or `1.`) is compared, the nesting level is not.
- The nodes of a pattern match consecutive nodes in order. Separate blocks with a blank line; a code block may contain one.
  - `$$$` skips any number of nodes within the same section (it never crosses a heading).
  - `$$$name` skips them and captures the nodes.
  - A trailing `$$$` takes the rest of the section.
- A table is matched as its cells in order: `| $a | $b |\n|---|---|\n| $c | $d |`.

### Templates

- `$name` and `$$$name` insert the captured text.
- `${name|filter}` transforms it. Filters are `upcase`, `downcase`, `trim`, `capitalize` and `slug`, and can be chained: `${name|slug|upcase}`.
- Unknown names are left as is.
- When a link pattern has no title, the title of the original link is kept.
- Nodes skipped by an unnamed `$$$` are dropped. Use `$$$name` in both the pattern and the template to keep them.

## Cookbook

Replace `http://` links with `https://`:

```sh
mq pattern.mqc --args pattern '[$t](http://$r)' --args rewrite '[$t](https://$r)' README.md
```

Check off every unchecked task:

```sh
mq -R -W pattern.mqc --args pattern ' - [ ] $item' --args rewrite ' - [x] $item' --args write true TODO.md
```

Find a heading and the link right after it:

```sh
mq pattern.mqc --args pattern '# $head\n\n[$text](http://$rest)' doc.md
```

Find links anywhere in a section, with the heading in the result:

```sh
mq pattern.mqc --args pattern '# $head\n\n$$$\n\n[$text](http://$rest)' doc.md
```

Insecure links in the Install section only:

```sh
mq pattern.mqc --args pattern '[$t](http://$r)' --args inside '## Install' doc.md
```

Rust code blocks that contain `unwrap`:

```sh
mq pattern.mqc --args pattern '```$l\n$code\n```' --args lang rust \
  --argjson constraints '{"code":"unwrap"}' docs/*.md
```

Count matches per file:

```sh
mq pattern.mqc --args pattern '[$t]($u)' --args output count docs/*.md
```

Rename a section and keep its body:

```sh
mq pattern.mqc --args pattern '## Install\n\n$$$body' --args rewrite '## Setup\n\n$$$body' README.md
```

## Using it as a module

Copy `pattern.mq` to your mq module directory, or place it anywhere and reference it with `-L`.
HTTP imports work too: `mq --allow-http-import 'import "github.com/harehare/pattern.mq" | ...'`.

```mq
import "pattern"
| .link | pattern::captures("[$text]($url)")   # => {"text": ..., "url": ...} or None
```

| Function | Description |
|---|---|
| `captures(node, pat)` | Named captures of `node` for `pat` as a dict, or `None` when it does not match |
| `matches(node, pat)` | `true` when `node` matches `pat` |
| `replace(node, pat, tmpl)` | Rewrites `node` with `tmpl` when it matches, otherwise returns it as is |
| `find_all(ns, pat)` | Runs of consecutive nodes matching a multi-node pattern, including those inside other nodes: `[{start, end, nodes, captures, title, top, nested}]` |
| `find_rule(ns, rule)` | Like `find_all` with the rule keys `pattern`, `kind`, `lang`, `inside`, `not_inside`, `constraints`, `not_constraints` |
| `replace_all(ns, pat, tmpl)` | Replaces every match in `ns` with the nodes of `tmpl` |
| `replace_rule(ns, rule, tmpl)` | `replace_all` for a rule |
| `rewrite_source(src, ms, tmpl)` | Replaces matches `ms` in the source text `src` and keeps the rest of it |
| `join_nodes(ns)` | Joins nodes back into Markdown using their positions |
| `report(m, file)`, `preview(m, file, text)`, `describe(m, file)` | Text and dict forms used by the command |

`mq -U` needs as many output nodes as input nodes. `replace` fits it for one-to-one rewrites (`mq -U '.link | pattern::replace(...)'`);
`replace_all` and `replace_rule` return a different number of nodes when a template has more or fewer nodes than the match, so use `rewrite_source` or the command for those.
They also replace only top-level matches (`nested` is `false`); `rewrite_source` and the command rewrite nested ones too.

## Known limitations

- Leaf nodes (text, inline code, code blocks, html) are compared by source, so `a *b* c` and `a _b_ c` are the same but `$x` inside a text node cannot span other inline nodes.
- `$$$` cannot cross a heading.
- mq limits nested calls, so `$$$` followed by another block fails with `Maximum recursion depth exceeded` when it has to skip about 5,000 nodes inside one section. Searching and rewriting do not have this limit for the number of nodes, lines or matches in a document.
- `$$$` and `$name` cannot stand for a part of a sequence of inline nodes inside a container, only for all of its children.
- A node that mq reports without a position cannot be rewritten in place.
- Rewriting a list item replaces from its marker.
- `replace_all` and `replace_rule` leave matches inside other nodes alone.

## Testing

```sh
mq-test pattern_tests.mq   # module tests, including what `run` prints for each argument
./e2e.sh                   # builds pattern.mqc and checks arguments, permissions, stdin and large documents
```

## Benchmarks

Benchmarks live in `bench/` and run with `mq-bench` from the [mq repository](https://github.com/harehare/mq). Run them from the repository root, so that `import "pattern"` is found.
Setup runs on every iteration, so each timing includes building the document; `document_only` measures that alone.

```sh
mq-bench bench/benchmarks.mq --iterations 5 --warmup 1           # searching
mq-bench bench/benchmarks_rewrite.mq --iterations 5 --warmup 1   # rewriting and reporting
```

`benchmarks.mq` searches a generated document of 64 sections (headings, links, task items, a blockquote, a code block and a table row each) with single-node, multi-node, gap, `inside` and constraint patterns. `benchmarks_rewrite.mq` measures `rewrite_source`, `replace_all`, `replace_rule`, `join_nodes`, `report` and `describe`.

Measured with the compiled command on a 1.25MB document of 70,000 lines (20,000 links), a search takes several seconds and a document of 300KB takes about one second; a 183-line README takes a few hundredths of a second. The time grows a little faster than the size because matches are collected into one array.
`mq-test` is much slower than the command on large documents, so the large-document checks are in `e2e.sh`.

Compare a change against an earlier run:

```sh
mq-bench bench/benchmarks.mq --format json --output before.json
# change the code, then
mq-bench bench/benchmarks.mq --baseline before.json
```

## Compatibility

Requires [mq](https://github.com/harehare/mq) v0.9 or later.

## License

MIT
