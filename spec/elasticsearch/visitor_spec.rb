RSpec.describe Luqum::Elasticsearch::Visitor::ElasticsearchQueryBuilder do
  def word(value, **)
    Luqum::Tree::Word.new(value, **)
  end

  def phrase(value, **)
    Luqum::Tree::Phrase.new(value, **)
  end

  def search_field(name, expr, **)
    Luqum::Tree::SearchField.new(name, expr, **)
  end

  def and_op(*children, **)
    Luqum::Tree::AndOperation.new(*children, **)
  end

  def or_op(*children, **)
    Luqum::Tree::OrOperation.new(*children, **)
  end

  def unknown_op(*children, **)
    Luqum::Tree::UnknownOperation.new(*children, **)
  end

  def bool_op(*children, **)
    Luqum::Tree::BoolOperation.new(*children, **)
  end

  def prohibit(expr, **)
    Luqum::Tree::Prohibit.new(expr, **)
  end

  def not_op(expr, **)
    Luqum::Tree::Not.new(expr, **)
  end

  def plus(expr, **)
    Luqum::Tree::Plus.new(expr, **)
  end

  def boost(expr, force:, **)
    Luqum::Tree::Boost.new(expr, force: force, **)
  end

  def fuzzy(expr, degree: nil, **)
    Luqum::Tree::Fuzzy.new(expr, degree: degree, **)
  end

  def proximity(expr, degree: nil, **)
    Luqum::Tree::Proximity.new(expr, degree: degree, **)
  end

  def range(low:, high:, include_low:, include_high:, **)
    Luqum::Tree::Range.new(low, high, include_low: include_low, include_high: include_high, **)
  end

  def group(expr, **)
    Luqum::Tree::Group.new(expr, **)
  end

  def field_group(expr, **)
    Luqum::Tree::FieldGroup.new(expr, **)
  end

  describe "basic transformations" do
    let(:transformer) do
      described_class.new(
        default_field: "text",
        not_analyzed_fields: ["not_analyzed_field", "text", "author.tag"],
        nested_fields: {
          "author" => %w[name tag],
        },
        object_fields: ["book.title", "author.rewards.name"],
        sub_fields: ["book.title.raw"],
      )
    end

    it "allows overriding the emitted EWord class" do
      custom_word_class = Class.new(Luqum::Elasticsearch::Visitor::EWord) do
        def json
          { "custom" => q }
        end
      end

      custom_builder = Class.new(described_class) do
        const_set(:E_WORD, custom_word_class)
      end

      result = custom_builder.new.call(and_op(word("spam"), word("eggs"), word("foo")))
      expect(result).to eq(
        {
          "bool" => {
            "must" => [
              { "custom" => "spam" },
              { "custom" => "eggs" },
              { "custom" => "foo" },
            ],
          },
        },
      )
    end

    it "raises on invalid nested search fields and still handles normal input" do
      tree = search_field("spam", or_op(word("egg"), search_field("monty", word("python"))))
      expect { transformer.call(tree) }.to raise_error(Luqum::ObjectSearchFieldError)

      tree = and_op(word("spam"), word("eggs"), word("foo"))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
              { "term" => { "text" => { "value" => "foo" } } },
            ],
          },
        },
      )
    end

    it "transforms AND operations" do
      tree = and_op(word("spam"), word("eggs"), word("foo"))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
              { "term" => { "text" => { "value" => "foo" } } },
            ],
          },
        },
      )
    end

    it "transforms plus" do
      expect(transformer.call(plus(word("spam")))).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam" } } },
            ],
          },
        },
      )
    end

    it "transforms OR operations" do
      tree = or_op(word("spam"), word("eggs"), word("foo"))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
              { "term" => { "text" => { "value" => "foo" } } },
            ],
          },
        },
      )
    end

    it "transforms BoolOperation" do
      tree = bool_op(
        word("a"),
        word("b"),
        group(bool_op(plus(word("f")), plus(word("g")))),
        prohibit(group(bool_op(word("c"), word("d")))),
        plus(word("e")),
      )

      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "e" } } },
            ],
            "should" => [
              { "term" => { "text" => { "value" => "a" } } },
              { "term" => { "text" => { "value" => "b" } } },
              {
                "bool" => {
                  "must" => [
                    { "term" => { "text" => { "value" => "f" } } },
                    { "term" => { "text" => { "value" => "g" } } },
                  ],
                },
              },
            ],
            "must_not" => [
              {
                "bool" => {
                  "should" => [
                    { "term" => { "text" => { "value" => "c" } } },
                    { "term" => { "text" => { "value" => "d" } } },
                  ],
                },
              },
            ],
          },
        },
      )
    end

    it "raises when OR contains AND on the same level" do
      tree = or_op(word("spam"), and_op(word("eggs"), word("monty")))
      expect { transformer.call(tree) }.to raise_error(Luqum::OrAndAndOnSameLevelError)

      tree = unknown_op(word("spam"), and_op(word("eggs"), word("monty")))
      expect { transformer.call(tree) }.to raise_error(Luqum::OrAndAndOnSameLevelError)
    end

    it "raises when OR mixes with not-like must semantics on the same level" do
      must_transformer = described_class.new(
        default_field: "text",
        not_analyzed_fields: %w[not_analyzed_field text],
        default_operator: described_class::MUST,
      )

      tree = or_op(word("spam"), unknown_op(word("test"), prohibit(word("eggs"))))
      expect { must_transformer.call(tree) }.to raise_error(Luqum::OrAndAndOnSameLevelError)

      tree = unknown_op(word("spam"), or_op(word("test"), prohibit(word("eggs"))))
      expect { must_transformer.call(tree) }.to raise_error(Luqum::OrAndAndOnSameLevelError)

      tree = unknown_op(
        group(word("preparation*")),
        unknown_op(word("CFG"), or_op(word("test"), word("fuck"))),
      )
      expect { must_transformer.call(tree) }.to raise_error(Luqum::OrAndAndOnSameLevelError)
    end

    it "transforms prohibit and NOT" do
      expected = {
        "bool" => {
          "must_not" => [
            { "term" => { "text" => { "value" => "spam" } } },
          ],
        },
      }
      expect(transformer.call(prohibit(word("spam")))).to eq(expected)
      expect(transformer.call(not_op(word("spam")))).to eq(expected)
    end

    it "transforms bare words and wildcard exists queries" do
      expect(transformer.call(word("spam"))).to eq(
        { "term" => { "text" => { "value" => "spam" } } },
      )

      expect(transformer.call(word("*"))).to eq(
        { "exists" => { "field" => "text" } },
      )

      expect(transformer.call(search_field("foo", word("*")))).to eq(
        { "exists" => { "field" => "foo" } },
      )
    end

    it "uses a custom default field" do
      custom_transformer = described_class.new(default_field: "custom", not_analyzed_fields: ["custom"])
      expect(custom_transformer.call(word("spam"))).to eq(
        { "term" => { "custom" => { "value" => "spam" } } },
      )
    end

    it "keeps phrases as phrases even with wildcard characters" do
      expect(transformer.call(search_field("foo", phrase('"spam*"')))).to eq(
        { "match_phrase" => { "foo" => { "query" => "spam*" } } },
      )

      expect(transformer.call(search_field("foo", phrase('"spam\*"')))).to eq(
        { "match_phrase" => { "foo" => { "query" => 'spam\*' } } },
      )

      expect(transformer.call(search_field("foo", phrase('"spam\\*"')))).to eq(
        { "match_phrase" => { "foo" => { "query" => 'spam\\*' } } },
      )
    end

    it "transforms phrases" do
      expect(transformer.call(search_field("foo", phrase('"spam eggs"')))).to eq(
        { "match_phrase" => { "foo" => { "query" => "spam eggs" } } },
      )

      expect(transformer.call(search_field("foo", phrase('""')))).to eq(
        { "match_phrase" => { "foo" => { "query" => "" } } },
      )

      custom_transformer = described_class.new(default_field: "custom")
      expect(custom_transformer.call(phrase('"spam eggs"'))).to eq(
        { "match_phrase" => { "custom" => { "query" => "spam eggs" } } },
      )

      expect(transformer.call(search_field("monthy", phrase('"spam eggs"')))).to eq(
        { "match_phrase" => { "monthy" => { "query" => "spam eggs" } } },
      )
    end

    it "transforms search fields" do
      expect(transformer.call(search_field("pays", word("spam")))).to eq(
        { "match" => { "pays" => { "query" => "spam", "zero_terms_query" => "none" } } },
      )
    end

    it "transforms unknown operations using the configured default operator" do
      tree = unknown_op(word("spam"), word("eggs"))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
            ],
          },
        },
      )

      must_transformer = described_class.new(
        default_operator: described_class::MUST,
        not_analyzed_fields: ["text"],
      )
      expect(must_transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
            ],
          },
        },
      )

      should_transformer = described_class.new(
        default_operator: described_class::SHOULD,
        not_analyzed_fields: ["text"],
      )
      expect(should_transformer.call(tree)).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
            ],
          },
        },
      )
    end

    it "simplifies nested same-type operations but not incompatible ones" do
      tree = and_op(word("spam"), and_op(word("eggs"), and_op(word("monthy"), word("python"))))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
              { "term" => { "text" => { "value" => "monthy" } } },
              { "term" => { "text" => { "value" => "python" } } },
            ],
          },
        },
      )

      tree = or_op(word("spam"), or_op(word("eggs"), or_op(word("monthy"), word("python"))))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "text" => { "value" => "spam" } } },
              { "term" => { "text" => { "value" => "eggs" } } },
              { "term" => { "text" => { "value" => "monthy" } } },
              { "term" => { "text" => { "value" => "python" } } },
            ],
          },
        },
      )

      tree = and_op(word("spam"), or_op(word("eggs"), and_op(word("monthy"), word("python"))))
      expect { transformer.call(tree) }.to raise_error(Luqum::OrAndAndOnSameLevelError)
    end

    it "transforms boosts, wildcards, fuzzies, and proximity" do
      expect(transformer.call(boost(word("spam"), force: 1))).to eq(
        { "term" => { "text" => { "value" => "spam", "boost" => 1.0 } } },
      )

      expect(transformer.call(word("spam*"))).to eq(
        { "wildcard" => { "text" => { "value" => "spam*" } } },
      )

      expect(transformer.call(word('spam\*'))).to eq(
        { "term" => { "text" => { "value" => 'spam\*' } } },
      )

      expect(transformer.call(search_field("spam", boost(word("egg"), force: 1)))).to eq(
        { "match" => { "spam" => { "query" => "egg", "boost" => 1.0, "zero_terms_query" => "none" } } },
      )

      expect(transformer.call(fuzzy(word("spam"), degree: 1))).to eq(
        { "fuzzy" => { "text" => { "value" => "spam", "fuzziness" => 1.0 } } },
      )

      expect(transformer.call(search_field("spam", fuzzy(word("egg"), degree: 1)))).to eq(
        { "fuzzy" => { "spam" => { "value" => "egg", "fuzziness" => 1.0 } } },
      )

      expect(transformer.call(search_field("foo", proximity(phrase('"spam and eggs"'), degree: 1)))).to eq(
        { "match_phrase" => { "foo" => { "query" => "spam and eggs", "slop" => 1.0 } } },
      )

      expect(transformer.call(search_field("spam", proximity(phrase('"Life of Bryan"'), degree: 1)))).to eq(
        { "match_phrase" => { "spam" => { "query" => "Life of Bryan", "slop" => 1.0 } } },
      )

      expect(transformer.call(search_field("not_analyzed_field", proximity(phrase('"Life of Bryan"'), degree: 2)))).to eq(
        { "fuzzy" => { "not_analyzed_field" => { "value" => "Life of Bryan", "fuzziness" => 2.0 } } },
      )
    end

    it "transforms ranges" do
      expect(
        transformer.call(range(low: word("1"), high: word("10"), include_low: true, include_high: true)),
      ).to eq(
        { "range" => { "text" => { "lte" => "10", "gte" => "1" } } },
      )

      expect(
        transformer.call(range(low: word("1"), high: word("*"), include_low: true, include_high: true)),
      ).to eq(
        { "range" => { "text" => { "gte" => "1" } } },
      )

      expect(
        transformer.call(range(low: word("1"), high: word("10"), include_low: false, include_high: false)),
      ).to eq(
        { "range" => { "text" => { "lt" => "10", "gt" => "1" } } },
      )

      expect(
        transformer.call(range(low: word("1"), high: word("10"), include_low: true, include_high: false)),
      ).to eq(
        { "range" => { "text" => { "lt" => "10", "gte" => "1" } } },
      )

      expect(
        transformer.call(range(low: word("1"), high: word("10"), include_low: false, include_high: true)),
      ).to eq(
        { "range" => { "text" => { "lte" => "10", "gt" => "1" } } },
      )

      expect(
        transformer.call(search_field("spam", range(low: word("1"), high: word("10"), include_low: true, include_high: false))),
      ).to eq(
        { "range" => { "spam" => { "lt" => "10", "gte" => "1" } } },
      )
    end

    it "transforms groups and field groups" do
      tree = and_op(word("spam"), group(and_op(word("monty"), word("python"))))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam" } } },
              {
                "bool" => {
                  "must" => [
                    { "term" => { "text" => { "value" => "monty" } } },
                    { "term" => { "text" => { "value" => "python" } } },
                  ],
                },
              },
            ],
          },
        },
      )

      tree = search_field("spam", field_group(and_op(word("monty"), word("python"))))
      expect(transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "match" => { "spam" => { "query" => "monty", "zero_terms_query" => "all" } } },
              { "match" => { "spam" => { "query" => "python", "zero_terms_query" => "all" } } },
            ],
          },
        },
      )
    end

    it "keeps not_analyzed settings inside nested fields" do
      tree = search_field(
        "author",
        field_group(
          and_op(
            search_field("name", word("Tolkien")),
            search_field("tag", word("fantasy")),
          ),
        ),
      )

      expect(transformer.call(tree)).to eq(
        {
          "nested" => {
            "path" => "author",
            "query" => {
              "bool" => {
                "must" => [
                  { "match" => { "author.name" => { "query" => "Tolkien", "zero_terms_query" => "all" } } },
                  { "term" => { "author.tag" => { "value" => "fantasy" } } },
                ],
              },
            },
          },
        },
      )
    end

    it "supports match_word_as_phrase" do
      tree = and_op(search_field("foo", word("bar")), search_field("spam", word("ham")))
      phrase_transformer = described_class.new(match_word_as_phrase: true)
      expect(phrase_transformer.call(tree)).to eq(
        {
          "bool" => {
            "must" => [
              { "match_phrase" => { "foo" => { "query" => "bar" } } },
              { "match_phrase" => { "spam" => { "query" => "ham" } } },
            ],
          },
        },
      )
    end

    it "applies field options for match-like queries" do
      tree = search_field("foo", word("bar"))

      option_transformer = described_class.new(field_options: { "foo" => { "match_type" => "match" } })
      expect(option_transformer.call(tree)).to eq(
        { "match" => { "foo" => { "query" => "bar", "zero_terms_query" => "none" } } },
      )

      option_transformer = described_class.new(field_options: { "foo" => { "match_type" => "match_phrase" } })
      expect(option_transformer.call(tree)).to eq(
        { "match_phrase" => { "foo" => { "query" => "bar" } } },
      )

      option_transformer = described_class.new(
        field_options: { "foo" => { "match_type" => "match_prefix", "max_expansions" => 3 } },
      )
      expect(option_transformer.call(tree)).to eq(
        { "match_prefix" => { "foo" => { "query" => "bar", "max_expansions" => 3 } } },
      )

      expect(option_transformer.call(search_field("baz", word("bar")))).to eq(
        { "match" => { "baz" => { "query" => "bar", "zero_terms_query" => "none" } } },
      )
    end

    it "supports backward-compatible type and multi_match options" do
      tree = search_field("foo", word("bar"))

      option_transformer = described_class.new(field_options: { "foo" => { "type" => "match_phrase" } })
      expect(option_transformer.call(tree)).to eq(
        { "match_phrase" => { "foo" => { "query" => "bar" } } },
      )

      option_transformer = described_class.new(
        field_options: {
          "foo" => {
            "match_type" => "multi_match",
            "type" => "most_fields",
            "fields" => %w[foo spam],
          },
        },
      )
      expect(option_transformer.call(tree)).to eq(
        {
          "multi_match" => {
            "type" => "most_fields",
            "fields" => %w[foo spam],
            "query" => "bar",
          },
        },
      )
    end

    it "applies field options for term and nested queries" do
      option_transformer = described_class.new(
        not_analyzed_fields: %w[foo baz],
        field_options: { "foo" => { "boost" => 2.0 } },
      )
      expect(option_transformer.call(search_field("foo", word("bar")))).to eq(
        { "term" => { "foo" => { "value" => "bar", "boost" => 2.0 } } },
      )
      expect(option_transformer.call(search_field("baz", word("bar")))).to eq(
        { "term" => { "baz" => { "value" => "bar" } } },
      )

      nested_transformer = described_class.new(
        nested_fields: { "author" => ["name"] },
        field_options: { "author.name" => { "match_type" => "match_prefix", "boost" => 3.0 } },
      )
      expected = {
        "nested" => {
          "path" => "author",
          "query" => {
            "match_prefix" => { "author.name" => { "query" => "bar", "boost" => 3.0 } },
          },
        },
      }
      expect(nested_transformer.call(search_field("author.name", word("bar")))).to eq(expected)
      expect(nested_transformer.call(search_field("author", search_field("name", word("bar"))))).to eq(expected)
    end

    it "applies field options deep inside a complex query" do
      option_transformer = described_class.new(
        default_field: "foo",
        not_analyzed_fields: ["spam"],
        field_options: { "foo" => { "match_type" => "match", "boost" => 2.0 } },
      )

      tree = or_op(
        search_field(
          "foo",
          field_group(and_op(word("bar"), boost(phrase('"baz"'), force: 4.0))),
        ),
        group(and_op(word("oof"), search_field("spam", word("ham")))),
      )

      expect(option_transformer.call(tree)).to eq(
        {
          "bool" => {
            "should" => [
              {
                "bool" => {
                  "must" => [
                    { "match" => { "foo" => { "query" => "bar", "boost" => 2.0, "zero_terms_query" => "all" } } },
                    { "match" => { "foo" => { "query" => "baz", "boost" => 4.0, "zero_terms_query" => "all" } } },
                  ],
                },
              },
              {
                "bool" => {
                  "must" => [
                    { "match" => { "foo" => { "query" => "oof", "boost" => 2.0, "zero_terms_query" => "all" } } },
                    { "term" => { "spam" => { "value" => "ham" } } },
                  ],
                },
              },
            ],
          },
        },
      )
    end
  end

  describe "real queries" do
    let(:transformer) do
      described_class.new(
        default_field: "text",
        not_analyzed_fields: %w[
          type statut pays pays_acheteur pays_acheteur_display
          refW pays_execution dept region dept_acheteur
          dept_acheteur_display dept_execution flux sourceU
          url refA thes modele ii iqi idc
          critere_special auteur doublons doublons_de
          resultats resultat_de rectifie_par rectifie
          profils_en_cours profils_exclus profils_historiques
        ],
        default_operator: described_class::MUST,
      )
    end

    it "handles real-world query situations" do
      expect(transformer.call(Luqum::Parser.parse("spam:eggs"))).to eq(
        { "match" => { "spam" => { "query" => "eggs", "zero_terms_query" => "none" } } },
      )

      expect(transformer.call(Luqum::Parser.parse("pays:FR AND monty:python"))).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "pays" => { "value" => "FR" } } },
              { "match" => { "monty" => { "query" => "python", "zero_terms_query" => "all" } } },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse("spam:de AND -monty:le AND title:alone"))).to eq(
        {
          "bool" => {
            "must" => [
              { "match" => { "spam" => { "query" => "de", "zero_terms_query" => "all" } } },
              {
                "bool" => {
                  "must_not" => [
                    { "match" => { "monty" => { "query" => "le", "zero_terms_query" => "none" } } },
                  ],
                },
              },
              { "match" => { "title" => { "query" => "alone", "zero_terms_query" => "all" } } },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse("spam:eggs AND (monty:python OR life:bryan)"))).to eq(
        {
          "bool" => {
            "must" => [
              { "match" => { "spam" => { "query" => "eggs", "zero_terms_query" => "all" } } },
              {
                "bool" => {
                  "should" => [
                    { "match" => { "monty" => { "query" => "python", "zero_terms_query" => "none" } } },
                    { "match" => { "life" => { "query" => "bryan", "zero_terms_query" => "none" } } },
                  ],
                },
              },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse("spam:eggs OR monty:{2 TO 4]"))).to eq(
        {
          "bool" => {
            "should" => [
              { "match" => { "spam" => { "query" => "eggs", "zero_terms_query" => "none" } } },
              { "range" => { "monty" => { "lte" => "4", "gt" => "2" } } },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse("pays:FR OR objet:{2 TO 4]"))).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "pays" => { "value" => "FR" } } },
              { "range" => { "objet" => { "lte" => "4", "gt" => "2" } } },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse("pays:FR OR monty:{2 TO 4] OR python"))).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "pays" => { "value" => "FR" } } },
              { "range" => { "monty" => { "lte" => "4", "gt" => "2" } } },
              { "match" => { "text" => { "query" => "python", "zero_terms_query" => "none" } } },
            ],
          },
        },
      )

      complex = Luqum::Parser.parse(
        "pays:FR AND " \
        "type:AO AND " \
        "thes:((" \
        "SI_FM_GC_RC_Relation_client_commerciale_courrier OR " \
        "SI_FM_GC_Gestion_Projet_Documents OR " \
        "SI_FM_GC_RC_Mailing_prospection_Enquete_Taxe_apprentissage OR " \
        "SI_FM_GC_RC_Site_web OR " \
        "SI_FM_GC_RH OR SI_FM_GC_RH_Paye OR " \
        "SI_FM_GC_RH_Temps) OR NOT C91_Etranger)",
      )

      expect(transformer.call(complex)).to eq(
        {
          "bool" => {
            "must" => [
              { "term" => { "pays" => { "value" => "FR" } } },
              { "term" => { "type" => { "value" => "AO" } } },
              {
                "bool" => {
                  "should" => [
                    {
                      "bool" => {
                        "should" => [
                          { "term" => { "thes" => { "value" => "SI_FM_GC_RC_Relation_client_commerciale_courrier" } } },
                          { "term" => { "thes" => { "value" => "SI_FM_GC_Gestion_Projet_Documents" } } },
                          { "term" => { "thes" => { "value" => "SI_FM_GC_RC_Mailing_prospection_Enquete_Taxe_apprentissage" } } },
                          { "term" => { "thes" => { "value" => "SI_FM_GC_RC_Site_web" } } },
                          { "term" => { "thes" => { "value" => "SI_FM_GC_RH" } } },
                          { "term" => { "thes" => { "value" => "SI_FM_GC_RH_Paye" } } },
                          { "term" => { "thes" => { "value" => "SI_FM_GC_RH_Temps" } } },
                        ],
                      },
                    },
                    {
                      "bool" => {
                        "must_not" => [
                          { "term" => { "thes" => { "value" => "C91_Etranger" } } },
                        ],
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
      )

      bad = Luqum::Parser.parse(
        'objet:(accessibilite OR diagnosti* OR adap OR "ad ap" -(travaux OR amiante OR "hors voirie"))',
      )
      expect { transformer.call(bad) }.to raise_error(Luqum::OrAndAndOnSameLevelError)

      expect(transformer.call(Luqum::Parser.parse("spam:\"monthy\r\n python\""))).to eq(
        { "match_phrase" => { "spam" => { "query" => "monthy python" } } },
      )
    end
  end

  describe "nested and object fields" do
    let(:transformer) do
      described_class.new(
        default_field: "text",
        not_analyzed_fields: [
          "author.book.format.type",
          "author.book.isbn.ref",
          "author.book.isbn.ref.lower",
          "publish.site",
          "manager.address.zipcode",
        ],
        nested_fields: {
          "author" => {
            "firstname" => nil,
            "lastname" => nil,
            "isbn" => nil,
            "book" => {
              "format" => ["type"],
              "title" => nil,
            },
          },
          "publish" => ["site"],
          "manager.subteams" => {
            "supervisor" => {},
          },
        },
        object_fields: [
          "author.book.isbn.ref",
          "manager.firstname",
          "manager.address.zipcode",
          "manager.subteams.supervisor.name",
        ],
        sub_fields: [
          "text.english",
          "author.book.isbn.ref.lower",
        ],
        default_operator: described_class::MUST,
      )
    end

    it "handles sub-fields, nested fields, object fields, and mixed deep nesting" do
      expect(transformer.call(Luqum::Parser.parse('text:(english:"Spanish Cow")'))).to eq(
        { "match_phrase" => { "text.english" => { "query" => "Spanish Cow" } } },
      )

      expect(transformer.call(Luqum::Parser.parse('text.english:"Spanish Cow"'))).to eq(
        { "match_phrase" => { "text.english" => { "query" => "Spanish Cow" } } },
      )

      expect(transformer.call(Luqum::Parser.parse("author.book.isbn.ref.lower:thebiglebowski"))).to eq(
        {
          "nested" => {
            "path" => "author.book",
            "query" => { "term" => { "author.book.isbn.ref.lower" => { "value" => "thebiglebowski" } } },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author:(firstname:"François")'))).to eq(
        {
          "nested" => {
            "path" => "author",
            "query" => { "match_phrase" => { "author.firstname" => { "query" => "François" } } },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author.firstname:"François"'))).to eq(
        {
          "nested" => {
            "path" => "author",
            "query" => { "match_phrase" => { "author.firstname" => { "query" => "François" } } },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('manager.firstname:"François" OR manager.address.zipcode:44000'))).to eq(
        {
          "bool" => {
            "should" => [
              { "match_phrase" => { "manager.firstname" => { "query" => "François" } } },
              { "term" => { "manager.address.zipcode" => { "value" => "44000" } } },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('publish.site:"http://example.com/foo#bar"'))).to eq(
        {
          "nested" => {
            "path" => "publish",
            "query" => { "term" => { "publish.site" => { "value" => "http://example.com/foo#bar" } } },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author.firstname:"François" AND author.lastname:"Dupont"'))).to eq(
        {
          "bool" => {
            "must" => [
              {
                "nested" => {
                  "query" => { "match_phrase" => { "author.firstname" => { "query" => "François" } } },
                  "path" => "author",
                },
              },
              {
                "nested" => {
                  "query" => { "match_phrase" => { "author.lastname" => { "query" => "Dupont" } } },
                  "path" => "author",
                },
              },
            ],
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author.book.format.type:"pdf"'))).to eq(
        {
          "nested" => {
            "query" => { "term" => { "author.book.format.type" => { "value" => "pdf" } } },
            "path" => "author.book.format",
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author:(firstname:"François" AND lastname:"Dupont")'))).to eq(
        {
          "nested" => {
            "path" => "author",
            "query" => {
              "bool" => {
                "must" => [
                  { "match_phrase" => { "author.firstname" => { "query" => "François" } } },
                  { "match_phrase" => { "author.lastname" => { "query" => "Dupont" } } },
                ],
              },
            },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author:(book:(title:"printemps"))'))).to eq(
        {
          "nested" => {
            "path" => "author.book",
            "query" => { "match_phrase" => { "author.book.title" => { "query" => "printemps" } } },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author:(book:(format:(type:"pdf")))'))).to eq(
        {
          "nested" => {
            "path" => "author.book.format",
            "query" => { "term" => { "author.book.format.type" => { "value" => "pdf" } } },
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author:(book:(format:(type:"pdf" OR type:"epub")))'))).to eq(
        {
          "nested" => {
            "query" => {
              "bool" => {
                "should" => [
                  { "term" => { "author.book.format.type" => { "value" => "pdf" } } },
                  { "term" => { "author.book.format.type" => { "value" => "epub" } } },
                ],
              },
            },
            "path" => "author.book.format",
          },
        },
      )

      expect(transformer.call(Luqum::Parser.parse('author.book.format.type:"pdf" OR author.book.format.type:"epub"'))).to eq(
        {
          "bool" => {
            "should" => [
              {
                "nested" => {
                  "query" => { "term" => { "author.book.format.type" => { "value" => "pdf" } } },
                  "path" => "author.book.format",
                },
              },
              {
                "nested" => {
                  "query" => { "term" => { "author.book.format.type" => { "value" => "epub" } } },
                  "path" => "author.book.format",
                },
              },
            ],
          },
        },
      )

      expect(
        transformer.call(
          Luqum::Parser.parse('author:book:(title:"Hugo" isbn.ref:"2222" format:type:("pdf" OR "epub"))'),
        ),
      ).to eq(
        {
          "nested" => {
            "path" => "author.book",
            "query" => {
              "bool" => {
                "must" => [
                  { "match_phrase" => { "author.book.title" => { "query" => "Hugo" } } },
                  { "term" => { "author.book.isbn.ref" => { "value" => "2222" } } },
                  {
                    "nested" => {
                      "path" => "author.book.format",
                      "query" => {
                        "bool" => {
                          "should" => [
                            { "term" => { "author.book.format.type" => { "value" => "pdf" } } },
                            { "term" => { "author.book.format.type" => { "value" => "epub" } } },
                          ],
                        },
                      },
                    },
                  },
                ],
              },
            },
          },
        },
      )

      mixed = Luqum::Parser.parse(
        'author:(book:(isbn.ref:"foo" AND title:"bar") OR lastname:"baz") AND ' \
        'manager:(subteams.supervisor.name:("John" OR "Paul") AND NOT address.zipcode:44)',
      )

      expect(transformer.call(mixed)).to eq(
        {
          "bool" => {
            "must" => [
              {
                "nested" => {
                  "path" => "author",
                  "query" => {
                    "bool" => {
                      "should" => [
                        {
                          "nested" => {
                            "path" => "author.book",
                            "query" => {
                              "bool" => {
                                "must" => [
                                  { "term" => { "author.book.isbn.ref" => { "value" => "foo" } } },
                                  { "match_phrase" => { "author.book.title" => { "query" => "bar" } } },
                                ],
                              },
                            },
                          },
                        },
                        { "match_phrase" => { "author.lastname" => { "query" => "baz" } } },
                      ],
                    },
                  },
                },
              },
              {
                "bool" => {
                  "must" => [
                    {
                      "nested" => {
                        "path" => "manager.subteams",
                        "query" => {
                          "bool" => {
                            "should" => [
                              { "match_phrase" => { "manager.subteams.supervisor.name" => { "query" => "John" } } },
                              { "match_phrase" => { "manager.subteams.supervisor.name" => { "query" => "Paul" } } },
                            ],
                          },
                        },
                      },
                    },
                    {
                      "bool" => {
                        "must_not" => [
                          { "term" => { "manager.address.zipcode" => { "value" => "44" } } },
                        ],
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
      )
    end
  end
end

RSpec.describe Luqum::Elasticsearch::Tree::ElasticSearchItemFactory do
  it "lets explicit field_options override factory defaults" do
    factory = described_class.new(
      [],
      {},
      { "foo" => { "match_type" => "phrase" } },
    )

    word = factory.build(Luqum::Elasticsearch::Visitor::EWord, "bar")
    expect(word.field_options).to eq({ "foo" => { "match_type" => "phrase" } })

    word = factory.build(
      Luqum::Elasticsearch::Visitor::EWord,
      "bar",
      field_options: { "foo" => { "match_type" => "term" } },
    )
    expect(word.field_options).to eq({ "foo" => { "match_type" => "term" } })
  end
end
