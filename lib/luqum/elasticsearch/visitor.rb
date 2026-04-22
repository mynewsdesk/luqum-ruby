require "set"
require "luqum/check"
require "luqum/naming"
require "luqum/utils"
require "luqum/visitor"
require "luqum/elasticsearch/tree"

module Luqum
  module Elasticsearch
    module Visitor
      EMust = Luqum::Elasticsearch::Tree::EMust
      EMustNot = Luqum::Elasticsearch::Tree::EMustNot
      EShould = Luqum::Elasticsearch::Tree::EShould
      EWord = Luqum::Elasticsearch::Tree::EWord
      EPhrase = Luqum::Elasticsearch::Tree::EPhrase
      ERange = Luqum::Elasticsearch::Tree::ERange
      ENested = Luqum::Elasticsearch::Tree::ENested
      EBoolOperation = Luqum::Elasticsearch::Tree::EBoolOperation
      ElasticSearchItemFactory = Luqum::Elasticsearch::Tree::ElasticSearchItemFactory

      class ElasticsearchQueryBuilder < Luqum::Visitor::TreeVisitor
        SHOULD = "should".freeze
        MUST = "must".freeze

        CONTEXT_ANALYZE_MARKER = "analyzed".freeze
        CONTEXT_FIELD_PREFIX = "field_prefix".freeze

        E_MUST = EMust
        E_MUST_NOT = EMustNot
        E_SHOULD = EShould
        E_WORD = EWord
        E_PHRASE = EPhrase
        E_RANGE = ERange
        E_NESTED = ENested
        E_BOOL_OPERATION = EBoolOperation

        def initialize(default_operator: SHOULD, default_field: "text",
                       not_analyzed_fields: nil, nested_fields: nil, object_fields: nil,
                       sub_fields: nil, field_options: nil, match_word_as_phrase: false)
          super(track_parents: true)
          @not_analyzed_fields = not_analyzed_fields || []
          @nested_fields = normalize_nested_fields(nested_fields)
          @nested_prefixes = Set.new(
            Luqum::Utils.flatten_nested_fields_specs(@nested_fields).map do |field|
              field.include?(".") ? field.rpartition(".").first : field
            end
          )
          @object_fields = normalize_object_fields(object_fields)
          @sub_fields = sub_fields
          @field_options = field_options || {}
          @default_operator = default_operator
          @default_field = default_field
          @es_item_factory = ElasticSearchItemFactory.new(@not_analyzed_fields, @nested_fields, @field_options)
          @nesting_checker = Luqum::Check::CheckNestedFields.new(
            @nested_fields,
            object_fields: @object_fields,
            sub_fields: @sub_fields
          )
          @match_word_as_phrase = match_word_as_phrase
        end

        def call(tree)
          @nesting_checker.call(tree)
          visit(tree).first.json
        end

        def visit_and_operation(node, context, &block)
          must_operation(node, context, &block)
        end

        def visit_or_operation(node, context, &block)
          should_operation(node, context, &block)
        end

        def visit_search_field(node, context)
          prefix = field_prefix(context) + node.name.split(".")
          full_name = prefix.join(".")
          child_context = context.dup
          child_context[:parents] = (context[:parents] || []) + [node]
          child_context[CONTEXT_ANALYZE_MARKER] = !@not_analyzed_fields.include?(full_name)
          child_context[CONTEXT_FIELD_PREFIX] = prefix
          propagate_name(node, child_context)

          enode = visit(node.expr, child_context).first
          nested_path = split_nested(node, context)
          skip_nesting = enode.is_a?(self.class::E_NESTED)
          if !nested_path.nil? && !skip_nesting
            enode = @es_item_factory.build(
              self.class::E_NESTED,
              nested_path: nested_path,
              items: enode,
              _name: effective_name(node, context)
            )
          end
          yield enode
        end

        def visit_not(node, context)
          children = simplify_if_same(node.children, node)
          child_context = context.dup
          child_context[:parents] = (context[:parents] || []) + [node]
          propagate_name(node, child_context)
          items = children.flat_map { |child| visit(child, child_context) }
          yield @es_item_factory.build(self.class::E_MUST_NOT, items)
        end

        def visit_prohibit(node, context, &block)
          visit_not(node, context, &block)
        end

        def visit_plus(node, context, &block)
          must_operation(node, context, &block)
        end

        def visit_bool_operation(node, context, &block)
          binary_operation(self.class::E_BOOL_OPERATION, node, context, &block)
        end

        def visit_unknown_operation(node, context, &block)
          if @default_operator == SHOULD
            should_operation(node, context, &block)
          else
            must_operation(node, context, &block)
          end
        end

        def visit_boost(node, context)
          eword = collect_generic(node, context).first
          eword.boost = node.force.to_f
          yield eword
        end

        def visit_fuzzy(node, context)
          eword = collect_generic(node, context).first
          eword.fuzziness = node.degree.to_f
          yield eword
        end

        def visit_proximity(node, context)
          ephrase = collect_generic(node, context).first
          if analyzed?(context)
            ephrase.slop = node.degree.to_f
          else
            ephrase.fuzziness = node.degree.to_f
          end
          yield ephrase
        end

        def generic_visit(node, context)
          child_context = context.dup
          propagate_name(node, child_context)
          super(node, child_context) { |item| yield item }
        end

        def visit_word(node, context)
          method_name = if analyzed?(context)
                          @match_word_as_phrase ? "match_phrase" : "match"
                        else
                          "term"
                        end
          yield @es_item_factory.build(
            self.class::E_WORD,
            node.value,
            method: method_name,
            fields: fields(context),
            _name: effective_name(node, context)
          )
        end

        def visit_phrase(node, context)
          if analyzed?(context)
            yield @es_item_factory.build(
              self.class::E_PHRASE,
              node.value,
              fields: fields(context),
              _name: effective_name(node, context)
            )
          else
            yield @es_item_factory.build(
              self.class::E_WORD,
              node.value[1...-1],
              fields: fields(context),
              _name: effective_name(node, context)
            )
          end
        end

        def visit_range(node, context)
          kwargs = {}
          kwargs[node.include_low ? :gte : :gt] = node.low.value
          kwargs[node.include_high ? :lte : :lt] = node.high.value
          yield @es_item_factory.build(
            self.class::E_RANGE,
            fields: fields(context),
            _name: effective_name(node, context),
            **kwargs
          )
        end

        private

        def field_prefix(context)
          context&.fetch(CONTEXT_FIELD_PREFIX, [])
        end

        def fields(context)
          default = [@default_field]
          context&.fetch(CONTEXT_FIELD_PREFIX, default) || default
        end

        def split_nested(node, context)
          names = node.name.split(".")
          prefix = field_prefix(context)
          nested_prefix = nil

          names.length.times do |i|
            candidate = prefix + (i.zero? ? names : names[0...-i])
            joined = candidate.join(".")
            if @nested_prefixes.include?(joined)
              nested_prefix = joined
              break
            end
          end

          nested_prefix
        end

        def analyzed?(context)
          marker = context&.[](CONTEXT_ANALYZE_MARKER)
          marker.nil? ? !@not_analyzed_fields.include?(@default_field) : marker
        end

        def normalize_nested_fields(nested_fields)
          Luqum::Utils.normalize_nested_fields_specs(nested_fields)
        end

        def normalize_object_fields(object_fields)
          Luqum::Utils.normalize_object_fields_specs(object_fields)
        end

        def simplify_if_same(children, current_node)
          children.flat_map do |child|
            child.class == current_node.class ? simplify_if_same(child.children, current_node) : [child]
          end
        end

        def get_operator_extract(binary_operation, delta = 8)
          node_str = binary_operation.to_s
          child_str_1 = binary_operation.children[0].to_s
          child_str_2 = binary_operation.children[1].to_s
          middle_length = node_str.length - child_str_1.length - child_str_2.length
          position = node_str.index(child_str_2)
          start = [position - middle_length - delta, 0].max
          ending = position + delta
          node_str[start...ending]
        end

        def must?(operation)
          operation.is_a?(Luqum::Tree::AndOperation) ||
            (operation.is_a?(Luqum::Tree::UnknownOperation) && @default_operator == MUST)
        end

        def should?(operation)
          operation.is_a?(Luqum::Tree::OrOperation) ||
            (operation.is_a?(Luqum::Tree::UnknownOperation) && @default_operator == SHOULD)
        end

        def propagate_name(node, child_context)
          name = Luqum::Naming.get_name(node)
          child_context["name"] = name unless name.nil?
        end

        def effective_name(node, context)
          name = Luqum::Naming.get_name(node)
          name.nil? ? context["name"] : name
        end

        def yield_nested_children(parent, children)
          children.each do |child|
            if (should?(parent) && must?(child)) || (must?(parent) && should?(child))
              raise Luqum::OrAndAndOnSameLevelError, get_operator_extract(child)
            end
            yield child
          end
        end

        def binary_operation(cls, node, context)
          children = simplify_if_same(node.children, node)
          child_context = context.dup
          propagate_name(node, child_context)

          items = []
          yield_nested_children(node, children) do |child|
            items.concat(visit(child, child_context))
          end
          yield @es_item_factory.build(cls, items)
        end

        def must_operation(node, context, &block)
          binary_operation(self.class::E_MUST, node, context, &block)
        end

        def should_operation(node, context, &block)
          binary_operation(self.class::E_SHOULD, node, context, &block)
        end

        def collect_generic(node, context)
          results = []
          generic_visit(node, context) { |item| results << item }
          results
        end
      end
    end
  end
end
