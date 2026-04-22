# frozen_string_literal: true

require "luqum/tree"

RSpec.describe Luqum::Utils do
  def word(value, **)
    Luqum::Tree::Word.new(value, **)
  end

  def group(expr, **)
    Luqum::Tree::Group.new(expr, **)
  end

  def field_group(expr, **)
    Luqum::Tree::FieldGroup.new(expr, **)
  end

  def and_op(*children, **)
    Luqum::Tree::AndOperation.new(*children, **)
  end

  def or_op(*children, **)
    Luqum::Tree::OrOperation.new(*children, **)
  end

  def bool_op(*children, **)
    Luqum::Tree::BoolOperation.new(*children, **)
  end

  def unknown_op(*children, **)
    Luqum::Tree::UnknownOperation.new(*children, **)
  end

  def prohibit(expr, **)
    Luqum::Tree::Prohibit.new(expr, **)
  end

  def plus(expr, **)
    Luqum::Tree::Plus.new(expr, **)
  end

  def from(expr, include: true, **)
    Luqum::Tree::From.new(expr, include: include, **)
  end

  def to(expr, include: true, **)
    Luqum::Tree::To.new(expr, include: include, **)
  end

  def range(low, high, include_low: true, include_high: true, **)
    Luqum::Tree::Range.new(
      low,
      high,
      include_low: include_low,
      include_high: include_high,
      **,
    )
  end

  def search_field(name, expr, **)
    Luqum::Tree::SearchField.new(name, expr, **)
  end

  def boost(expr, force:, **)
    Luqum::Tree::Boost.new(expr, force: force, **)
  end

  describe Luqum::Utils::UnknownOperationResolver do
    it "resolves unknown operations to AND" do
      tree = unknown_op(
        word("a"),
        word("b"),
        or_op(word("c"), word("d")),
      )
      expected = and_op(
        word("a"),
        word("b"),
        or_op(word("c"), word("d")),
      )

      resolver = described_class.new(resolve_to: Luqum::Tree::AndOperation)
      expect(resolver.call(tree)).to eq(expected)
    end

    it "resolves unknown operations to OR" do
      tree = unknown_op(
        word("a"),
        word("b"),
        and_op(word("c"), word("d")),
      )
      expected = or_op(
        word("a"),
        word("b"),
        and_op(word("c"), word("d")),
      )

      resolver = described_class.new(resolve_to: Luqum::Tree::OrOperation)
      expect(resolver.call(tree)).to eq(expected)
    end

    it "resolves unknown operations to Lucene's last operation for a simple query" do
      tree = unknown_op(
        word("a"),
        word("b"),
        unknown_op(word("c"), word("d")),
      )
      expected = and_op(
        word("a"),
        word("b"),
        and_op(word("c"), word("d")),
      )

      resolver = described_class.new(resolve_to: nil)
      expect(resolver.call(tree)).to eq(expected)
    end

    it "resolves unknown operations to BoolOperation" do
      tree = Luqum::Parser.parse("a b (+f +g) -(c d) +e")
      expected = bool_op(
        word("a"),
        word("b"),
        group(bool_op(plus(word("f")), plus(word("g")))),
        prohibit(group(bool_op(word("c"), word("d")))),
        plus(word("e")),
      )

      resolver = described_class.new(resolve_to: Luqum::Tree::BoolOperation)
      expect(resolver.call(tree)).to eq(expected)
    end

    it "resolves unknown operations using the last explicit operation at the same level" do
      tree = or_op(
        word("a"),
        word("b"),
        unknown_op(word("c"), word("d")),
        and_op(
          word("e"),
          unknown_op(word("f"), word("g")),
        ),
        unknown_op(word("i"), word("j")),
        or_op(
          word("k"),
          unknown_op(word("l"), word("m")),
        ),
        unknown_op(word("n"), word("o")),
      )
      expected = or_op(
        word("a"),
        word("b"),
        or_op(word("c"), word("d")),
        and_op(
          word("e"),
          and_op(word("f"), word("g")),
        ),
        and_op(word("i"), word("j")),
        or_op(
          word("k"),
          or_op(word("l"), word("m")),
        ),
        or_op(word("n"), word("o")),
      )

      resolver = described_class.new(resolve_to: nil)
      expect(resolver.call(tree)).to eq(expected)
    end

    it "resolves unknown operations using the last explicit operation with grouping" do
      tree = or_op(
        word("a"),
        word("b"),
        group(
          and_op(
            word("c"),
            unknown_op(word("d"), word("e")),
          ),
        ),
        unknown_op(word("f"), word("g")),
        group(
          unknown_op(word("h"), word("i")),
        ),
      )
      expected = or_op(
        word("a"),
        word("b"),
        group(
          and_op(
            word("c"),
            and_op(word("d"), word("e")),
          ),
        ),
        or_op(word("f"), word("g")),
        group(
          and_op(word("h"), word("i")),
        ),
      )

      resolver = described_class.new(resolve_to: nil)
      expect(resolver.call(tree)).to eq(expected)
    end

    it "rejects invalid resolve_to values" do
      expect do
        described_class.new(resolve_to: Object.new)
      end.to raise_error(ArgumentError)
    end

    it "preserves head, tail, pos, and size" do
      tree = Luqum::Parser.parse("\ra\nb (c\t (d e f)) ")
      resolver = described_class.new(resolve_to: nil)
      transformed = resolver.call(tree)

      expect(transformed.to_s(head_tail: true)).to eq("\ra\nAND b AND (c\t AND (d AND e AND f)) ")
      expect(transformed.pos).to eq(tree.pos)
      expect(transformed.size).to eq(tree.size)

      inner_op = transformed.children[2].children[0]
      original_inner_op = tree.children[2].children[0]
      expect(inner_op).to be_a(Luqum::Tree::AndOperation)
      expect(inner_op.pos).to eq(original_inner_op.pos)
      expect(inner_op.size).to eq(original_inner_op.size)

      deeper_op = inner_op.children[1].children[0]
      original_deeper_op = original_inner_op.children[1].children[0]
      expect(deeper_op).to be_a(Luqum::Tree::AndOperation)
      expect(deeper_op.pos).to eq(original_deeper_op.pos)
      expect(deeper_op.size).to eq(original_deeper_op.size)

      transformed = described_class.new(resolve_to: Luqum::Tree::OrOperation).call(tree)
      expect(transformed.to_s(head_tail: true)).to eq("\ra\nOR b OR (c\t OR (d OR e OR f)) ")
    end
  end

  describe Luqum::Utils::OpenRangeTransformer do
    it "resolves a simple From range" do
      tree = from(word("1"), include: true)
      expected = range(
        word("1", tail: " "),
        word("*", head: " "),
        include_low: true,
        include_high: true,
      )

      [true, false].each do |merge_ranges|
        resolver = described_class.new(merge_ranges: merge_ranges)
        output = resolver.call(tree)
        expect(output).to eq(expected)
        expect(output.to_s).to eq(expected.to_s)
      end
    end

    it "resolves a simple To range" do
      tree = to(word("1"), include: false)
      expected = range(
        word("*", tail: " "),
        word("1", head: " "),
        include_low: true,
        include_high: false,
      )

      [true, false].each do |merge_ranges|
        resolver = described_class.new(merge_ranges: merge_ranges)
        output = resolver.call(tree)
        expect(output).to eq(expected)
        expect(output.to_s).to eq(expected.to_s)
      end
    end

    it "merges complementary open ranges inside AND" do
      tree = and_op(
        from(word("1"), include: true),
        to(word("2"), include: true),
      )
      expected = and_op(
        range(
          word("1", tail: " "),
          word("2", head: " "),
          include_low: true,
          include_high: true,
        ),
      )

      resolver = described_class.new(merge_ranges: true)
      output = resolver.call(tree)
      expect(output).to eq(expected)
      expect(output.to_s).to eq(expected.to_s)
    end

    it "does not merge complementary open ranges when merge_ranges is false" do
      tree = and_op(
        from(word("1"), include: true),
        to(word("2"), include: true),
      )
      expected = and_op(
        range(
          word("1", tail: " "),
          word("*", head: " "),
          include_low: true,
          include_high: true,
        ),
        range(
          word("*", tail: " "),
          word("2", head: " "),
          include_low: true,
          include_high: true,
        ),
      )

      resolver = described_class.new(merge_ranges: false)
      output = resolver.call(tree)
      expect(output).to eq(expected)
      expect(output.to_s).to eq(expected.to_s)
    end

    it "leaves unjoinable open ranges separate" do
      tree = and_op(
        from(word("1"), include: false),
        from(word("2"), include: true),
      )
      expected = and_op(
        range(
          word("1", tail: " "),
          word("*", head: " "),
          include_low: false,
          include_high: true,
        ),
        range(
          word("2", tail: " "),
          word("*", head: " "),
          include_low: true,
          include_high: true,
        ),
      )

      resolver = described_class.new(merge_ranges: true)
      output = resolver.call(tree)
      expect(output).to eq(expected)
      expect(output.to_s).to eq(expected.to_s)
    end

    it "leaves normal ranges untouched" do
      tree = and_op(
        range(word("1"), word("2"), include_low: true, include_high: true),
        range(word("*"), word("*"), include_low: true, include_high: true),
        range(word("1"), word("*"), include_low: true, include_high: true),
      )

      [true, false].each do |merge_ranges|
        resolver = described_class.new(merge_ranges: merge_ranges)
        expect(resolver.call(tree)).to eq(tree)
      end
    end

    it "merges into the first compatible range" do
      tree = and_op(
        range(word("*"), word("2"), include_low: true, include_high: true),
        range(word("*"), word("*"), include_low: true, include_high: true),
        range(word("*"), word("3"), include_low: true, include_high: true),
        range(word("1"), word("*"), include_low: true, include_high: true),
        range(word("4"), word("*"), include_low: true, include_high: true),
      )
      expected = and_op(
        range(word("1"), word("2"), include_low: true, include_high: true),
        range(word("*"), word("*"), include_low: true, include_high: true),
        range(word("4"), word("3"), include_low: true, include_high: true),
      )

      resolver = described_class.new(merge_ranges: true)
      output = resolver.call(tree)
      expect(output).to eq(expected)
      expect(output.to_s).to eq(expected.to_s)
    end

    it "does not merge ranges inside unknown operations" do
      tree = unknown_op(
        range(word("1"), word("*"), include_low: true, include_high: true),
        range(word("*"), word("2"), include_low: true, include_high: true),
      )

      resolver = described_class.new(merge_ranges: true)
      expect(resolver.call(tree)).to eq(tree)
    end

    it "does not merge ranges across search fields" do
      tree = and_op(
        range(word("1"), word("*"), include_low: true, include_high: true),
        search_field("foo", range(word("*"), word("2"), include_low: true, include_high: true)),
      )

      resolver = described_class.new(merge_ranges: true)
      expect(resolver.call(tree)).to eq(tree)
    end

    it "does not merge boosted ranges" do
      tree = and_op(
        boost(range(word("1"), word("*"), include_low: true, include_high: true), force: 2),
        boost(range(word("*"), word("2"), include_low: true, include_high: true), force: 2),
      )

      resolver = described_class.new(merge_ranges: true)
      expect(resolver.call(tree)).to eq(tree)
    end
  end
end
