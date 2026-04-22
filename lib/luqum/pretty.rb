# frozen_string_literal: true

require "luqum/tree"

module Luqum
  module Pretty
    # Sentinel used between two elements that must stick together.
    STICK_MARKER = Object.new
    def STICK_MARKER.length
      0
    end
    STICK_MARKER.freeze

    class Prettifier
      def initialize(indent: 4, max_len: 80, inline_ops: false)
        @indent = indent
        @prefix = " " * indent
        @max_len = max_len
        @inline_ops = inline_ops
      end

      def call(tree)
        chains = get_chains(tree, nil)
        with_counts, total = count_chars(chains)
        concatenate(with_counts, total)
      end

      private

      # Produce a flat array of strings and nested arrays (deeper indentation).
      def get_chains(element, parent)
        case element
        when Luqum::Tree::BaseOperation
          if !parent.is_a?(Luqum::Tree::BaseOperation) || element.class::OP == parent.class::OP
            items = []
            num = element.children.length
            element.children.each_with_index do |child, n|
              items.concat(get_chains(child, element))
              if n < num - 1
                items << STICK_MARKER if @inline_ops
                items << element.class::OP unless element.class::OP.empty?
              end
            end
            items
          else
            new_level = []
            num = element.children.length
            element.children.each_with_index do |child, n|
              new_level.concat(get_chains(child, element))
              if n < num - 1
                new_level << STICK_MARKER if @inline_ops
                new_level << element.class::OP unless element.class::OP.empty?
              end
            end
            [new_level]
          end
        when Luqum::Tree::BaseGroup
          items = ["("]
          items << get_chains(element.expr, element)
          items << STICK_MARKER if @inline_ops
          items << ")"
          items
        when Luqum::Tree::SearchField
          [
            "#{element.name}:",
            STICK_MARKER,
            *get_chains(element.expr, element),
          ]
        else
          [element.to_s]
        end
      end

      # Attach character counts to each element; nested arrays get a total count.
      def count_chars(element)
        if element.is_a?(Array)
          with_counts = element.map { |c| count_chars(c) }
          # add one space between items
          total = with_counts.sum { |_, n| n + 1 } - 1
          [with_counts, total]
        else
          [element, element.length]
        end
      end

      # Merge items around STICK_MARKER into the previous element with a separating space.
      def apply_stick(elements)
        result = []
        last = nil
        sticking = false
        elements.each do |current|
          if current.equal?(STICK_MARKER)
            raise "STICK_MARKER should never be first!" if last.nil?

            sticking = true
          elsif sticking
            last = "#{last} #{current}"
            sticking = false
          else
            result << last unless last.nil?
            last = current
          end
        end
        result << last unless last.nil?
        result
      end

      def concatenate(chain_with_counts, char_counts, level: 0, in_one_liner: false)
        one_liner = in_one_liner || char_counts < @max_len - (@indent * level)
        new_level = one_liner ? level : level + 1
        elements = chain_with_counts.map do |c, n|
          if c.is_a?(Array)
            concatenate(c, n, level: new_level, in_one_liner: one_liner)
          else
            c
          end
        end
        elements = apply_stick(elements)
        prefix = level > 0 && !in_one_liner ? @prefix : ""
        join_char = one_liner ? " " : "\n#{prefix}"
        prefix + elements.flat_map { |c| c.split("\n") }.join(join_char)
      end
    end

    # Default pretty-printing function.
    def self.prettify(tree)
      DEFAULT.call(tree)
    end

    DEFAULT = Prettifier.new
  end
end
