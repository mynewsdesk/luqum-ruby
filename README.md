# Luqum

A Ruby library for parsing, inspecting, and transforming [Lucene query syntax](https://lucene.apache.org/core/3_6_0/queryparsersyntax.html) — the same syntax used by [Solr](https://solr.apache.org/) and the [Elasticsearch query string](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html).

Ported from the Python [luqum](https://github.com/jurismarches/luqum) library.

Use it to:

- Sanity-check queries before passing them to a search engine
- Enforce rules on what a query can and can't contain (e.g. forbid certain fields)
- Rewrite, redact, or inject expressions inside a query
- Pretty-print long queries for logs or UIs
- Compile a Lucene query into Elasticsearch Query DSL JSON

## Table of contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Parsing](#parsing)
- [Manipulating trees](#manipulating-trees)
  - [Direct mutation](#direct-mutation)
  - [The visitor pattern](#the-visitor-pattern)
- [The unknown operation](#the-unknown-operation)
- [Head and tail](#head-and-tail)
- [Pretty printing](#pretty-printing)
- [Transforming to Elasticsearch](#transforming-to-elasticsearch)
  - [Manual configuration](#manual-configuration)
  - [Deriving config from an index mapping](#deriving-config-from-an-index-mapping)
  - [Customizing the generated DSL](#customizing-the-generated-dsl)
- [Named queries](#named-queries)
- [Thread safety](#thread-safety)
- [Exceptions](#exceptions)
- [Development](#development)
- [License](#license)

## Installation

Add it to your `Gemfile`:

```ruby
gem "luqum"
```

Then:

```sh
bundle install
```

Or install it directly:

```sh
gem install luqum
```

Requires Ruby 3.2 or newer.

## Quick start

```ruby
require "luqum"

tree = Luqum::Parser.parse('(title:"foo bar" AND body:"quick fox") OR title:fox')

puts tree
# => (title:"foo bar" AND body:"quick fox") OR title:fox
```

## Parsing

The parser takes a string and returns a tree of `Luqum::Tree` nodes:

```ruby
tree = Luqum::Parser.parse('(title:"foo bar" AND body:"quick fox") OR title:fox')

tree.inspect
# => OrOperation(Group(AndOperation(SearchField("title", Phrase("\"foo bar\"")),
#    SearchField("body", Phrase("\"quick fox\"")))), SearchField("title", Word("fox")))
```

The tree round-trips losslessly — including the original whitespace — back to a string with `#to_s` (and implicitly with `puts` / string interpolation).

The nodes you'll most commonly touch live under `Luqum::Tree`:

| Node | Matches | Example |
| --- | --- | --- |
| `Word` | Bare term | `foo`, `2015-12-19` |
| `Phrase` | Quoted phrase | `"foo bar"` |
| `Regex` | `/…/` regex | `/ab+c/` |
| `SearchField` | `field:expr` | `title:foo` |
| `Group` / `FieldGroup` | Parenthesised expression | `(a OR b)` |
| `AndOperation`, `OrOperation`, `UnknownOperation`, `BoolOperation` | Binary operators | `a AND b`, `a b` |
| `Not`, `Plus`, `Prohibit` | Unary operators | `NOT x`, `+x`, `-x` |
| `Range`, `From`, `To` | Ranges | `[a TO z]`, `>=10` |
| `Fuzzy`, `Proximity`, `Boost` | Modifiers | `foo~1`, `"foo bar"~2`, `foo^3` |

Each node exposes `children`, `pos`, `size`, `head`, and `tail`. Equality (`==`) is structural and recursive.

## Manipulating trees

### Direct mutation

Every child is reachable through `#children` (ordered) or the named accessor (`expr`, `low`/`high`, `operands`, `a`, `term`). Nodes are mutable, so small surgical edits are straightforward:

```ruby
tree = Luqum::Parser.parse('(title:"foo bar" AND body:"quick fox") OR title:fox')
tree.children[0].children[0].children[0].children[0].value = '"lazy dog"'

puts tree
# => (title:"lazy dog" AND body:"quick fox") OR title:fox
```

That's fine for one-off tweaks, but it's tied to the exact shape of the tree. For anything reusable, use a transformer.

### The visitor pattern

`Luqum::Visitor::TreeVisitor` walks a tree and yields values; `TreeTransformer` produces a **new** tree where you can rewrite, drop, or replace nodes as you go.

A visit method is named `visit_<snake_cased_class_name>` (e.g. `visit_search_field`, `visit_or_operation`). It receives `(node, context, &block)` and yields results through the block.

```ruby
require "luqum"

class PhraseRewriter < Luqum::Visitor::TreeTransformer
  def visit_search_field(node, context, &block)
    if node.expr.is_a?(Luqum::Tree::Phrase) && node.expr.value == '"lazy dog"'
      new_node = node.clone_item
      new_node.expr = node.expr.clone_item(value: '"back to foo bar"')
      yield new_node
    else
      generic_visit(node, context, &block)
    end
  end
end

tree = Luqum::Parser.parse('(title:"lazy dog" AND body:"quick fox") OR title:fox')
puts PhraseRewriter.new.visit(tree)
# => (title:"back to foo bar" AND body:"quick fox") OR title:fox
```

A few useful things to know:

- **Yield nothing** from a visit method to drop that subtree from the output.
- **Yield more than one value** to splice multiple children into the parent.
- `generic_visit(node, context, &block)` clones the node and recursively visits its children — call it from `super` (inside `generic_visit`) or directly when you want default behavior for a specific branch.
- Pass `track_parents: true` to the visitor (or `track_new_parents: true` to the transformer) to receive the list of ancestors in `context[:parents]` / `context[:new_parents]`.
- `Luqum::Visitor::PathTrackingVisitor` and `PathTrackingTransformer` automatically populate `context[:path]` with the index of each child along the way — handy for tagging nodes with their location.

## The unknown operation

A bare space between two expressions (`foo bar`) has no defined meaning until Solr/Elasticsearch decides, so luqum keeps it as `UnknownOperation`:

```ruby
Luqum::Parser.parse("foo bar").inspect
# => UnknownOperation(Word("foo"), Word("bar"))
```

`Luqum::Utils::UnknownOperationResolver` rewrites those nodes to `AndOperation`, `OrOperation`, or `BoolOperation` depending on what you want:

```ruby
tree = Luqum::Parser.parse("foo bar")

resolver = Luqum::Utils::UnknownOperationResolver.new
puts resolver.call(tree)
# => foo AND bar

resolver = Luqum::Utils::UnknownOperationResolver.new(resolve_to: Luqum::Tree::OrOperation)
puts resolver.call(tree)
# => foo OR bar
```

## Head and tail

Every node remembers the insignificant characters (mostly whitespace) that surrounded it in the source query, split into `head` (before) and `tail` (after). That's what makes round-tripping through `#to_s` preserve formatting exactly.

If you build a tree by hand, those fields start empty — which means `#to_s` will happily glue everything together without spaces:

```ruby
tree = Luqum::Tree::AndOperation.new(
  Luqum::Tree::Word.new("foo"),
  Luqum::Tree::Not.new(Luqum::Tree::Word.new("bar"))
)

puts tree
# => fooANDNOTbar
```

You can set `head` / `tail` yourself, or let `Luqum::AutoHeadTail.auto_head_tail` do the minimum necessary to make a hand-built tree printable:

```ruby
require "luqum/auto_head_tail"

puts Luqum::AutoHeadTail.auto_head_tail(tree)
# => foo AND NOT bar
```

`auto_head_tail` is idempotent and won't overwrite whitespace you've already set.

## Pretty printing

For long queries, `Luqum::Pretty.prettify` reflows the tree across lines using indent and max-width rules:

```ruby
require "luqum/pretty"

query = 'some_long_field:("some long value" OR "another quite long expression"~2 OR "even something more expanded"^4) AND yet_another_fieldname:[a_strange_value TO z]'
puts Luqum::Pretty.prettify(Luqum::Parser.parse(query))
```

```
some_long_field: (
    "some long value"
    OR
    "another quite long expression"~2
    OR
    "even something more expanded"^4
)
AND
yet_another_fieldname: [a_strange_value TO z]
```

For tighter control, instantiate `Luqum::Pretty::Prettifier` directly:

```ruby
pretty = Luqum::Pretty::Prettifier.new(indent: 2, max_len: 60, inline_ops: true)
puts pretty.call(tree)
```

| Option | Default | Effect |
| --- | --- | --- |
| `indent:` | `4` | Spaces per nesting level |
| `max_len:` | `80` | Target max line length |
| `inline_ops:` | `false` | When `true`, operators stay at end-of-line instead of getting their own line |

## Transforming to Elasticsearch

`Luqum::Elasticsearch::Visitor::ElasticsearchQueryBuilder` turns a Lucene tree into an Elasticsearch Query DSL hash you can send to the ES client of your choice.

### Manual configuration

```ruby
require "luqum"
require "json"

es = Luqum::Elasticsearch::Visitor::ElasticsearchQueryBuilder.new(
  not_analyzed_fields: ["published", "tag"]
)

tree = Luqum::Parser.parse(<<~Q)
  title:("brown fox" AND quick AND NOT dog) AND
  published:[* TO 1990-01-01T00:00:00.000Z] AND
  tag:fable
Q

puts JSON.pretty_generate(es.call(tree))
```

```json
{
  "bool": {
    "must": [
      {
        "bool": {
          "must": [
            { "match_phrase": { "title": { "query": "brown fox" } } },
            { "match":        { "title": { "query": "quick", "zero_terms_query": "all" } } },
            { "bool": { "must_not": [
              { "match": { "title": { "query": "dog", "zero_terms_query": "none" } } }
            ] } }
          ]
        }
      },
      { "range": { "published": { "lte": "1990-01-01T00:00:00.000Z" } } },
      { "term":  { "tag": { "value": "fable" } } }
    ]
  }
}
```

The full set of constructor options:

| Option | Purpose |
| --- | --- |
| `default_field:` | Field to use when a term has no explicit field |
| `default_operator:` | What to do with implicit spaces (`"must"`, `"should"`, …) |
| `not_analyzed_fields:` | Fields treated as exact-match (`term` instead of `match`) |
| `nested_fields:` | Nested-field map (`{ "authors" => %w[name city] }`) |
| `object_fields:` | Dotted object-field paths |
| `sub_fields:` | Multi-fields (e.g. `title.raw`) |
| `field_options:` | Per-field overrides |

### Deriving config from an index mapping

If you already have an ES index mapping, hand it to `SchemaAnalyzer` and let it compute the options:

```ruby
schema = {
  "settings" => { "query" => { "default_field" => "message" } },
  "mappings" => {
    "properties" => {
      "message" => { "type" => "text" },
      "created" => { "type" => "date" },
      "author"  => {
        "type" => "object",
        "properties" => {
          "given_name" => { "type" => "keyword" },
          "last_name"  => { "type" => "keyword" }
        }
      },
      "references" => {
        "type" => "nested",
        "properties" => {
          "link_type" => { "type" => "keyword" },
          "link_url"  => { "type" => "keyword" }
        }
      }
    }
  }
}

options = Luqum::Elasticsearch::SchemaAnalyzer.new(schema).query_builder_options
es = Luqum::Elasticsearch::Visitor::ElasticsearchQueryBuilder.new(**options.transform_keys(&:to_sym))

tree = Luqum::Parser.parse(
  'message:"exciting news" AND author.given_name:John AND references.link_type:action'
)
es.call(tree)
```

### Customizing the generated DSL

Every node in the generated ES tree (`EWord`, `EPhrase`, `ERange`, `EMust`, …) is a plain Ruby class with a `json` method. Swap one out by subclassing the builder and pointing its constants at your replacement:

```ruby
class EWordMatch < Luqum::Elasticsearch::Tree::EWord
  def json
    return super if q == "*"
    { "match" => { field => q } }
  end
end

class MyBuilder < Luqum::Elasticsearch::Visitor::ElasticsearchQueryBuilder
  E_WORD = EWordMatch
end

MyBuilder.new.call(Luqum::Parser.parse("message:* AND author:John AND link_type:action"))
# => { "bool" => { "must" => [
#      { "exists" => { "field" => "message" } },
#      { "match"  => { "author"    => "John" } },
#      { "match"  => { "link_type" => "action" } }
#    ] } }
```

The same pattern works for `E_PHRASE`, `E_RANGE`, `E_NESTED`, `E_BOOL_OPERATION`, `E_MUST`, `E_MUST_NOT`, and `E_SHOULD`.

## Named queries

Named queries let Elasticsearch tell you *which* sub-query matched each document — useful for explaining results to users. `Luqum::Naming.auto_name` walks a tree and assigns a short unique name (`"a"`, `"b"`, …) to each leaf; the ES builder then emits those as `_name` on the generated clauses.

```ruby
tree  = Luqum::Parser.parse("foo~2 OR (bar AND baz)")
names = Luqum::Naming.auto_name(tree)
names
# => { "a" => [0], "b" => [1], "c" => [1, 0, 0], "d" => [1, 0, 1] }

Luqum::Naming.element_from_name(tree, "a", names).inspect
# => 'Fuzzy(Word("foo"), 2)'
```

After your search returns `matched_queries: ["b", "c"]`, propagate those back into the tree and render a visual explanation (HTML by default):

```ruby
matched = %w[b c]

propagate = Luqum::Naming::MatchingPropagator.new
ok, ko = propagate.call(tree, *Luqum::Naming.matching_from_names(matched, names))

Luqum::Naming::HTMLMarker.new.call(tree, ok, ko)
# => '<span class="ok"><span class="ko">foo~2 </span>OR (<span class="ko"><span class="ok">bar </span>AND baz</span>)</span>'
```

## Thread safety

`Luqum::Parser.parse` builds a fresh parser state per call, so it is safe to call concurrently from multiple threads. `Luqum::Thread.parse` is provided as an alias for API parity with the Python library.

## Exceptions

All exceptions live under `Luqum`:

| Exception | When it's raised |
| --- | --- |
| `Luqum::IllegalCharacterError` | The lexer hit a character it can't handle |
| `Luqum::ParseSyntaxError` | Tokens don't fit the grammar (unmatched paren, `AND` at the wrong place, …) |
| `Luqum::ParseError` | Base class for both of the above |
| `Luqum::InconsistentQueryError` | Structural problem — e.g. `OR` and `AND` on the same level |
| `Luqum::NestedSearchFieldError` | A field search nested inside another (e.g. `a:(b:c)`) |
| `Luqum::ObjectSearchFieldError` | Dotted field name used on a non-object field |
| `Luqum::OrAndAndOnSameLevelError` | Ambiguous precedence without parentheses |

`ArgumentError` is used when a caller passes a value the library can't make sense of (e.g. setting a wrong number of children on a node).

## Development

```sh
bundle install
bundle exec rspec
```

The specs are mirrors of the upstream Python test suite and are the primary specification for behavior. If you touch anything, run the full suite — it's fast (< 1s) and covers the whole library end-to-end.

The upstream Python source and tests live in `luqum/` and are kept around as reference. They are not compiled or loaded by the gem.

## License

Dual-licensed under Apache-2.0 and LGPL-3.0-or-later, matching the upstream Python project.
