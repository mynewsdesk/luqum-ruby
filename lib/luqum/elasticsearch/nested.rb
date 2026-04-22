# frozen_string_literal: true
module Luqum
  module Elasticsearch
    module Nested
      class << self
        def get_first_name(query)
          children = if query.is_a?(Hash)
                       return query["_name"] if query.key?("_name")
                       return nil if query.key?("bool")

                       query.values
                     elsif query.is_a?(Array)
                       query
                     else
                       return nil
                     end

          candidates = children.map { |child| get_first_name(child) }.compact
          candidates.first
        end

        def extract_nested_queries(query, query_nester = nil)
          queries = []
          in_nested = !query_nester.nil?
          sub_query_nester = query_nester

          children = if query.is_a?(Hash)
                       if query.key?("nested")
                         params = query["nested"].except('query', 'name')
                         sub_query_nester = lambda do |req, name|
                           nested = { "nested" => params.merge("query" => req) }
                           nested = query_nester.call(nested, name) unless query_nester.nil?
                           nested["nested"]["_name"] = name unless name.nil?
                           nested
                         end
                       end

                       bool_param = %w[must should must_not] & query.keys
                       if !bool_param.empty? && in_nested
                         op = bool_param.first
                         sub_queries = query[op].is_a?(Array) ? query[op] : [query[op]]
                         queries.concat(sub_queries.map { |sub_query| query_nester.call(sub_query, get_first_name(sub_query)) })
                         sub_queries
                       else
                         query.values
                       end
                     elsif query.is_a?(Array)
                       query
                     else
                       []
                     end

          children.each do |child_query|
            queries.concat(extract_nested_queries(child_query, sub_query_nester))
          end

          queries
        end
      end
    end
  end
end
