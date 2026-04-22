# frozen_string_literal: true
require "luqum/utils"
require "luqum/visitor"

module Luqum
  module Check
    class LuceneCheck
      FIELD_NAME_RE = /^\w+$/
      SPACE_RE = /\s/
      INVALID_TERM_CHARS_RE = %r{[+/-]}

      SIMPLE_EXPR_FIELDS = [
        Luqum::Tree::Boost,
        Luqum::Tree::Proximity,
        Luqum::Tree::Fuzzy,
        Luqum::Tree::Word,
        Luqum::Tree::Phrase,
      ].freeze
      FIELD_EXPR_FIELDS = (SIMPLE_EXPR_FIELDS + [Luqum::Tree::FieldGroup]).freeze

      def initialize(zeal: 0)
        @zeal = zeal
      end

      def check_search_field(item, parents)
        errors = []
        errors << "#{item.name} is not a valid field name" unless check_field_name(item.name)
        errors << "field expression is not valid : #{item}" unless FIELD_EXPR_FIELDS.any? { |cls| item.expr.is_a?(cls) }
        errors.concat(check_children(item, parents))
      end

      def check_group(item, parents)
        errors = []
        if parents.any? && parents[-1].is_a?(Luqum::Tree::SearchField)
          errors << "Group misuse, after SearchField you should use Group : #{parents[-1]}"
        end
        errors.concat(check_children(item, parents))
      end

      def check_field_group(item, parents)
        errors = []
        unless parents.any? && parents[-1].is_a?(Luqum::Tree::SearchField)
          errors << "FieldGroup misuse, it must be used after SearchField : #{parents.any? ? parents[-1] : item}"
        end
        errors.concat(check_children(item, parents))
      end

      def check_range(_item, _parents)
        []
      end

      def check_word(item, _parents)
        errors = []
        errors << "A single term value can't hold a space #{item}" if item.value.match?(SPACE_RE)
        if @zeal.positive? && item.value.match?(INVALID_TERM_CHARS_RE)
          errors << "Invalid characters in term value: #{item.value}"
        end
        errors
      end

      def check_fuzzy(item, _parents)
        errors = []
        errors << "invalid degree #{Luqum::Tree.format_decimal(item.degree)}, it must be positive" if item.degree.negative?
        errors << "Fuzzy should be on a single term in #{item}" unless item.term.is_a?(Luqum::Tree::Word)
        errors
      end

      def check_proximity(item, _parents)
        return [] if item.term.is_a?(Luqum::Tree::Phrase)

        ["Proximity can be only on a phrase in #{item}"]
      end

      def check_boost(item, parents)
        check_children(item, parents)
      end

      def check_base_operation(item, parents)
        check_children(item, parents)
      end

      def check_plus(item, parents)
        check_children(item, parents)
      end

      def check_not(item, parents)
        check_not_operator(item, parents) + check_children(item, parents)
      end

      def check_prohibit(item, parents)
        check_not_operator(item, parents) + check_children(item, parents)
      end

      def check(item, parents = nil)
        parents ||= []
        item.class.ancestors.each do |cls|
          next unless cls.is_a?(Class)

          candidate = "check_#{Luqum::Visitor.camel_to_lower(cls.name.split('::').last)}"
          return send(candidate, item, parents) if respond_to?(candidate, true)
        end
        ["Unknown item type #{item.class.name.split('::').last} : #{item}"]
      end

      def call(tree)
        check(tree).empty?
      end

      def errors(tree)
        check(tree)
      end

      private

      def check_field_name(field_name)
        field_name.match?(FIELD_NAME_RE)
      end

      def check_children(item, parents)
        item.children.flat_map { |child| check(child, parents + [item]) }
      end

      def check_not_operator(_item, parents)
        if @zeal.positive? && parents.any? && parents[-1].is_a?(Luqum::Tree::OrOperation)
          ["Prohibit or Not really means 'AND NOT' wich is inconsistent with OR operation in #{parents[-1]}"]
        else
          []
        end
      end
    end

    class CheckNestedFields < Luqum::Visitor::TreeVisitor
      def initialize(nested_fields, object_fields: nil, sub_fields: nil)
        raise ArgumentError, "nested_fields must be a Hash" unless nested_fields.is_a?(Hash)

        @object_fields = Luqum::Utils.normalize_object_fields_specs(object_fields)
        @object_prefixes = Set.new((@object_fields || []).map { |field|
          field.include?(".") ? field.rpartition(".").first : field
        })
        @nested_fields = Luqum::Utils.flatten_nested_fields_specs(nested_fields)
        @nested_prefixes = Set.new(@nested_fields.map { |field| field.include?(".") ? field.rpartition(".").first : field })
        @sub_fields = Luqum::Utils.normalize_object_fields_specs(sub_fields)
        super(track_parents: true)
      end

      def visit_search_field(node, context, &)
        child_context = context.dup
        child_context[:prefix] = context[:prefix] + node.name.split(".")
        generic_visit(node, child_context, &)
      end

      def visit_phrase(node, context)
        check_final_operation(node, context)
      end

      def visit_term(node, context)
        check_final_operation(node, context)
      end

      def call(tree)
        visit(tree, { prefix: [] })
      end

      private

      def check_final_operation(node, context)
        prefix = context[:prefix]
        return if prefix.empty?

        fullname = prefix.join(".")
        if @nested_prefixes.include?(fullname)
          raise Luqum::NestedSearchFieldError,
            %("#{node}" can't be directly attributed to "#{fullname}" as it is a nested field)
        elsif @object_prefixes.include?(fullname)
          raise Luqum::NestedSearchFieldError,
            %("#{node}" can't be directly attributed to "#{fullname}" as it is an object field)
        elsif prefix.length > 1
          unknown_field = !@sub_fields.nil? &&
                          !@object_fields.nil? &&
                          !@sub_fields.include?(fullname) &&
                          !@object_fields.include?(fullname) &&
                          !@nested_fields.include?(fullname)
          if unknown_field
            raise Luqum::ObjectSearchFieldError,
              %("#{node}" attributed to unknown nested or object field "#{fullname}")
          end
        end
      end
    end
  end
end
