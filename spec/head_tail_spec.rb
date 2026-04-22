require "luqum"
require "luqum/parser"

module Luqum
  module Tree
    RSpec.describe "HeadTail" do
      describe Luqum::TokenValue do
        it "prints its value" do
          expect(Luqum::TokenValue.new("").to_s).to eq("")
          expect(Luqum::TokenValue.new("foo").to_s).to eq("foo")
        end

        it "inspects to TokenValue(value)" do
          expect(Luqum::TokenValue.new("").inspect).to eq("TokenValue()")
          expect(Luqum::TokenValue.new("foo").inspect).to eq("TokenValue(foo)")
        end

        it "defaults pos/head/tail" do
          t = Luqum::TokenValue.new("foo")
          expect(t.pos).to be_nil
          expect(t.head).to eq("")
          expect(t.tail).to eq("")
        end
      end

      describe "Lexer head/tail behavior" do
        def first_token(input)
          Luqum::Lexer.new.tokenize(input).first
        end

        it "puts leading separator in head of first token" do
          tokens = Luqum::Lexer.new.tokenize("\tfoo")
          expect(tokens.first.value.head).to eq("\t")
          expect(tokens.first.value.tail).to eq("")
          expect(tokens.first.value.pos).to eq(1)
          expect(tokens.first.value.size).to eq(3)
        end

        it "leaves head empty when there is no leading separator" do
          tokens = Luqum::Lexer.new.tokenize("foo")
          expect(tokens.first.value.head).to eq("")
          expect(tokens.first.value.tail).to eq("")
          expect(tokens.first.value.pos).to eq(0)
          expect(tokens.first.value.size).to eq(3)
        end

        it "accumulates tail between tokens" do
          tokens = Luqum::Lexer.new.tokenize("foo  bar")
          expect(tokens[0].value.head).to eq("")
          expect(tokens[0].value.tail).to eq("  ")
          expect(tokens[1].value.head).to eq("")
          expect(tokens[1].value.tail).to eq("")
        end

        it "puts trailing separator in tail of last token" do
          tokens = Luqum::Lexer.new.tokenize("foo\r")
          expect(tokens.last.value.tail).to eq("\r")
        end
      end

      describe Luqum::HeadTailManager do
        let(:manager) { Luqum::HeadTailManager.new }

        it "sets pos/size" do
          p = [Item.new, Item.new(pos: 4, size: 3)]
          manager.pos(p)
          expect(p[0].pos).to eq(4)
          expect(p[0].size).to eq(3)
        end

        it "subtracts head from pos when not transferring" do
          p = [Item.new, Item.new(pos: 4, size: 3, head: "\r\n")]
          manager.pos(p, head_transfer: false)
          expect(p[0].pos).to eq(2)
          expect(p[0].size).to eq(5)
        end

        it "keeps pos when transferring head" do
          p = [Item.new, Item.new(pos: 4, size: 3, head: "\r\n")]
          manager.pos(p, head_transfer: true)
          expect(p[0].pos).to eq(4)
          expect(p[0].size).to eq(3)
        end

        it "sets pos to nil when child pos is nil" do
          p = [Item.new, Item.new(pos: nil, size: nil)]
          manager.pos(p)
          expect(p[0].pos).to be_nil
          expect(p[0].size).to eq(0)
        end

        it "computes binary_operation pos/size" do
          p = [
            Item.new,
            Item.new(pos: 1, size: 3, head: "\t", tail: "\n"),
            Item.new(pos: 4, size: 4, head: "\r", tail: "  "),
          ]
          manager.binary_operation(p, op_tail: "")
          expect(p[0].pos).to eq(0)
          expect(p[0].size).to eq(12)
          manager.binary_operation(p, op_tail: "  ")
          expect(p[0].pos).to eq(0)
          expect(p[0].size).to eq(10)
        end

        it "copies head/tail for simple_term" do
          p = [Item.new, Item.new(pos: 4, size: 3, head: "\t", tail: "\r")]
          manager.simple_term(p)
          expect(p[0].head).to eq("\t")
          expect(p[0].tail).to eq("\r")
          expect(p[0].pos).to eq(4)
          expect(p[0].size).to eq(3)
        end

        it "handles unary" do
          p = [
            Item.new,
            Item.new(head: "\t", tail: "\r", pos: 3, size: 3),
            Item.new(head: "\n", tail: "  ", pos: 5, size: 5),
          ]
          manager.unary(p)
          expect(p[0].head).to eq("\t")
          expect(p[0].tail).to eq("")
          expect(p[0].pos).to eq(3)
          expect(p[0].size).to eq(12)
          expect(p[2].head).to eq("\r\n")
          expect(p[2].tail).to eq("  ")
          expect(p[2].pos).to eq(5)
          expect(p[2].size).to eq(5)
        end

        it "handles post_unary" do
          p = [
            Item.new,
            Item.new(head: "\t", tail: "\r", pos: 3, size: 3),
            Item.new(head: "\n", tail: "  ", pos: 5, size: 5),
          ]
          manager.post_unary(p)
          expect(p[0].head).to eq("")
          expect(p[0].tail).to eq("  ")
          expect(p[0].pos).to eq(2)
          expect(p[0].size).to eq(11)
          expect(p[1].head).to eq("\t")
          expect(p[1].tail).to eq("\r\n")
          expect(p[1].pos).to eq(3)
        end

        it "handles paren" do
          p = [
            Item.new,
            Item.new(head: "\t", tail: "\r", pos: 3, size: 1),
            Item.new(head: "\n", tail: "  ", pos: 5, size: 3),
            Item.new(head: "\n\n", tail: "\t\t", pos: 7, size: 1),
          ]
          manager.paren(p)
          expect(p[0].head).to eq("\t")
          expect(p[0].tail).to eq("\t\t")
          expect(p[0].pos).to eq(3)
          expect(p[0].size).to eq(11)
          expect(p[2].head).to eq("\r\n")
          expect(p[2].tail).to eq("  \n\n")
          expect(p[2].pos).to eq(5)
          expect(p[2].size).to eq(3)
        end

        it "handles range" do
          p = [
            Item.new,
            Item.new(head: "\t", tail: "\r", pos: 3, size: 1),
            Item.new(head: "\n", tail: "  ", pos: 5, size: 3),
            Item.new(head: "\n\n", tail: "\t\t", pos: 7, size: 2),
            Item.new(head: "\r\r", tail: " \t ", pos: 9, size: 5),
            Item.new(head: " \r ", tail: " \n ", pos: 12, size: 1),
          ]
          manager.range(p)
          expect(p[0].head).to eq("\t")
          expect(p[0].tail).to eq(" \n ")
          expect(p[0].pos).to eq(3)
          expect(p[0].size).to eq(28)
          expect(p[2].head).to eq("\r\n")
          expect(p[2].tail).to eq("  \n\n")
          expect(p[2].pos).to eq(5)
          expect(p[2].size).to eq(3)
          expect(p[4].head).to eq("\t\t\r\r")
          expect(p[4].tail).to eq(" \t  \r ")
          expect(p[4].pos).to eq(9)
          expect(p[4].size).to eq(5)
        end

        it "handles search_field" do
          p = [
            Item.new,
            Item.new(head: "\t", tail: "\r", pos: 3, size: 3),
            Item.new(head: "\n", tail: "  ", pos: 5, size: 1),
            Item.new(head: "\n\n", tail: "\t\t", pos: 7, size: 5),
          ]
          manager.search_field(p)
          expect(p[0].head).to eq("\t")
          expect(p[0].tail).to eq("")
          expect(p[0].pos).to eq(3)
          expect(p[0].size).to eq(17)
          expect(p[3].head).to eq("  \n\n")
          expect(p[3].tail).to eq("\t\t")
          expect(p[3].pos).to eq(7)
        end
      end

      describe "Parser head/tail integration" do
        def parse(s)
          Luqum::Parser.parse(s)
        end

        it "captures head/tail on a simple word" do
          tree = parse("\tfoo\r")
          expect(tree).to eq(Word.new("foo"))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("\r")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(3)
          expect(tree.to_s).to eq("foo")
          expect(tree.to_s(head_tail: true)).to eq("\tfoo\r")
        end

        it "captures head/tail on a phrase" do
          tree = parse("\t\"foo  bar\"\r")
          expect(tree).to eq(Phrase.new('"foo  bar"'))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("\r")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(10)
          expect(tree.to_s).to eq('"foo  bar"')
          expect(tree.to_s(head_tail: true)).to eq("\t\"foo  bar\"\r")
        end

        it "captures head/tail on a regex" do
          tree = parse("\t/foo/\r")
          expect(tree).to eq(Regex.new("/foo/"))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("\r")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(5)
          expect(tree.to_s).to eq("/foo/")
          expect(tree.to_s(head_tail: true)).to eq("\t/foo/\r")
        end

        it "captures head/tail when TO is used as a term" do
          tree = parse("\tTO\r")
          expect(tree).to eq(Word.new("TO"))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("\r")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(2)
          expect(tree.to_s).to eq("TO")
          expect(tree.to_s(head_tail: true)).to eq("\tTO\r")
        end

        it "captures head/tail for unknown operator" do
          tree = parse("\tfoo\nbar\r")
          expect(tree).to eq(UnknownOperation.new(Word.new("foo"), Word.new("bar")))
          expect(tree.head).to eq("")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(0)
          expect(tree.size).to eq(9)
          foo, bar = tree.children
          expect(foo.head).to eq("\t")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(1)
          expect(foo.size).to eq(3)
          expect(bar.head).to eq("")
          expect(bar.tail).to eq("\r")
          expect(bar.pos).to eq(5)
          expect(bar.size).to eq(3)
          expect(tree.to_s).to eq("\tfoo\nbar\r")
          expect(tree.to_s(head_tail: true)).to eq("\tfoo\nbar\r")
        end

        it "captures head/tail across OR chain" do
          tree = parse("\tfoo\nOR  bar\rOR\t\nbaz\r\r")
          expect(tree).to eq(OrOperation.new(Word.new("foo"), Word.new("bar"), Word.new("baz")))
          expect(tree.head).to eq("")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(0)
          expect(tree.size).to eq(22)
          foo, bar, baz = tree.children
          expect(foo.head).to eq("\t")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(1)
          expect(foo.size).to eq(3)
          expect(bar.head).to eq("  ")
          expect(bar.tail).to eq("\r")
          expect(bar.pos).to eq(9)
          expect(bar.size).to eq(3)
          expect(baz.head).to eq("\t\n")
          expect(baz.tail).to eq("\r\r")
          expect(baz.pos).to eq(17)
          expect(baz.size).to eq(3)
          expect(tree.to_s).to eq("\tfoo\nOR  bar\rOR\t\nbaz\r\r")
          expect(tree.to_s(head_tail: true)).to eq("\tfoo\nOR  bar\rOR\t\nbaz\r\r")
        end

        it "captures head/tail across AND chain" do
          tree = parse("\tfoo\nAND  bar\rAND\t\nbaz\r\r")
          expect(tree).to eq(AndOperation.new(Word.new("foo"), Word.new("bar"), Word.new("baz")))
          expect(tree.head).to eq("")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(0)
          expect(tree.size).to eq(24)
          foo, bar, baz = tree.children
          expect(foo.head).to eq("\t")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(1)
          expect(foo.size).to eq(3)
          expect(bar.head).to eq("  ")
          expect(bar.tail).to eq("\r")
          expect(bar.pos).to eq(10)
          expect(bar.size).to eq(3)
          expect(baz.head).to eq("\t\n")
          expect(baz.tail).to eq("\r\r")
          expect(baz.pos).to eq(19)
          expect(baz.size).to eq(3)
          expect(tree.to_s).to eq("\tfoo\nAND  bar\rAND\t\nbaz\r\r")
          expect(tree.to_s(head_tail: true)).to eq("\tfoo\nAND  bar\rAND\t\nbaz\r\r")
        end

        it "captures head/tail for Plus" do
          tree = parse("\t+\rfoo\n")
          expect(tree).to eq(Plus.new(Word.new("foo")))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(6)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(3)
          expect(foo.size).to eq(3)
          expect(tree.to_s).to eq("+\rfoo\n")
          expect(tree.to_s(head_tail: true)).to eq("\t+\rfoo\n")
        end

        it "captures head/tail for Prohibit" do
          tree = parse("\t-\rfoo\n")
          expect(tree).to eq(Prohibit.new(Word.new("foo")))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(6)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(3)
          expect(foo.size).to eq(3)
          expect(tree.to_s).to eq("-\rfoo\n")
          expect(tree.to_s(head_tail: true)).to eq("\t-\rfoo\n")
        end

        it "captures head/tail for NOT" do
          tree = parse("\tNOT\rfoo\n")
          expect(tree).to eq(Not.new(Word.new("foo")))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(8)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(5)
          expect(foo.size).to eq(3)
          expect(tree.to_s).to eq("NOT\rfoo\n")
          expect(tree.to_s(head_tail: true)).to eq("\tNOT\rfoo\n")
        end

        it "captures head/tail for Group" do
          tree = parse("\t(\rfoo  )\n")
          expect(tree).to eq(Group.new(Word.new("foo")))
          expect(tree.head).to eq("\t")
          expect(tree.tail).to eq("\n")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(8)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("  ")
          expect(foo.pos).to eq(3)
          expect(foo.size).to eq(3)
          expect(tree.to_s).to eq("(\rfoo  )")
          expect(tree.to_s(head_tail: true)).to eq("\t(\rfoo  )\n")
        end

        it "captures head/tail for SearchField" do
          tree = parse("\rfoo:\tbar\n")
          expect(tree).to eq(SearchField.new("foo", Word.new("bar")))
          expect(tree.head).to eq("\r")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(9)
          bar, = tree.children
          expect(bar.head).to eq("\t")
          expect(bar.tail).to eq("\n")
          expect(bar.pos).to eq(6)
          expect(bar.size).to eq(3)
          expect(tree.to_s).to eq("foo:\tbar\n")
          expect(tree.to_s(head_tail: true)).to eq("\rfoo:\tbar\n")
        end

        it "captures head/tail for FieldGroup" do
          tree = parse("\rfoo:\t(  bar\n)\t\n")
          expect(tree).to eq(SearchField.new("foo", FieldGroup.new(Word.new("bar"))))
          expect(tree.head).to eq("\r")
          expect(tree.tail).to eq("")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(15)
          group, = tree.children
          expect(group.head).to eq("\t")
          expect(group.tail).to eq("\t\n")
          expect(group.pos).to eq(6)
          expect(group.size).to eq(8)
          bar, = group.children
          expect(bar.head).to eq("  ")
          expect(bar.tail).to eq("\n")
          expect(bar.pos).to eq(9)
          expect(bar.size).to eq(3)
          expect(tree.to_s).to eq("foo:\t(  bar\n)\t\n")
          expect(tree.to_s(head_tail: true)).to eq("\rfoo:\t(  bar\n)\t\n")
        end

        it "captures head/tail for Range" do
          tree = parse("\r{\tfoo\nTO  bar\r\n]\t\t")
          expect(tree).to eq(Range.new(Word.new("foo"), Word.new("bar"), include_low: false))
          expect(tree.head).to eq("\r")
          expect(tree.tail).to eq("\t\t")
          expect(tree.pos).to eq(1)
          expect(tree.size).to eq(16)
          foo, bar = tree.children
          expect(foo.head).to eq("\t")
          expect(foo.tail).to eq("\n")
          expect(foo.pos).to eq(3)
          expect(foo.size).to eq(3)
          expect(bar.head).to eq("  ")
          expect(bar.tail).to eq("\r\n")
          expect(bar.pos).to eq(11)
          expect(bar.size).to eq(3)
          expect(tree.to_s).to eq("{\tfoo\nTO  bar\r\n]")
          expect(tree.to_s(head_tail: true)).to eq("\r{\tfoo\nTO  bar\r\n]\t\t")
        end

        it "captures head/tail for Boost" do
          tree = parse("\rfoo\t^2\n")
          expect(tree).to eq(Boost.new(Word.new("foo"), force: 2))
          expect(tree.head).to eq("")
          expect(tree.tail).to eq("\n")
          expect(tree.pos).to eq(0)
          expect(tree.size).to eq(7)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("\t")
          expect(foo.pos).to eq(1)
          expect(foo.size).to eq(3)
          expect(tree.to_s).to eq("\rfoo\t^2")
          expect(tree.to_s(head_tail: true)).to eq("\rfoo\t^2\n")
        end

        it "captures head/tail for Fuzzy" do
          tree = parse("\rfoo\t~2\n")
          expect(tree).to eq(Fuzzy.new(Word.new("foo"), degree: 2))
          expect(tree.head).to eq("")
          expect(tree.tail).to eq("\n")
          expect(tree.pos).to eq(0)
          expect(tree.size).to eq(7)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("\t")
          expect(foo.pos).to eq(1)
          expect(foo.size).to eq(3)
          expect(tree.to_s).to eq("\rfoo\t~2")
          expect(tree.to_s(head_tail: true)).to eq("\rfoo\t~2\n")
        end

        it "captures head/tail for Proximity" do
          tree = parse("\r\"foo\"\t~2\n")
          expect(tree).to eq(Proximity.new(Phrase.new('"foo"'), degree: 2))
          expect(tree.head).to eq("")
          expect(tree.tail).to eq("\n")
          expect(tree.pos).to eq(0)
          expect(tree.size).to eq(9)
          foo, = tree.children
          expect(foo.head).to eq("\r")
          expect(foo.tail).to eq("\t")
          expect(foo.pos).to eq(1)
          expect(foo.size).to eq(5)
          expect(tree.to_s).to eq("\r\"foo\"\t~2")
          expect(tree.to_s(head_tail: true)).to eq("\r\"foo\"\t~2\n")
        end

        it "preserves complex queries verbatim" do
          query = "\rfoo AND bar  \nAND \t(\rbaz OR    spam\rOR ham\t\t)\r"
          tree = parse(query)
          expect(tree.to_s).to eq(query)
          expect(tree.to_s(head_tail: true)).to eq(query)
        end

        it "strips head/tail at topmost element via plain to_s" do
          query = "\r(foo AND bar  \nAND \t(\rbaz OR    spam\rOR ham\t\t))\r"
          tree = parse(query)
          expect(tree.to_s).to eq(query.strip)
          expect(tree.to_s(head_tail: true)).to eq(query)
        end
      end
    end
  end
end
