require "set"

RSpec.describe Luqum::Check do
  def word(value, **kwargs)
    Luqum::Tree::Word.new(value, **kwargs)
  end

  def phrase(value, **kwargs)
    Luqum::Tree::Phrase.new(value, **kwargs)
  end

  def proximity(term, degree:, **kwargs)
    Luqum::Tree::Proximity.new(term, degree: degree, **kwargs)
  end

  def fuzzy(term, degree:, **kwargs)
    Luqum::Tree::Fuzzy.new(term, degree: degree, **kwargs)
  end

  def boost(expr, force:, **kwargs)
    Luqum::Tree::Boost.new(expr, force: force, **kwargs)
  end

  def range(low, high, include_low: true, include_high: true, **kwargs)
    Luqum::Tree::Range.new(
      low,
      high,
      include_low: include_low,
      include_high: include_high,
      **kwargs
    )
  end

  def group(expr, **kwargs)
    Luqum::Tree::Group.new(expr, **kwargs)
  end

  def field_group(expr, **kwargs)
    Luqum::Tree::FieldGroup.new(expr, **kwargs)
  end

  def search_field(name, expr, **kwargs)
    Luqum::Tree::SearchField.new(name, expr, **kwargs)
  end

  def and_op(*children, **kwargs)
    Luqum::Tree::AndOperation.new(*children, **kwargs)
  end

  def or_op(*children, **kwargs)
    Luqum::Tree::OrOperation.new(*children, **kwargs)
  end

  def plus(expr, **kwargs)
    Luqum::Tree::Plus.new(expr, **kwargs)
  end

  def not_op(expr, **kwargs)
    Luqum::Tree::Not.new(expr, **kwargs)
  end

  def prohibit(expr, **kwargs)
    Luqum::Tree::Prohibit.new(expr, **kwargs)
  end

  describe Luqum::Check::LuceneCheck do
    it "accepts a valid query" do
      query = and_op(
        search_field(
          "f",
          field_group(
            and_op(
              boost(proximity(phrase('"foo bar"'), degree: 4), force: "4.2"),
              prohibit(range(word("100"), word("200")))
            )
          )
        ),
        group(
          or_op(
            fuzzy(word("baz"), degree: ".8"),
            plus(word("fizz"))
          )
        )
      )

      check = described_class.new
      expect(check.call(query)).to be(true)
      expect(check.errors(query)).to eq([])

      check = described_class.new(zeal: 1)
      expect(check.call(query)).to be(true)
      expect(check.errors(query)).to eq([])
    end

    it "rejects FieldGroup outside a SearchField" do
      check = described_class.new

      query = field_group(word("foo"))
      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("FieldGroup misuse")

      query = or_op(field_group(word("bar")), word("foo"))
      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("FieldGroup misuse")
    end

    it "rejects Group directly after a SearchField" do
      check = described_class.new
      query = search_field("f", group(word("foo")))

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(2)
      expect(check.errors(query).join).to include("Group misuse")
    end

    it "flags prohibit inside OR in zealous mode" do
      query = or_op(prohibit(word("foo")), word("bar"))

      check_zealous = described_class.new(zeal: 1)
      expect(check_zealous.call(query)).to be(false)
      expect(check_zealous.errors(query).first).to include("inconsistent")

      check_easy_going = described_class.new
      expect(check_easy_going.call(query)).to be(true)
    end

    it "flags NOT inside OR in zealous mode" do
      query = or_op(not_op(word("foo")), word("bar"))

      check_zealous = described_class.new(zeal: 1)
      expect(check_zealous.call(query)).to be(false)
      expect(check_zealous.errors(query).first).to include("inconsistent")

      check_easy_going = described_class.new
      expect(check_easy_going.call(query)).to be(true)
    end

    it "rejects invalid field names" do
      check = described_class.new
      query = search_field("foo*", word("bar"))

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("not a valid field name")
    end

    it "rejects invalid field expressions" do
      check = described_class.new
      query = search_field("foo", prohibit(word("bar")))

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("not valid")
    end

    it "rejects words containing spaces" do
      check = described_class.new
      query = word("foo bar")

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("space")
    end

    it "flags invalid characters in a word when zeal is enabled" do
      query = word("foo/bar")

      check = described_class.new
      expect(check.call(query)).to be(true)
      expect(check.errors(query).length).to eq(0)

      check = described_class.new(zeal: 1)
      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("Invalid characters")
    end

    it "rejects negative fuzzy degrees" do
      check = described_class.new
      query = fuzzy(word("foo"), degree: "-4.1")

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("invalid degree")
    end

    it "rejects fuzzy queries on non-words" do
      check = described_class.new
      query = fuzzy(phrase('"foo bar"'), degree: "2")

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("single term")
    end

    it "rejects proximity queries on non-phrases" do
      check = described_class.new
      query = proximity(word("foo"), degree: "2")

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(1)
      expect(check.errors(query).first).to include("phrase")
    end

    it "reports unknown item types" do
      check = described_class.new
      query = and_op("foo", 2)

      expect(check.call(query)).to be(false)
      expect(check.errors(query).length).to eq(2)
      expect(check.errors(query)[0]).to include("Unknown item type")
      expect(check.errors(query)[1]).to include("Unknown item type")
    end
  end

  describe Luqum::Check::CheckNestedFields do
    let(:nested_fields) do
      {
        "author" => {
          "firstname" => {},
          "book" => {
            "title" => {},
            "format" => {
              "type" => {}
            }
          }
        },
        "collection.keywords" => {
          "key" => {},
          "more_info.linked" => {
            "key" => {}
          }
        }
      }
    end

    let(:object_fields) do
      [
        "author.birth.city",
        "collection.title",
        "collection.ref",
        "collection.keywords.more_info.revision"
      ]
    end

    let(:sub_fields) do
      [
        "foo.english",
        "author.book.title.raw"
      ]
    end

    let(:checker) do
      described_class.new(nested_fields)
    end

    let(:strict_checker) do
      described_class.new(
        nested_fields,
        object_fields: object_fields,
        sub_fields: sub_fields
      )
    end

    it "accepts valid nested field queries with colon syntax" do
      tree = Luqum::Parser.parse('author:book:title:"foo" AND author:book:format:type: "pdf"')
      expect { strict_checker.call(tree) }.not_to raise_error
    end

    it "accepts valid object field queries with colon syntax" do
      tree = Luqum::Parser.parse('author:birth:city:"foo" AND collection:(ref:"foo" AND title:"bar")')
      expect { strict_checker.call(tree) }.not_to raise_error
      expect { checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "accepts valid sub-field queries with colon syntax" do
      tree = Luqum::Parser.parse('foo:english:"foo" AND author:book:title:raw:"pdf"')
      expect { strict_checker.call(tree) }.not_to raise_error
    end

    it "accepts valid nested field queries with dotted syntax" do
      tree = Luqum::Parser.parse('author.book.title:"foo" AND author.book.format.type:"pdf"')
      expect { strict_checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "accepts valid object field queries with dotted syntax" do
      tree = Luqum::Parser.parse('author.birth.city:"foo" AND collection.ref:"foo"')
      expect { strict_checker.call(tree) }.not_to raise_error
      expect { checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "accepts valid sub-field queries with dotted syntax" do
      tree = Luqum::Parser.parse('foo.english:"foo" AND author.book.title.raw:"pdf"')
      expect { strict_checker.call(tree) }.not_to raise_error
    end

    it "accepts mixed object field queries" do
      tree = Luqum::Parser.parse('author:(birth.city:"foo" AND book.title:"bar")')
      expect { strict_checker.call(tree) }.not_to raise_error
      expect { checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "rejects invalid nested field queries with colon syntax" do
      tree = Luqum::Parser.parse('author:gender:"Mr" AND author:book:format:type:"pdf"')

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::ObjectSearchFieldError, /author\.gender/)
    end

    it "rejects invalid nested field queries with dotted syntax" do
      tree = Luqum::Parser.parse('author.gender:"Mr" AND author.book.format.type:"pdf"')

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::ObjectSearchFieldError, /"author\.gender"/)
    end

    it "accepts nested queries wrapped inside groups" do
      tree = Luqum::Parser.parse('author:(book.title:"foo" OR book.title:"bar")')
      expect { checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "accepts complex sub-fields" do
      tree = Luqum::Parser.parse('author:(book.title.raw:"foo" OR book.title.raw:"bar")')
      expect { checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "rejects direct searches on a nested field" do
      tree = Luqum::Parser.parse('author:"foo"')

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"author"/)
    end

    it "rejects direct searches on a multi-level nested field" do
      tree = Luqum::Parser.parse('author:book:"foo"')

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"author\.book"/)
    end

    it "rejects complex queries directly on a nested field" do
      tree = Luqum::Parser.parse('author:test OR author.firstname:"Hugo"')

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"author"/)
    end

    it "rejects grouped queries directly on a nested field" do
      tree = Luqum::Parser.parse('author:("test" AND firstname:Hugo)')

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"author"/)
    end

    it "accepts a complex mix of object and nested fields" do
      tree = Luqum::Parser.parse(
        'collection:(title:"foo" AND keywords.more_info:(linked.key:"bar" revision:"test"))'
      )
      expect { strict_checker.call(tree) }.not_to raise_error
      expect { checker.call(tree) }.not_to raise_error
      expect(tree).not_to be_nil
    end

    it "rejects incomplete nested paths inside a complex mix" do
      tree = Luqum::Parser.parse(
        'collection:(title:"foo" AND keywords.more_info:(linked:"bar" revision:"test"))'
      )

      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"collection\.keywords\.more_info\.linked"/)
      expect(tree).not_to be_nil
    end

    it "rejects incomplete object fields" do
      tree = Luqum::Parser.parse('collection.keywords.more_info:"foo"')
      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"collection\.keywords\.more_info"/)

      tree = Luqum::Parser.parse('author:birth:"foo"')
      expect do
        strict_checker.call(tree)
      end.to raise_error(Luqum::NestedSearchFieldError, /"author\.birth"/)
    end
  end
end
