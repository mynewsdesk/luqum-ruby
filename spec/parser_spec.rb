require "bigdecimal"
require "luqum"
require "luqum/parser"

module Luqum
  module Tree
    RSpec.describe "Parser" do
      let(:parser) { Luqum::Parser }

      describe "lexer" do
        def simplify_tokens(tokens)
          tokens.map do |tok|
            v = tok.value
            [tok.type, v.is_a?(Term) ? v : v.value]
          end
        end

        it "tokenizes a complex query" do
          tokens = Luqum::Lexer.new.tokenize(
            'subject:test desc:(house OR car)^3 AND "big garage"~2 dirt~0.3 OR foo:{a TO z*]'
          )
          expect(simplify_tokens(tokens)).to eq([
            [:TERM, Word.new("subject")],
            [:COLUMN, ":"],
            [:TERM, Word.new("test")],
            [:TERM, Word.new("desc")],
            [:COLUMN, ":"],
            [:LPAREN, "("],
            [:TERM, Word.new("house")],
            [:OR_OP, "OR"],
            [:TERM, Word.new("car")],
            [:RPAREN, ")"],
            [:BOOST, "3"],
            [:AND_OP, "AND"],
            [:PHRASE, Phrase.new('"big garage"')],
            [:APPROX, "2"],
            [:TERM, Word.new("dirt")],
            [:APPROX, "0.3"],
            [:OR_OP, "OR"],
            [:TERM, Word.new("foo")],
            [:COLUMN, ":"],
            [:LBRACKET, "{"],
            [:TERM, Word.new("a")],
            [:TO, "TO"],
            [:TERM, Word.new("z*")],
            [:RBRACKET, "]"]
          ])
        end

        it "accepts date-like terms" do
          tokens = Luqum::Lexer.new.tokenize("somedate:[now/d-1d+7H TO now/d+7H]")
          expect(simplify_tokens(tokens)).to eq([
            [:TERM, Word.new("somedate")],
            [:COLUMN, ":"],
            [:LBRACKET, "["],
            [:TERM, Word.new("now/d-1d+7H")],
            [:TO, "TO"],
            [:TERM, Word.new("now/d+7H")],
            [:RBRACKET, "]"]
          ])
        end
      end

      describe "parser" do
        # Helpers
        def parse(s)
          Luqum::Parser.parse(s)
        end

        def expect_parses_to(input, tree)
          parsed = parse(input)
          expect(parsed.to_s).to eq(tree.to_s)
          expect(parsed).to eq(tree)
        end

        it "parses a simple AND" do
          tree = AndOperation.new(Word.new("foo", tail: " "), Word.new("bar", head: " "))
          expect_parses_to("foo AND bar", tree)
        end

        it "parses implicit concatenation" do
          tree = UnknownOperation.new(Word.new("foo", tail: " "), Word.new("bar"))
          expect_parses_to("foo bar", tree)
        end

        it "parses a simple field search" do
          tree = SearchField.new("subject", Word.new("test"))
          expect_parses_to("subject:test", tree)
        end

        it "parses fully-escaped word" do
          query = 'test\+\-\&\&\|\|\!\(\)\{\}\[\]\^\"\~\*\?\:\\\\test'
          tree = Word.new(query)
          unescaped = 'test+-&&||!(){}[]^"~*?:\test'
          parsed = parse(query)
          expect(parsed.to_s).to eq(query)
          expect(parsed).to eq(tree)
          expect(parsed.unescaped_value).to eq(unescaped)
        end

        it "parses a word starting with an escaped character" do
          ['+', '-', '&', '|', '!', '(', ')', '{', '}', '[', ']', '^', '"', '~', '*', '?', ':', '\\\\', '<', '>'].each do |letter|
            query = "\\#{letter}test"
            tree = Word.new(query)
            unescaped = "#{letter.gsub('\\\\', '\\')}test"
            parsed = parse(query)
            expect(parsed.to_s).to eq(query)
            expect(parsed).to eq(tree)
            expect(parsed.unescaped_value).to eq(unescaped)
          end
        end

        it "parses <\\=foo as To with include=false" do
          query = '<\=test'
          tree = To.new(Word.new('\=test'), include: false)
          parsed = parse(query)
          expect(parsed.to_s).to eq(query)
          expect(parsed).to eq(tree)
          expect(parsed.a.unescaped_value).to eq("=test")
        end

        it "parses an escaped phrase" do
          query = '"test \"ph\rase"'
          tree = Phrase.new(query)
          unescaped = '"test "phrase"'
          parsed = parse(query)
          expect(parsed.to_s).to eq(query)
          expect(parsed).to eq(tree)
          expect(parsed.unescaped_value).to eq(unescaped)
        end

        it "parses escaped colons in a field value" do
          query = 'ip:1000\:\:1000\:\:1/24'
          tree = SearchField.new("ip", Word.new('1000\:\:1000\:\:1/24'))
          parsed = parse(query)
          expect(parsed).to eq(tree)
          expect(parsed.to_s).to eq(query)
          expect(parsed.children[0].unescaped_value).to eq("1000::1000::1/24")
        end

        it "parses escaped colons in a bare term" do
          query = '1000\:1000\:\:1/24'
          tree = Word.new('1000\:1000\:\:1/24')
          parsed = parse(query)
          expect(parsed).to eq(tree)
          expect(parsed.to_s).to eq(query)
          expect(parsed.unescaped_value).to eq("1000:1000::1/24")
        end

        it "defaults boost to 1" do
          query = "boost^ me^1"
          parsed = parse(query)
          tree = UnknownOperation.new(
            Boost.new(Word.new("boost"), force: nil),
            Boost.new(Word.new("me"), force: 1)
          )
          expect(parsed).to eq(tree)
          expect(parsed.operands[0].force).to eq(1)
          expect(parsed.operands[0].implicit_force).to eq(true)
          expect(parsed.operands[1].force).to eq(BigDecimal("1"))
          expect(parsed.operands[1].implicit_force).to eq(false)
          expect(parsed.to_s).to eq(query)
        end

        it "parses field names with numbers" do
          tree = SearchField.new("field_42", Word.new("42"))
          expect_parses_to("field_42:42", tree)
        end

        it "treats comma as a term" do
          tree = UnknownOperation.new(
            Word.new("hi", tail: " "),
            Word.new(",", tail: " "),
            Word.new("bye")
          )
          expect_parses_to("hi , bye", tree)
        end

        it "parses - (prohibit) and NOT" do
          tree = AndOperation.new(
            Prohibit.new(Word.new("test", tail: " ")),
            Prohibit.new(Word.new("foo", tail: " "), head: " "),
            Not.new(Word.new("bar", head: " "), head: " ")
          )
          expect_parses_to("-test AND -foo AND NOT bar", tree)
        end

        it "parses + (plus)" do
          tree = AndOperation.new(
            Plus.new(Word.new("test", tail: " ")),
            Word.new("foo", head: " ", tail: " "),
            Plus.new(Word.new("bar"), head: " ")
          )
          expect_parses_to("+test AND foo AND +bar", tree)
        end

        it "parses quoted phrases" do
          tree = AndOperation.new(
            Phrase.new('"a phrase (AND a complicated~ one)"', tail: " "),
            Phrase.new('"Another one"', head: " ")
          )
          expect_parses_to('"a phrase (AND a complicated~ one)" AND "Another one"', tree)
        end

        it "parses regexes" do
          tree = AndOperation.new(
            Regex.new('/a regex (with some.*match+ing)?/', tail: " "),
            Regex.new('/Another one/', head: " ")
          )
          expect_parses_to('/a regex (with some.*match+ing)?/ AND /Another one/', tree)
        end

        it "parses proximity and fuzzy modifiers" do
          tree = UnknownOperation.new(
            Proximity.new(Phrase.new('"foo bar"'), degree: 3, tail: " "),
            Proximity.new(Phrase.new('"foo baz"'), degree: nil, tail: " "),
            Fuzzy.new(Word.new("baz"), degree: BigDecimal("0.3"), tail: " "),
            Fuzzy.new(Word.new("fou"), degree: nil)
          )
          expect_parses_to('"foo bar"~3 "foo baz"~ baz~0.3 fou~', tree)
        end

        it "parses boost" do
          tree = UnknownOperation.new(
            Boost.new(Phrase.new('"foo bar"'), force: BigDecimal("3.0"), tail: " "),
            Boost.new(
              Group.new(AndOperation.new(Word.new("baz", tail: " "), Word.new("bar", head: " "))),
              force: BigDecimal("2.1")
            )
          )
          expect_parses_to('"foo bar"^3 (baz AND bar)^2.1', tree)
        end

        it "parses groups" do
          tree = OrOperation.new(
            Word.new("test", tail: " "),
            Group.new(
              AndOperation.new(
                SearchField.new(
                  "subject",
                  FieldGroup.new(OrOperation.new(Word.new("foo", tail: " "), Word.new("bar", head: " "))),
                  tail: " "
                ),
                Word.new("baz", head: " ")
              ),
              head: " "
            )
          )
          expect_parses_to("test OR (subject:(foo OR bar) AND baz)", tree)
        end

        it "parses ranges" do
          tree = AndOperation.new(
            SearchField.new(
              "foo",
              Range.new(Word.new("10", tail: " "), Word.new("100", head: " "), include_low: true, include_high: true),
              tail: " "
            ),
            SearchField.new(
              "bar",
              Range.new(Word.new("a*", tail: " "), Word.new("*", head: " "), include_low: true, include_high: false),
              head: " "
            )
          )
          expect_parses_to("foo:[10 TO 100] AND bar:[a* TO *}", tree)
        end

        it "parses date-math ranges" do
          tree = SearchField.new(
            "somedate",
            Range.new(Word.new("now/d-1d+7H", tail: " "), Word.new("now/d+7H", head: " "), include_low: true, include_high: true)
          )
          expect_parses_to("somedate:[now/d-1d+7H TO now/d+7H]", tree)
        end

        it "parses complex combinations" do
          tree = UnknownOperation.new(
            SearchField.new("subject", Word.new("test"), tail: " "),
            AndOperation.new(
              SearchField.new(
                "desc",
                FieldGroup.new(OrOperation.new(Word.new("house", tail: " "), Word.new("car", head: " "))),
                tail: " "
              ),
              Not.new(
                Proximity.new(Phrase.new('"approximatly this"'), degree: 3, head: " "),
                head: " "
              )
            )
          )
          expect_parses_to('subject:test desc:(house OR car) AND NOT "approximatly this"~3', tree)
        end

        it "parses From/To open ranges" do
          tree = AndOperation.new(
            SearchField.new("foo", From.new(Word.new("10"), include: false), tail: " "),
            SearchField.new("bar", To.new(Word.new("11"), include: true), tail: " ", head: " "),
            SearchField.new("baz", From.new(Word.new("100"), include: true), tail: " ", head: " "),
            SearchField.new("fou", To.new(Phrase.new('"200"'), include: false), head: " ")
          )
          expect_parses_to('foo:>10 AND bar:<=11 AND baz:>=100 AND fou:<"200"', tree)
        end

        it "parses combined open ranges in a field group" do
          tree = SearchField.new("foo", FieldGroup.new(UnknownOperation.new(
            From.new(Word.new("10"), include: true, tail: " "),
            To.new(Word.new("11"), include: false)
          )))
          expect_parses_to("foo:(>=10 <11)", tree)
        end

        it "respects boost/plus/open-range precedence" do
          tree = Plus.new(Boost.new(From.new(Word.new("10"), include: true), force: 3))
          expect_parses_to("+>=10^3", tree)
        end

        it "associates unary operators with the closest unary expression" do
          tree = OrOperation.new(
            Word.new("1", tail: " "),
            AndOperation.new(
              Plus.new(Boost.new(Fuzzy.new(Word.new("2"), degree: 1), force: 1), tail: " "),
              Word.new("3", head: " "),
              head: " "
            )
          )
          expect_parses_to("1 OR +2~1^1 AND 3", tree)
        end

        it "gives implicit operation lowest precedence" do
          tree = UnknownOperation.new(
            Word.new("1", tail: " "),
            AndOperation.new(
              Word.new("2", tail: " "),
              Word.new("3", head: " "),
              tail: " "
            ),
            Word.new("4")
          )
          expect_parses_to("1 2 AND 3 4", tree)
        end

        it "allows reserved words in certain positions" do
          [
            ["foo:TO", SearchField.new("foo", Word.new("TO"))],
            ["foo:TO*", SearchField.new("foo", Word.new("TO*"))],
            ["foo:NOT*", SearchField.new("foo", Word.new("NOT*"))],
            ['foo:"TO AND OR"', SearchField.new("foo", Phrase.new('"TO AND OR"'))]
          ].each { |input, tree| expect_parses_to(input, tree) }
        end

        it "parses dates as field values" do
          [
            ["foo:2015-12-19", SearchField.new("foo", Word.new("2015-12-19"))],
            ["foo:2015-12-19T22:30", SearchField.new("foo", Word.new("2015-12-19T22:30"))],
            ["foo:2015-12-19T22:30:45", SearchField.new("foo", Word.new("2015-12-19T22:30:45"))],
            ["foo:2015-12-19T22:30:45.234Z", SearchField.new("foo", Word.new("2015-12-19T22:30:45.234Z"))]
          ].each { |input, tree| expect_parses_to(input, tree) }
        end

        it "parses date-math expressions in a field value" do
          [
            ['foo:2015-12-19||+2\d', SearchField.new("foo", Word.new('2015-12-19||+2\d'))],
            ['foo:now+2h+20m\h', SearchField.new("foo", Word.new('now+2h+20m\h'))]
          ].each { |input, tree| expect_parses_to(input, tree) }
        end

        it "parses date-math expressions in a range" do
          tree = SearchField.new(
            "foo",
            Range.new(Word.new('2015-12-19||+2\d', tail: " "), Word.new('now+3d+12h\h', head: " "))
          )
          expect_parses_to('foo:[2015-12-19||+2\d TO now+3d+12h\h]', tree)
        end

        it "raises on reserved words in illegal positions" do
          expect { parse("foo:NOT") }.to raise_error(Luqum::ParseSyntaxError, /unexpected end of expr/)
          expect { parse("foo:AND") }.to raise_error(Luqum::ParseSyntaxError, /unexpected.*'AND' at position 4/)
          expect { parse("foo:OR") }.to raise_error(Luqum::ParseSyntaxError, /unexpected.*'OR' at position 4/)
          expect { parse("OR") }.to raise_error(Luqum::ParseSyntaxError, /unexpected.*'OR' at position 0/)
          expect { parse("AND") }.to raise_error(Luqum::ParseSyntaxError, /unexpected.*'AND' at position 0/)
        end

        it "raises on unmatched parenthesis" do
          expect { parse("((foo bar) ") }.to raise_error(Luqum::ParseSyntaxError, /unexpected end of expr/)
        end

        it "raises on unmatched bracket" do
          expect { parse("[foo TO bar") }.to raise_error(Luqum::ParseSyntaxError, /unexpected end of expr/)
        end

        it "raises on unclosed range with missing upper bound" do
          expect { parse("[foo TO ]") }.to raise_error(Luqum::ParseSyntaxError, /unexpected.*']' at position 8/)
        end

        it "raises on illegal character" do
          expect { parse("\\") }.to raise_error(Luqum::IllegalCharacterError, /Illegal character '\\' at position 0/)
        end

        it "parses negative values in ranges" do
          expect(parse("[-1 TO 5]").to_s).to eq("[-1 TO 5]")
          expect(parse("[-10 TO -1]").to_s).to eq("[-10 TO -1]")
          expect(parse("[5 TO -1]").to_s).to eq("[5 TO -1]")
        end
      end
    end
  end
end
