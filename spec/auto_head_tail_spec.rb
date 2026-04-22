# frozen_string_literal: true
require "luqum/tree"
require "luqum/auto_head_tail"

module Luqum
  module Tree
    RSpec.describe Luqum::AutoHeadTail do
      it "pads OR operations" do
        tree = OrOperation.new(Word.new("foo"), Word.new("bar"), Word.new("baz"))
        expect(tree.to_s).to eq("fooORbarORbaz")
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq("foo OR bar OR baz")
      end

      it "pads AND operations" do
        tree = AndOperation.new(Word.new("foo"), Word.new("bar"), Word.new("baz"))
        expect(tree.to_s).to eq("fooANDbarANDbaz")
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq("foo AND bar AND baz")
      end

      it "pads unknown operations" do
        tree = UnknownOperation.new(Word.new("foo"), Word.new("bar"), Word.new("baz"))
        expect(tree.to_s).to eq("foobarbaz")
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq("foo bar baz")
      end

      it "pads ranges" do
        tree = Range.new(Word.new("foo"), Word.new("bar"))
        expect(tree.to_s).to eq("[fooTObar]")
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq("[foo TO bar]")
      end

      it "pads NOT" do
        tree = Not.new(Word.new("foo"))
        expect(tree.to_s).to eq("NOTfoo")
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq("NOT foo")
      end

      it "pads a complex tree idempotently" do
        tree = Group.new(
          OrOperation.new(
            SearchField.new(
              "foo",
              FieldGroup.new(UnknownOperation.new(Word.new("bar"), Range.new(Word.new("baz"), Word.new("spam")))),
            ),
            Not.new(Proximity.new(Phrase.new('"ham ham"'), degree: 2)),
            Plus.new(Fuzzy.new(Word.new("hammer"), degree: 3)),
          ),
        )
        expect(tree.to_s).to eq('(foo:(bar[bazTOspam])ORNOT"ham ham"~2OR+hammer~3)')
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq(
          '(foo:(bar [baz TO spam]) OR NOT "ham ham"~2 OR +hammer~3)',
        )
        expect(Luqum::AutoHeadTail.auto_head_tail(Luqum::AutoHeadTail.auto_head_tail(tree)).to_s).to eq(
          '(foo:(bar [baz TO spam]) OR NOT "ham ham"~2 OR +hammer~3)',
        )
      end

      it "preserves existing head/tail values" do
        tree = AndOperation.new(
          Range.new(Word.new("foo", tail: "\t"), Word.new("bar", head: "\n"), tail: "\r"),
          Not.new(Word.new("baz", head: "\t\t"), head: "\n\n", tail: "\r\r"),
          Word.new("spam", head: "\t\n"),
        )
        expect(tree.to_s).to eq("[foo\tTO\nbar]\rAND\n\nNOT\t\tbaz\r\rAND\t\nspam")
        expect(Luqum::AutoHeadTail.auto_head_tail(tree).to_s).to eq(
          "[foo\tTO\nbar]\rAND\n\nNOT\t\tbaz\r\rAND\t\nspam",
        )
      end
    end
  end
end
