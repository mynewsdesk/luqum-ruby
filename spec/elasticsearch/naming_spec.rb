RSpec.describe Luqum::Elasticsearch::Visitor do
  def transformer
    @transformer ||= Luqum::Elasticsearch::Visitor::ElasticsearchQueryBuilder.new(
      default_field: "text",
      not_analyzed_fields: ["not_analyzed_field", "text", "author.tag"],
      nested_fields: {
        "author" => %w[name tag],
      },
      object_fields: ["book.title", "author.rewards.name"],
      sub_fields: ["book.title.raw"],
    )
  end

  it "propagates names into match queries" do
    tree = Luqum::Tree::SearchField.new("spam", Luqum::Tree::Word.new("bar"))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      {
        "match" => {
          "spam" => {
            "query" => "bar",
            "_name" => "a",
            "zero_terms_query" => "none",
          },
        },
      },
    )

    tree = Luqum::Tree::SearchField.new("spam", Luqum::Tree::Phrase.new('"foo bar"'))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      {
        "match_phrase" => {
          "spam" => {
            "query" => "foo bar",
            "_name" => "a",
          },
        },
      },
    )
  end

  it "propagates names into term queries" do
    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("bar"))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "term" => { "text" => { "value" => "bar", "_name" => "a" } } },
    )

    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::Phrase.new('"foo bar"'))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "term" => { "text" => { "value" => "foo bar", "_name" => "a" } } },
    )
  end

  it "propagates names into fuzzy queries" do
    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::Fuzzy.new(Luqum::Tree::Word.new("bar")))
    Luqum::Naming.set_name(tree.children[0], "a")
    expect(transformer.call(tree)).to eq(
      { "fuzzy" => { "text" => { "value" => "bar", "_name" => "a", "fuzziness" => 0.5 } } },
    )
  end

  it "propagates names into proximity queries" do
    tree = Luqum::Tree::SearchField.new("spam", Luqum::Tree::Proximity.new(Luqum::Tree::Phrase.new('"foo bar"')))
    Luqum::Naming.set_name(tree.children[0], "a")
    expect(transformer.call(tree)).to eq(
      { "match_phrase" => { "spam" => { "query" => "foo bar", "_name" => "a", "slop" => 1.0 } } },
    )
  end

  it "propagates names into boosted queries" do
    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::Boost.new(Luqum::Tree::Phrase.new('"foo bar"'), force: 2))
    Luqum::Naming.set_name(tree.children[0], "a")
    expect(transformer.call(tree)).to eq(
      { "term" => { "text" => { "value" => "foo bar", "_name" => "a", "boost" => 2.0 } } },
    )
  end

  it "propagates names through OR operations" do
    tree = Luqum::Tree::OrOperation.new(
      Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("foo")),
      Luqum::Tree::SearchField.new("spam", Luqum::Tree::Word.new("bar")),
    )
    Luqum::Naming.set_name(tree.operands[0], "a")
    Luqum::Naming.set_name(tree.operands[1], "b")

    expect(transformer.call(tree)).to eq(
      {
        "bool" => {
          "should" => [
            { "term" => { "text" => { "_name" => "a", "value" => "foo" } } },
            { "match" => { "spam" => { "_name" => "b", "query" => "bar", "zero_terms_query" => "none" } } },
          ],
        },
      },
    )
  end

  it "propagates names through AND operations" do
    tree = Luqum::Tree::AndOperation.new(
      Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("foo")),
      Luqum::Tree::SearchField.new("spam", Luqum::Tree::Word.new("bar")),
    )
    Luqum::Naming.set_name(tree.operands[0], "a")
    Luqum::Naming.set_name(tree.operands[1], "b")

    expect(transformer.call(tree)).to eq(
      {
        "bool" => {
          "must" => [
            { "term" => { "text" => { "_name" => "a", "value" => "foo" } } },
            { "match" => { "spam" => { "_name" => "b", "query" => "bar", "zero_terms_query" => "all" } } },
          ],
        },
      },
    )
  end

  it "propagates names through unknown operations" do
    tree = Luqum::Tree::UnknownOperation.new(
      Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("foo")),
      Luqum::Tree::SearchField.new("spam", Luqum::Tree::Word.new("bar")),
    )
    Luqum::Naming.set_name(tree.operands[0], "a")
    Luqum::Naming.set_name(tree.operands[1], "b")

    expect(transformer.call(tree)).to eq(
      {
        "bool" => {
          "should" => [
            { "term" => { "text" => { "_name" => "a", "value" => "foo" } } },
            { "match" => { "spam" => { "_name" => "b", "query" => "bar", "zero_terms_query" => "none" } } },
          ],
        },
      },
    )
  end

  it "propagates names through NOT and prohibit" do
    tree = Luqum::Tree::Not.new(Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("foo")))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "bool" => { "must_not" => [{ "term" => { "text" => { "_name" => "a", "value" => "foo" } } }] } },
    )

    tree = Luqum::Tree::Prohibit.new(Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("foo")))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "bool" => { "must_not" => [{ "term" => { "text" => { "_name" => "a", "value" => "foo" } } }] } },
    )
  end

  it "propagates names through plus" do
    tree = Luqum::Tree::Plus.new(Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("foo")))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "bool" => { "must" => [{ "term" => { "text" => { "_name" => "a", "value" => "foo" } } }] } },
    )
  end

  it "propagates names through ranges" do
    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::Range.new(Luqum::Tree::Word.new("x"), Luqum::Tree::Word.new("z")))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "range" => { "text" => { "_name" => "a", "gte" => "x", "lte" => "z" } } },
    )
  end

  it "propagates names through nested and object fields" do
    tree = Luqum::Tree::SearchField.new("author.name", Luqum::Tree::Word.new("Monthy"))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      {
        "nested" => {
          "_name" => "a",
          "path" => "author",
          "query" => {
            "match" => {
              "author.name" => {
                "_name" => "a",
                "query" => "Monthy",
                "zero_terms_query" => "none",
              },
            },
          },
        },
      },
    )

    tree = Luqum::Tree::SearchField.new("book.title", Luqum::Tree::Word.new("Circus"))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      {
        "match" => {
          "book.title" => {
            "_name" => "a",
            "query" => "Circus",
            "zero_terms_query" => "none",
          },
        },
      },
    )
  end

  it "propagates names through groups and exists queries" do
    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::FieldGroup.new(Luqum::Tree::Word.new("bar")))
    Luqum::Naming.set_name(tree.children[0], "a")
    expect(transformer.call(tree)).to eq(
      { "term" => { "text" => { "value" => "bar", "_name" => "a" } } },
    )

    tree = Luqum::Tree::Group.new(Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("bar")))
    Luqum::Naming.set_name(tree, "a")
    expect(transformer.call(tree)).to eq(
      { "term" => { "text" => { "value" => "bar", "_name" => "a" } } },
    )

    tree = Luqum::Tree::SearchField.new("text", Luqum::Tree::Word.new("*"))
    Luqum::Naming.set_name(tree.children[0], "a")
    expect(transformer.call(tree)).to eq(
      { "exists" => { "field" => "text", "_name" => "a" } },
    )
  end

  it "propagates names through a complex tree" do
    tree = Luqum::Tree::AndOperation.new(
      Luqum::Tree::SearchField.new("text", Luqum::Tree::Phrase.new('"foo bar"')),
      Luqum::Tree::Group.new(
        Luqum::Tree::OrOperation.new(
          Luqum::Tree::Word.new("bar"),
          Luqum::Tree::SearchField.new("spam", Luqum::Tree::Word.new("baz")),
        ),
      ),
    )

    and_op = tree
    search_text = and_op.operands[0]
    or_op = and_op.operands[1].children[0]
    bar = or_op.operands[0]
    search_spam = or_op.operands[1]
    Luqum::Naming.set_name(search_text, "foo_bar")
    Luqum::Naming.set_name(bar, "bar")
    Luqum::Naming.set_name(search_spam, "baz")

    expected = {
      "bool" => {
        "must" => [
          { "term" => { "text" => { "_name" => "foo_bar", "value" => "foo bar" } } },
          {
            "bool" => {
              "should" => [
                { "term" => { "text" => { "_name" => "bar", "value" => "bar" } } },
                { "match" => { "spam" => { "_name" => "baz", "query" => "baz", "zero_terms_query" => "none" } } },
              ],
            },
          },
        ],
      },
    }

    expect(transformer.call(tree)).to eq(expected)
  end

  it "integrates with auto_name" do
    tree = Luqum::Tree::AndOperation.new(
      Luqum::Tree::SearchField.new("text", Luqum::Tree::Phrase.new('"foo bar"')),
      Luqum::Tree::Group.new(
        Luqum::Tree::OrOperation.new(
          Luqum::Tree::Word.new("bar"),
          Luqum::Tree::SearchField.new("spam", Luqum::Tree::Word.new("baz")),
        ),
      ),
    )
    Luqum::Naming.auto_name(tree)

    expect(transformer.call(tree)).to eq(
      {
        "bool" => {
          "must" => [
            { "term" => { "text" => { "_name" => "a", "value" => "foo bar" } } },
            {
              "bool" => {
                "should" => [
                  { "term" => { "text" => { "_name" => "c", "value" => "bar" } } },
                  { "match" => { "spam" => { "_name" => "d", "query" => "baz", "zero_terms_query" => "none" } } },
                ],
              },
            },
          ],
        },
      },
    )
  end
end
