require "luqum/tree"
require "luqum/pretty"

module Luqum
  module Tree
    RSpec.describe Luqum::Pretty::Prettifier do
      big_tree = AndOperation.new(
        Group.new(OrOperation.new(Word.new("baaaaaaaaaar"), Word.new("baaaaaaaaaaaaaz"))),
        Word.new("fooooooooooo")
      )
      fat_tree = AndOperation.new(
        SearchField.new(
          "subject",
          FieldGroup.new(
            OrOperation.new(
              Word.new("fiiiiiiiiiiz"),
              AndOperation.new(Word.new("baaaaaaaaaar"), Word.new("baaaaaaaaaaaaaz"))
            )
          )
        ),
        AndOperation.new(Word.new("fooooooooooo"), Word.new("wiiiiiiiiiz"))
      )

      it "fits on one line when short enough" do
        tree = AndOperation.new(
          Group.new(OrOperation.new(Word.new("bar"), Word.new("baz"))),
          Word.new("foo")
        )
        expect(Luqum::Pretty.prettify(tree)).to eq("( bar OR baz ) AND foo")
      end

      it "handles unknown operations" do
        prettify = Luqum::Pretty::Prettifier.new(indent: 8, max_len: 20)
        tree = UnknownOperation.new(
          Group.new(UnknownOperation.new(Word.new("baaaaaaaaaar"), Word.new("baaaaaaaaaaaaaz"))),
          Word.new("fooooooooooo")
        )
        expect("\n" + prettify.call(tree)).to eq(<<~OUT.chomp)

          (
                  baaaaaaaaaar
                  baaaaaaaaaaaaaz
          )
          fooooooooooo
        OUT
      end

      it "handles nested unknown operations" do
        prettify = Luqum::Pretty::Prettifier.new(indent: 8, max_len: 20)
        tree = OrOperation.new(
          UnknownOperation.new(Word.new("baaaaaaaaaar"), Word.new("baaaaaaaaaaaaaz")),
          Word.new("fooooooooooo")
        )
        expect("\n" + prettify.call(tree)).to eq(<<~OUT.chomp)

                  baaaaaaaaaar
                  baaaaaaaaaaaaaz
          OR
          fooooooooooo
        OUT
      end

      it "formats small max_len, indent=8" do
        prettify = Luqum::Pretty::Prettifier.new(indent: 8, max_len: 20)
        expect("\n" + prettify.call(big_tree)).to eq(<<~OUT.chomp)

          (
                  baaaaaaaaaar
                  OR
                  baaaaaaaaaaaaaz
          )
          AND
          fooooooooooo
        OUT

        expect("\n" + prettify.call(fat_tree)).to eq(<<~OUT.chomp)

          subject: (
                  fiiiiiiiiiiz
                  OR
                          baaaaaaaaaar
                          AND
                          baaaaaaaaaaaaaz
          )
          AND
          fooooooooooo
          AND
          wiiiiiiiiiz
        OUT
      end

      it "formats small max_len, inline_ops" do
        prettify = Luqum::Pretty::Prettifier.new(indent: 8, max_len: 20, inline_ops: true)
        expect("\n" + prettify.call(big_tree)).to eq(<<~OUT.chomp)

          (
                  baaaaaaaaaar OR
                  baaaaaaaaaaaaaz ) AND
          fooooooooooo
        OUT

        expect("\n" + prettify.call(fat_tree)).to eq(<<~OUT.chomp)

          subject: (
                  fiiiiiiiiiiz OR
                          baaaaaaaaaar AND
                          baaaaaaaaaaaaaz ) AND
          fooooooooooo AND
          wiiiiiiiiiz
        OUT
      end

      it "formats normal max_len, indent=4" do
        prettify = Luqum::Pretty::Prettifier.new(indent: 4, max_len: 50)
        expect("\n" + prettify.call(big_tree)).to eq(<<~OUT.chomp)

          (
              baaaaaaaaaar OR baaaaaaaaaaaaaz
          )
          AND
          fooooooooooo
        OUT

        expect("\n" + prettify.call(fat_tree)).to eq(<<~OUT.chomp)

          subject: (
              fiiiiiiiiiiz
              OR
                  baaaaaaaaaar AND baaaaaaaaaaaaaz
          )
          AND
          fooooooooooo
          AND
          wiiiiiiiiiz
        OUT
      end

      it "formats normal max_len, inline_ops" do
        prettify = Luqum::Pretty::Prettifier.new(indent: 4, max_len: 50, inline_ops: true)
        expect("\n" + prettify.call(big_tree)).to eq(<<~OUT.chomp)

          (
              baaaaaaaaaar OR baaaaaaaaaaaaaz ) AND
          fooooooooooo
        OUT

        expect("\n" + prettify.call(fat_tree)).to eq(<<~OUT.chomp)

          subject: (
              fiiiiiiiiiiz OR
                  baaaaaaaaaar AND baaaaaaaaaaaaaz ) AND
          fooooooooooo AND
          wiiiiiiiiiz
        OUT
      end
    end
  end
end
