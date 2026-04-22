require "bigdecimal"
require "luqum/tree"

module Luqum
  module Tree
    RSpec.describe "Tree" do
      describe Term do
        it "detects wildcards" do
          expect(Term.new("ba*").has_wildcard?).to be true
          expect(Term.new("b*r").has_wildcard?).to be true
          expect(Term.new("*ar").has_wildcard?).to be true
          expect(Term.new("ba?").has_wildcard?).to be true
          expect(Term.new("b?r").has_wildcard?).to be true
          expect(Term.new("?ar").has_wildcard?).to be true
          expect(Term.new("?a*").has_wildcard?).to be true
          expect(Term.new('\?a*').has_wildcard?).to be true
          expect(Term.new('?a\*').has_wildcard?).to be true
          expect(Term.new("*").has_wildcard?).to be true
          expect(Term.new("?").has_wildcard?).to be true
          # the \ itself can be escaped !
          expect(Term.new('\\\\*\\\\?').has_wildcard?).to be true
        end

        it "detects absence of wildcards" do
          expect(Term.new("bar").has_wildcard?).to be false
          expect(Term.new('bar\*').has_wildcard?).to be false
          expect(Term.new('b\?r\*').has_wildcard?).to be false
        end

        it "detects a lone wildcard value" do
          expect(Term.new("*").wildcard?).to be true
          expect(Term.new("*o").wildcard?).to be false
          expect(Term.new("b*").wildcard?).to be false
          expect(Term.new("b*o").wildcard?).to be false
          expect(Term.new("?").wildcard?).to be false
        end

        it "iterates wildcards with positions" do
          expect(Term.new('a?b\*or*and\?').iter_wildcards.to_a).to eq(
            [[[1, 2], "?"], [[7, 8], "*"]],
          )
          expect(Term.new('\**\**').iter_wildcards.to_a).to eq(
            [[[2, 3], "*"], [[5, 6], "*"]],
          )
        end

        it "splits on wildcards" do
          expect(Term.new('a??b\*or*and\?').split_wildcards).to eq(
            ["a", "?", "", "?", 'b\*or', "*", 'and\?'],
          )
          expect(Term.new('\**\**').split_wildcards).to eq(
            ['\*', "*", '\*', "*", ""],
          )
        end
      end

      describe "equality" do
        it "compares Proximity nodes" do
          p1 = Proximity.new(Word.new("foo"), degree: 5)
          p2 = Proximity.new(Word.new("bar"), degree: 5)
          p3 = Proximity.new(Word.new("foo"), degree: 5)
          p4 = Proximity.new(Word.new("foo"), degree: 1)
          p5 = Proximity.new(Word.new("foo"), degree: nil)

          expect(p1).not_to eq(p2)
          expect(p1).to eq(p3)
          expect(p1).not_to eq(p4)
          expect(p4).to eq(p5)
        end

        it "compares Fuzzy nodes" do
          f1 = Fuzzy.new(Word.new("foo"), degree: 5)
          f2 = Fuzzy.new(Word.new("bar"), degree: 5)
          f3 = Fuzzy.new(Word.new("foo"), degree: 5)
          f4 = Fuzzy.new(Word.new("foo"), degree: 0.5)
          f5 = Fuzzy.new(Word.new("foo"), degree: nil)

          expect(f1).not_to eq(f2)
          expect(f1).to eq(f3)
          expect(f1).not_to eq(f4)
          expect(f4).to eq(f5)
        end

        it "compares Boost nodes" do
          b1 = Boost.new(Word.new("foo"), force: 5)
          b2 = Boost.new(Word.new("bar"), force: 5)
          b3 = Boost.new(Word.new("foo"), force: 5)
          b4 = Boost.new(Word.new("foo"), force: 0.5)

          expect(b1).not_to eq(b2)
          expect(b1).to eq(b3)
          expect(b1).not_to eq(b4)
        end

        it "compares Range nodes" do
          r1 = Range.new(Word.new("20"), Word.new("40"), include_low: true, include_high: true)
          r2 = Range.new(Word.new("20"), Word.new("40"), include_low: true, include_high: true)
          expect(r1).to eq(r2)
        end

        it "finds Range nodes with different bound values unequal" do
          r1 = Range.new(Word.new("20"), Word.new("40"), include_low: true, include_high: true)
          expect(r1).not_to eq(Range.new(Word.new("30"), Word.new("40"), include_low: true, include_high: true))
          expect(r1).not_to eq(Range.new(Word.new("20"), Word.new("30"), include_low: true, include_high: true))
        end

        it "finds Range nodes with different inclusivity unequal" do
          r1 = Range.new(Word.new("20"), Word.new("40"), include_low: true, include_high: true)
          r2 = Range.new(Word.new("20"), Word.new("40"), include_low: false, include_high: true)
          r3 = Range.new(Word.new("20"), Word.new("40"), include_low: true, include_high: false)
          r4 = Range.new(Word.new("20"), Word.new("40"), include_low: false, include_high: false)
          expect(r1).not_to eq(r2)
          expect(r1).not_to eq(r3)
          expect(r1).not_to eq(r4)
          expect(r2).not_to eq(r3)
          expect(r2).not_to eq(r4)
          expect(r3).not_to eq(r4)
        end

        it "considers different number of operands unequal" do
          tree1 = OrOperation.new(Word.new("bar"))
          tree2 = OrOperation.new(Word.new("bar"), Word.new("foo"))
          expect(tree1).not_to eq(tree2)
        end
      end

      describe "setting children" do
        def self.it_sets_children_for(desc, &)
          it "sets children for #{desc}" do
            item, children = instance_exec(&)
            item.children = children
            expect(item.children).to eq(children)
          end
        end

        it "sets children of leaf and composite nodes" do
          [
            [Word.new("foo"), []],
            [Phrase.new('"foo"'), []],
            [Regex.new("/foo/"), []],
            [SearchField.new("foo", Word.new("bar")), [Word.new("baz")]],
            [Group.new(Word.new("foo")), [Word.new("foo")]],
            [FieldGroup.new(Word.new("foo")), [Word.new("foo")]],
            [Range.new(Word.new("20"), Word.new("30")), [Word.new("40"), Word.new("50")]],
            [Proximity.new(Word.new("foo")), [Word.new("foo")]],
            [Fuzzy.new(Word.new("foo")), [Word.new("foo")]],
            [Boost.new(Word.new("foo"), force: 1), [Word.new("foo")]],
            [UnknownOperation.new(Word.new("foo"), Word.new("bar")), [Word.new("foo"), Word.new("bar")]],
            [AndOperation.new(Word.new("foo"), Word.new("bar")), [Word.new("foo"), Word.new("bar")]],
            [OrOperation.new(Word.new("foo"), Word.new("bar")), [Word.new("foo"), Word.new("bar")]],
            [Plus.new(Word.new("foo")), [Word.new("foo")]],
            [Not.new(Word.new("foo")), [Word.new("foo")]],
            [Prohibit.new(Word.new("foo")), [Word.new("foo")]],
          ].each do |item, children|
            item.children = children
            expect(item.children).to eq(children)
          end

          many_terms = (0...5).map { |i| Word.new("foo_#{i}") }
          [UnknownOperation, AndOperation, OrOperation].each do |cls|
            item = cls.new(*many_terms)
            item.children = many_terms
            expect(item.children).to eq(many_terms)
          end
        end

        it "raises when wrong number of children is supplied" do
          bad = [
            [Word.new("foo"), [Word.new("foo")]],
            [Phrase.new('"foo"'), [Word.new("foo")]],
            [Regex.new("/foo/"), [Word.new("foo")]],
            [SearchField.new("foo", Word.new("bar")), []],
            [SearchField.new("foo", Word.new("bar")), [Word.new("bar"), Word.new("baz")]],
            [Group.new(Word.new("foo")), []],
            [Group.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
            [FieldGroup.new(Word.new("foo")), []],
            [FieldGroup.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
            [Range.new(Word.new("20"), Word.new("30")), []],
            [Range.new(Word.new("20"), Word.new("30")), [Word.new("20"), Word.new("30"), Word.new("40")]],
            [Proximity.new(Word.new("foo")), []],
            [Proximity.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
            [Fuzzy.new(Word.new("foo")), []],
            [Fuzzy.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
            [Boost.new(Word.new("foo"), force: 1), []],
            [Boost.new(Word.new("foo"), force: 1), [Word.new("foo"), Word.new("bar")]],
            [Plus.new(Word.new("foo")), []],
            [Plus.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
            [Not.new(Word.new("foo")), []],
            [Not.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
            [Prohibit.new(Word.new("foo")), []],
            [Prohibit.new(Word.new("foo")), [Word.new("foo"), Word.new("bar")]],
          ]
          bad.each do |item, children|
            expect { item.children = children }.to raise_error(ArgumentError)
          end
        end
      end

      describe "clone_item" do
        def assert_equal_span(a, b)
          expect(a.pos).to eq(b.pos)
          expect(a.size).to eq(b.size)
          expect(a.head).to eq(b.head)
          expect(a.tail).to eq(b.tail)
        end

        it "clones Word with same attributes" do
          orig = Word.new("foo", pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.value).to eq(orig.value)
          expect(copy).to eq(orig)
        end

        it "applies keyword overrides when cloning" do
          orig = Word.new("foo", pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item(value: "bar")
          assert_equal_span(orig, copy)
          expect(copy.value).to eq("bar")
        end

        it "clones Phrase" do
          orig = Phrase.new('"foo"', pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.value).to eq(orig.value)
          expect(copy).to eq(orig)
        end

        it "clones a Phrase into a Word via _clone_item" do
          orig = Phrase.new('"foo"', pos: 3, head: "\n", tail: "\t")
          copy = orig._clone_item(cls: Word)
          assert_equal_span(orig, copy)
          expect(copy.value).to eq(orig.value)
          expect(copy).to be_a(Word)
        end

        it "clones Regex" do
          orig = Regex.new("/foo/", pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.value).to eq(orig.value)
          expect(copy).to eq(orig)
        end

        it "clones SearchField without children" do
          orig = SearchField.new("foo", Word.new("bar"), pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.name).to eq(orig.name)
          expect(copy.expr).to eq(NONE_ITEM)

          expect(copy).not_to eq(orig)
          copy.children = [Word.new("bar")]
          expect(copy).to eq(orig)
        end

        it "clones Group without children" do
          orig = Group.new(Word.new("bar"), pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.expr).to eq(NONE_ITEM)
          expect(copy).not_to eq(orig)
          copy.children = [Word.new("bar")]
          expect(copy).to eq(orig)
        end

        it "clones FieldGroup without children" do
          orig = FieldGroup.new(Word.new("bar"), pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.expr).to eq(NONE_ITEM)
          expect(copy).not_to eq(orig)
          copy.children = [Word.new("bar")]
          expect(copy).to eq(orig)
        end

        it "clones Range without children" do
          orig = Range.new(Word.new("foo"), Word.new("bar"), include_low: false, pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.include_low).to eq(orig.include_low)
          expect(copy.include_high).to eq(orig.include_high)
          expect(copy.low).to eq(NONE_ITEM)
          expect(copy.high).to eq(NONE_ITEM)
          expect(copy).not_to eq(orig)
          copy.children = [Word.new("foo"), Word.new("bar")]
          expect(copy).to eq(orig)
        end

        it "clones Proximity without children" do
          orig = Proximity.new(Word.new("bar"), degree: 3, pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.degree).to eq(orig.degree)
          expect(copy.term).to eq(NONE_ITEM)
          expect(copy).not_to eq(orig)
          copy.children = [Word.new("bar")]
          expect(copy).to eq(orig)
        end

        it "clones Fuzzy without children" do
          orig = Fuzzy.new(Word.new("bar"), degree: 0.3, pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.degree).to eq(orig.degree)
          expect(copy.term).to eq(NONE_ITEM)
          expect(copy).not_to eq(orig)
          copy.children = [Word.new("bar")]
          expect(copy).to eq(orig)
        end

        it "clones Boost without children" do
          orig = Boost.new(Word.new("bar"), force: 3.2, pos: 3, head: "\n", tail: "\t")
          copy = orig.clone_item
          assert_equal_span(orig, copy)
          expect(copy.force).to eq(orig.force)
          expect(copy.expr).to eq(NONE_ITEM)
          expect(copy).not_to eq(orig)
          copy.children = [Word.new("bar")]
          expect(copy).to eq(orig)
        end

        [UnknownOperation, AndOperation, OrOperation].each do |cls|
          it "clones #{cls.name.split('::').last} without operands" do
            orig = cls.new(Word.new("foo"), Word.new("bar"), Word.new("baz"), pos: 3, head: "\n", tail: "\t")
            copy = orig.clone_item
            assert_equal_span(orig, copy)
            expect(copy.operands).to eq([])
            expect(copy).not_to eq(orig)
            copy.children = [Word.new("foo"), Word.new("bar"), Word.new("baz")]
            expect(copy).to eq(orig)
          end
        end

        [Plus, Not, Prohibit].each do |cls|
          it "clones #{cls.name.split('::').last} without child" do
            orig = cls.new(Word.new("foo"), pos: 3, head: "\n", tail: "\t")
            copy = orig.clone_item
            assert_equal_span(orig, copy)
            expect(copy.a).to eq(NONE_ITEM)
            expect(copy).not_to eq(orig)
            copy.children = [Word.new("foo")]
            expect(copy).to eq(orig)
          end
        end
      end

      describe "span" do
        it "returns start and end positions" do
          expect(Item.new(pos: 0, size: 3).span).to eq([0, 3])
          expect(Item.new(head: "\r", tail: "\t\t", pos: 1, size: 3).span).to eq([1, 4])
          expect(Item.new(head: "\r", tail: "\t\t", pos: 1, size: 3).span(head_tail: true)).to eq([0, 6])
        end

        it "returns [nil, nil] when pos is nil" do
          expect(Item.new(pos: nil, size: 3).span).to eq([nil, nil])
          expect(Item.new(pos: nil, size: 3).span(head_tail: true)).to eq([nil, nil])
        end
      end

      describe "printing" do
        it "prints UnknownOperation with operand tails" do
          tree = UnknownOperation.new(
            Word.new("foo", tail: " "),
            Word.new("bar", tail: " "),
            Word.new("baz"),
          )
          expect(tree.to_s).to eq("foo bar baz")
        end

        it "prints Fuzzy" do
          item = Fuzzy.new(Word.new("foo"), degree: nil)
          expect(item.to_s).to eq("foo~")
          expect(item.inspect).to eq('Fuzzy(Word("foo"), 0.5)')
          expect(item.degree).to eq(BigDecimal("0.5"))

          item = Fuzzy.new(Word.new("foo"), degree: ".5")
          expect(item.to_s).to eq("foo~0.5")

          item = Fuzzy.new(Word.new("foo"), degree: (1.0 / 3).to_s)
          expect(item.to_s).to eq("foo~0.3333333333333333")

          item = Fuzzy.new(
            Word.new("foo", head: "\t", tail: "\n"),
            head: "\r",
            tail: "  ",
          )
          expect(item.to_s).to eq("\tfoo\n~")
          expect(item.to_s(head_tail: true)).to eq("\r\tfoo\n~  ")
        end

        it "prints Proximity" do
          item = Proximity.new(Word.new("foo"), degree: nil)
          expect(item.to_s).to eq("foo~")
          expect(item.inspect).to eq('Proximity(Word("foo"), 1)')
          expect(item.degree).to eq(1)

          item = Proximity.new(Word.new("foo"), degree: "1")
          expect(item.to_s).to eq("foo~1")
          expect(item.inspect).to eq('Proximity(Word("foo"), 1)')

          item = Proximity.new(Word.new("foo"), degree: "4")
          expect(item.to_s).to eq("foo~4")
          expect(item.inspect).to eq('Proximity(Word("foo"), 4)')

          item = Proximity.new(
            Word.new("foo", head: "\t", tail: "\n"),
            head: "\r",
            tail: "  ",
          )
          expect(item.to_s).to eq("\tfoo\n~")
          expect(item.to_s(head_tail: true)).to eq("\r\tfoo\n~  ")
        end

        it "prints Boost" do
          item = Boost.new(Word.new("foo"), force: "3")
          expect(item.to_s).to eq("foo^3")
          expect(item.inspect).to eq('Boost(Word("foo"), 3)')

          item = Boost.new(Word.new("foo"), force: (1.0 / 3).to_s)
          expect(item.to_s).to eq("foo^0.3333333333333333")

          item = Boost.new(
            Word.new("foo", head: "\t", tail: "\n"),
            force: 2,
            head: "\r",
            tail: "  ",
          )
          expect(item.to_s).to eq("\tfoo\n^2")
          expect(item.to_s(head_tail: true)).to eq("\r\tfoo\n^2  ")
        end

        it "prints the none item as empty string" do
          expect(NONE_ITEM.to_s).to eq("")
          expect(AndOperation.new(NONE_ITEM, NONE_ITEM).to_s).to eq("AND")
        end
      end
    end
  end
end
