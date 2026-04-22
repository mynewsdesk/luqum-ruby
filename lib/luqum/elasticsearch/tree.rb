require "luqum/tree"

module Luqum
  module Elasticsearch
    module Tree
      module JsonSerializableMixin
        def json
          raise NotImplementedError
        end
      end

      class AbstractEItem
        include JsonSerializableMixin

        BASE_KEYS_TO_ADD = ["boost", "fuzziness", "_name"].freeze

        attr_accessor :boost, :zero_terms_query, :field_options

        def initialize(no_analyze: nil, method: "term", fields: [], _name: nil, field_options: nil)
          @method_name = method
          @fields = fields
          @no_analyze = no_analyze || []
          @zero_terms_query = "none"
          @field_options = field_options || {}
          @_name = _name unless _name.nil?
          @additional_keys_to_add = self.class.const_defined?(:DEFAULT_ADDITIONAL_KEYS_TO_ADD, false) ?
            self.class::DEFAULT_ADDITIONAL_KEYS_TO_ADD.dup : []
        end

        def json
          field_name = field
          inner_json = field_options.fetch(field_name, {}).dup
          result = inner_json.delete("match_type")
          inner_json.delete("type") if result.nil? || result == false

          current_method = query_method
          data = if ["query_string", "multi_match"].include?(current_method)
                   { current_method => inner_json }
                 else
                   { current_method => { field_name => inner_json } }
                 end

          (BASE_KEYS_TO_ADD + @additional_keys_to_add).each do |key|
            value = public_send(key)
            next if value.nil?

            if key == "q"
              if current_method.include?("match")
                inner_json["query"] = value
                inner_json["zero_terms_query"] = zero_terms_query if current_method == "match"
              elsif current_method == "query_string"
                inner_json["query"] = value
                inner_json["default_field"] = field_name
                inner_json["analyze_wildcard"] = inner_json.fetch("analyze_wildcard", true)
                inner_json["allow_leading_wildcard"] = inner_json.fetch("allow_leading_wildcard", true)
              else
                inner_json["value"] = value
              end
            else
              inner_json[key] = value
            end
          end

          data
        end

        def field
          @fields.join(".")
        end

        def fuzziness
          @fuzzy
        end

        def fuzziness=(value)
          @method_name = "fuzzy"
          @fuzzy = value
        end

        def _name
          @_name
        end

        def query_method
          if !analyzed? && value_has_wildcard_char?
            "wildcard"
          elsif analyzed?
            if value_has_wildcard_char?
              "query_string"
            elsif @method_name.start_with?("match")
              options = field_options.fetch(field, {})
              options.fetch("match_type", options.fetch("type", @method_name))
            else
              @method_name
            end
          else
            @method_name
          end
        end

        private

        def add_additional_key(key)
          @additional_keys_to_add << key unless @additional_keys_to_add.include?(key)
        end

        def value_has_wildcard_char?
          value = respond_to?(:q) ? q : ""
          Luqum::Tree::Term.new(value).has_wildcard?
        end

        def analyzed?
          !@no_analyze.include?(field)
        end
      end

      class EWord < AbstractEItem
        DEFAULT_ADDITIONAL_KEYS_TO_ADD = ["q"].freeze

        attr_accessor :q

        def initialize(q, *args, **kwargs)
          super(*args, **kwargs)
          @q = q
        end

        def json
          if q == "*"
            result = { "exists" => { "field" => field } }
            result["exists"]["_name"] = _name unless _name.nil?
            return result
          end
          super
        end
      end

      class EPhrase < AbstractEItem
        DEFAULT_ADDITIONAL_KEYS_TO_ADD = ["q"].freeze

        attr_accessor :q, :slop

        def initialize(phrase, *args, **kwargs)
          super(*args, method: "match_phrase", **kwargs)
          normalized = phrase.gsub(/\s+/, " ")
          @q = normalized[1...-1]
        end

        def value_has_wildcard_char?
          false
        end

        def slop=(value)
          @slop = value
          add_additional_key("slop")
        end
      end

      class ERange < AbstractEItem
        attr_accessor :lt, :lte, :gt, :gte

        def initialize(*args, lt: nil, lte: nil, gt: nil, gte: nil, **kwargs)
          super(*args, method: "range", **kwargs)
          unless lt.nil? || lt == "*"
            @lt = lt
            add_additional_key("lt")
          end
          unless lte.nil? || lte == "*"
            @lte = lte
            add_additional_key("lte")
          end
          unless gt.nil? || gt == "*"
            @gt = gt
            add_additional_key("gt")
          end
          unless gte.nil? || gte == "*"
            @gte = gte
            add_additional_key("gte")
          end
        end
      end

      class AbstractEOperation
        include JsonSerializableMixin

        attr_accessor :zero_terms_query
      end

      class EOperation < AbstractEOperation
        attr_accessor :items

        def initialize(items, **options)
          @items = items
          @options = options.transform_keys(&:to_s)
        end

        def json
          bool_query = { operation => items.map(&:json) }
          { "bool" => bool_query.merge(@options) }
        end
      end

      class ENested < AbstractEOperation
        attr_reader :items

        def initialize(nested_path:, nested_fields:, items:, _name: nil, **_kwargs)
          @nested_path = [nested_path]
          @items = exclude_nested_children(items)
          @_name = _name
          nested_fields
        end

        def nested_path
          @nested_path.join(".")
        end

        def json
          data = { "nested" => { "path" => nested_path, "query" => items.json } }
          data["nested"]["_name"] = @_name unless @_name.nil?
          data
        end

        private

        def exclude_nested_children(subtree)
          if subtree.is_a?(ENested)
            subtree.nested_path == nested_path ? exclude_nested_children(subtree.items) : subtree
          elsif subtree.is_a?(AbstractEOperation)
            subtree.items = subtree.items.map { |child| exclude_nested_children(child) }
            subtree
          else
            subtree
          end
        end
      end

      class EShould < EOperation
        def operation
          "should"
        end
      end

      class AbstractEMustOperation < EOperation
        def initialize(items, **options)
          super
          @items.each { |item| item.zero_terms_query = zero_terms_query }
        end
      end

      class EMust < AbstractEMustOperation
        def zero_terms_query
          "all"
        end

        def operation
          "must"
        end
      end

      class EMustNot < AbstractEMustOperation
        def zero_terms_query
          "none"
        end

        def operation
          "must_not"
        end
      end

      class EBoolOperation < EOperation
        def json
          must_items = []
          should_items = []
          must_not_items = []

          items.each do |item|
            if item.is_a?(EMust)
              must_items.concat(item.items)
            elsif item.is_a?(EMustNot)
              must_not_items.concat(item.items)
            else
              should_items << item
            end
          end

          bool_query = {}
          bool_query["must"] = must_items.map(&:json) unless must_items.empty?
          bool_query["should"] = should_items.map(&:json) unless should_items.empty?
          bool_query["must_not"] = must_not_items.map(&:json) unless must_not_items.empty?
          { "bool" => bool_query.merge(@options) }
        end
      end

      class ElasticSearchItemFactory
        def initialize(no_analyze, nested_fields, field_options)
          @no_analyze = no_analyze
          @nested_fields = nested_fields
          @field_options = field_options
        end

        def build(cls, *args, **kwargs)
          if cls <= AbstractEItem
            kwargs = kwargs.key?(:field_options) ? kwargs : kwargs.merge(field_options: @field_options)
            cls.new(*args, no_analyze: @no_analyze, **kwargs)
          elsif cls <= ENested
            cls.new(*args, nested_fields: @nested_fields, **kwargs)
          else
            cls.new(*args, **kwargs)
          end
        end
      end
    end
  end
end
