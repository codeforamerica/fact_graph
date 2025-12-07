# frozen_string_literal: true

require "active_support/core_ext/string"

require_relative "fact_graph/data_container"
require_relative "fact_graph/evaluator"
require_relative "fact_graph/fact"
require_relative "fact_graph/input"
require_relative "fact_graph/version"

module FactGraph
  class ValidationError < StandardError; end

  class Graph
    @graph_registry = []

    class << self
      attr_accessor :graph_registry

      def module_name = to_s.underscore.split("/").last.to_sym

      def inherited(subclass)
        super
        subclass.graph_registry = []
      end

      def fact(name, **kwargs, &def_proc)
        superclass.graph_registry << {module_name:, name:, def_proc:, **kwargs}
      end
      alias_method :constant, :fact

      def prepare_fact_objects(input, module_filter = nil)
        graph = {}

        graph_registry = self.graph_registry
        if module_filter
          graph_registry = graph_registry.select do |fact_kwargs|
            fact_kwargs in {module_name:}
            module_filter.include? module_name
          end
        end

        graph_registry.map do |fact_kwargs|
          fact_kwargs in {module_name:, name:}
          graph[module_name] ||= {}

          if fact_kwargs.key? :per_entity
            graph[module_name][name] = {}

            # replace this with a different method of getting entity IDs if we e.g. switch to hashes of ID=>entity_hash
            num_entities = input[fact_kwargs[:per_entity]].count
            num_entities.times do |entity_id|
              fact_kwargs[:entity_id] = entity_id
              fact = FactGraph::Fact.new(graph:, **fact_kwargs)
              graph[module_name][name][entity_id] = fact
            end
          else
            fact = FactGraph::Fact.new(graph:, **fact_kwargs)
            graph[module_name][name] = fact
          end
        end

        graph
      end
    end
  end
end
