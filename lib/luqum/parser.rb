# frozen_string_literal: true

require "luqum/tree"
require "luqum/exceptions"
require "luqum/head_tail"
require "luqum/lexer"

module Luqum
  module Parser
    # Operator precedence (higher = binds tighter).
    IMPLICIT_PREC = 1
    OR_PREC = 2
    AND_PREC = 3

    # Token types that can start a unary expression (for detecting implicit
    # concatenation).
    UNARY_START = %i[TERM PHRASE REGEX LPAREN LBRACKET PLUS MINUS NOT LESSTHAN GREATERTHAN TO].freeze

    class << self
      def parse(input)
        tokens = Lexer.new.tokenize(input)
        Engine.new(tokens).parse
      end
    end

    class Engine
      def initialize(tokens)
        @tokens = tokens
        @pos = 0
      end

      def parse
        tree = parse_expression(0)
        raise_syntax_error(peek) if peek
        tree
      end

      private

      def peek
        @tokens[@pos]
      end

      def peek_type
        @tokens[@pos]&.type
      end

      def consume
        tok = @tokens[@pos]
        @pos += 1
        tok
      end

      def expect(type)
        tok = peek
        raise_syntax_error(tok) unless tok&.type == type
        consume
      end

      def raise_syntax_error(tok)
        if tok.nil?
          raise ParseSyntaxError,
            "Syntax error in input : unexpected end of expression (maybe due to unmatched parenthesis) at the end!"
        else
          raise ParseSyntaxError,
            "Syntax error in input : unexpected  '#{tok.value}' at position #{tok.pos}!"
        end
      end

      def parse_expression(min_prec)
        left = parse_unary
        loop do
          t = peek_type
          case t
          when :OR_OP
            break if min_prec > OR_PREC

            op_tok = consume
            right = parse_expression(OR_PREC + 1)
            p_arr = [nil, left, op_tok.value, right]
            merged = Tree.create_operation(Tree::OrOperation, left, right, op_tail: op_tok.value.tail)
            p_arr[0] = merged
            Luqum::HEAD_TAIL.binary_operation(p_arr, op_tail: op_tok.value.tail)
            left = merged
          when :AND_OP
            break if min_prec > AND_PREC

            op_tok = consume
            right = parse_expression(AND_PREC + 1)
            p_arr = [nil, left, op_tok.value, right]
            merged = Tree.create_operation(Tree::AndOperation, left, right, op_tail: op_tok.value.tail)
            p_arr[0] = merged
            Luqum::HEAD_TAIL.binary_operation(p_arr, op_tail: op_tok.value.tail)
            left = merged
          else
            if UNARY_START.include?(t)
              break if min_prec > IMPLICIT_PREC

              right = parse_expression(IMPLICIT_PREC + 1)
              merged = Tree.create_operation(Tree::UnknownOperation, left, right, op_tail: "")
              # pos/size: compute span from left to right
              p_arr = [merged, left, right]
              Luqum::HEAD_TAIL.binary_operation(p_arr, op_tail: "")
              left = merged
            else
              break
            end
          end
        end
        left
      end

      def parse_unary
        t = peek_type
        case t
        when :PLUS
          op_tok = consume
          inner = parse_unary
          node = Tree::Plus.new(inner)
          Luqum::HEAD_TAIL.unary([node, op_tok.value, inner])
          node
        when :MINUS
          op_tok = consume
          inner = parse_unary
          node = Tree::Prohibit.new(inner)
          Luqum::HEAD_TAIL.unary([node, op_tok.value, inner])
          node
        when :NOT
          op_tok = consume
          inner = parse_unary
          node = Tree::Not.new(inner)
          Luqum::HEAD_TAIL.unary([node, op_tok.value, inner])
          node
        else
          atom = parse_atom
          # postfix BOOST applies to any unary_expression
          while peek_type == :BOOST
            boost_tok = consume
            new_node = Tree::Boost.new(atom, force: boost_tok.value.value)
            Luqum::HEAD_TAIL.post_unary([new_node, atom, boost_tok.value])
            atom = new_node
          end
          atom
        end
      end

      def parse_atom
        t = peek
        raise_syntax_error(nil) if t.nil?

        case t.type
        when :LPAREN
          parse_group
        when :LBRACKET
          parse_range
        when :LESSTHAN
          parse_lessthan
        when :GREATERTHAN
          parse_greaterthan
        when :PHRASE
          parse_phrase_atom
        when :REGEX
          consume.value
        when :TO
          # TO used as a term outside of range
          tok = consume
          word = Tree::Word.new(tok.value.value)
          Luqum::HEAD_TAIL.simple_term([word, tok.value])
          word
        when :TERM
          parse_term_atom
        else
          raise_syntax_error(t)
        end
      end

      def parse_phrase_atom
        phrase_tok = consume
        phrase = phrase_tok.value
        if peek_type == :APPROX
          approx_tok = consume
          prox = Tree::Proximity.new(phrase, degree: approx_tok.value.value)
          Luqum::HEAD_TAIL.post_unary([prox, phrase, approx_tok.value])
          prox
        else
          phrase
        end
      end

      def parse_term_atom
        term_tok = consume
        term = term_tok.value
        case peek_type
        when :APPROX
          approx_tok = consume
          fuzzy = Tree::Fuzzy.new(term, degree: approx_tok.value.value)
          Luqum::HEAD_TAIL.post_unary([fuzzy, term, approx_tok.value])
          fuzzy
        when :COLUMN
          col_tok = consume
          inner = parse_unary
          inner = Tree.group_to_fieldgroup(inner) if inner.is_a?(Tree::Group)
          sf = Tree::SearchField.new(term.value, inner)
          Luqum::HEAD_TAIL.search_field([sf, term, col_tok.value, inner])
          sf
        else
          term
        end
      end

      def parse_group
        lparen = consume
        expr = parse_expression(0)
        rparen_tok = peek
        unless rparen_tok&.type == :RPAREN
          raise_syntax_error(rparen_tok)
        end
        rparen = consume
        group = Tree::Group.new(expr)
        Luqum::HEAD_TAIL.paren([group, lparen.value, expr, rparen.value])
        group
      end

      def parse_range
        lbracket = consume
        include_low = lbracket.value.value == "["
        low = parse_range_bound
        to_tok = peek
        unless to_tok&.type == :TO
          raise_syntax_error(to_tok)
        end
        to = consume
        high = parse_range_bound
        rbracket_tok = peek
        unless rbracket_tok&.type == :RBRACKET
          raise_syntax_error(rbracket_tok)
        end
        rbracket = consume
        include_high = rbracket.value.value == "]"
        range = Tree::Range.new(low, high, include_low: include_low, include_high: include_high)
        Luqum::HEAD_TAIL.range([range, lbracket.value, low, to.value, high, rbracket.value])
        range
      end

      # phrase_or_possibly_negative_term: PHRASE | TERM | MINUS PHRASE | MINUS TERM
      def parse_range_bound
        if peek_type == :PHRASE
          return consume.value
        end

        if peek_type == :MINUS
          minus_tok = consume
          inner = parse_phrase_or_term
          node = Tree::Prohibit.new(inner)
          Luqum::HEAD_TAIL.unary([node, minus_tok.value, inner])
          return node
        end
        parse_phrase_or_term
      end

      def parse_phrase_or_term
        case peek_type
        when :PHRASE then consume.value
        when :TERM then consume.value
        else raise_syntax_error(peek)
        end
      end

      def parse_lessthan
        lt_tok = consume
        include_bound = lt_tok.value.value.include?("=")
        inner = parse_phrase_or_term
        node = Tree::To.new(inner, include: include_bound)
        Luqum::HEAD_TAIL.unary([node, lt_tok.value, inner])
        node
      end

      def parse_greaterthan
        gt_tok = consume
        include_bound = gt_tok.value.value.include?("=")
        inner = parse_phrase_or_term
        node = Tree::From.new(inner, include: include_bound)
        Luqum::HEAD_TAIL.unary([node, gt_tok.value, inner])
        node
      end
    end
  end
end
