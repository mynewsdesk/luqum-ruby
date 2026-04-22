# frozen_string_literal: true
module Luqum
  module Elasticsearch
    class SchemaAnalyzer
      def initialize(schema)
        @settings = schema.fetch("settings", {})
        mappings = schema.fetch("mappings", {})
        @mappings = if mappings.key?("properties")
                      { "_doc" => mappings }
                    else
                      mappings
                    end
      end

      def default_field
        @settings.fetch("query", {}).fetch("default_field", "*")
      end

      def not_analyzed_fields
        iter_fields(subfields: true).filter_map do |fname, fdef, parents|
          not_analyzed =
            (fdef["type"] == "string" && fdef.fetch("index", "") == "not_analyzed") ||
            !%w[text string nested object].include?(fdef["type"])

          dot_name(fname, parents) if not_analyzed
        end
      end

      def nested_fields
        result = {}
        iter_fields.each do |fname, _fdef, parents|
          parent_def = parents.empty? ? {} : parents[-1][1]
          next unless parent_def["type"] == "nested"

          target = result
          cumulated = []
          parents.each do |name, _definition|
            cumulated << name
            key = cumulated.join(".")
            if target.key?(key)
              target = target[key]
              cumulated = []
            end
          end
          unless cumulated.empty?
            key = cumulated.join(".")
            target[key] ||= {}
            target = target[key]
          end
          target[fname] = {}
        end
        result
      end

      def object_fields
        iter_fields.filter_map do |fname, fdef, parents|
          parent_def = parents.empty? ? {} : parents[-1][1]
          dot_name(fname, parents) if parent_def["type"] == "object" && !%w[object nested].include?(fdef["type"])
        end
      end

      def sub_fields
        iter_fields.filter_map do |fname, fdef, parents|
          next unless fdef.key?("fields")

          subfield_parents = parents + [[fname, fdef]]
          fdef["fields"].keys.map { |subname| dot_name(subname, subfield_parents) }
        end.flatten
      end

      def query_builder_options
        {
          "default_field" => default_field,
          "not_analyzed_fields" => not_analyzed_fields,
          "nested_fields" => nested_fields,
          "object_fields" => object_fields,
        }
      end

      private

      def dot_name(fname, parents)
        (parents.map(&:first) + [fname]).join(".")
      end

      def walk_properties(properties, parents = [], subfields: false, &)
        properties.each do |fname, fdef|
          yield fname, fdef, parents

          if subfields && fdef.key?("fields")
            subfield_parents = parents + [[fname, fdef]]
            subdef = fdef.dup
            subfield_defs = subdef.delete("fields")
            subfield_defs.each do |subname, subfdef|
              yield subname, subdef.merge(subfdef), subfield_parents
            end
          end

          inner_properties = fdef.fetch("properties", {})
          next if inner_properties.empty?

          walk_properties(inner_properties, parents + [[fname, fdef]], subfields: subfields, &)
        end
      end

      def iter_fields(subfields: false)
        fields = []
        @mappings.each_value do |mapping|
          walk_properties(mapping.fetch("properties", {}), subfields: subfields) do |fname, fdef, parents|
            fields << [fname, fdef, parents]
          end
        end
        fields
      end
    end
  end
end
