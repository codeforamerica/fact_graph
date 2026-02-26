# frozen_string_literal: true

require "active_support/core_ext/string"

require_relative "fact_graph/data_container"
require_relative "fact_graph/evaluator"
require_relative "fact_graph/fact"
require_relative "fact_graph/version"

module FactGraph
  class ValidationError < StandardError; end

  class Graph
    @graph_registry = []

    class << self
      attr_accessor :graph_registry

      def module_name = @module_name || to_s.underscore.split("/").last.to_sym

      def inherited(subclass)
        super
        subclass.graph_registry = []
      end

      def in_module(module_name, &blk)
        previous_module = @module_name
        @module_name = module_name
        yield
        @module_name = previous_module
      end

      def fact(name, **kwargs, &def_proc)
        superclass.graph_registry << {module_name:, name:, def_proc:, **kwargs}
      end
      alias_method :constant, :fact

      def entity_ids(input, entity_name)
        # replace this with a different method of getting entity IDs if we e.g. switch to hashes of ID=>entity_hash
        if input.key? entity_name
          (0...input[entity_name].count).to_a
        else
          []
        end
      end

      def filter_graph(module_filter)
        if module_filter
          self.graph_registry.select do |fact_kwargs|
            module_filter.include? fact_kwargs[:module_name]
          end
        else
          self.graph_registry
        end
      end

      def fact_definitions(module_filter = nil)
        graph = {}
        filter_graph(module_filter).each do |fact_kwargs|
          fact_kwargs in {module_name:, name:}
          graph[module_name] ||= {}
          fact = FactGraph::Fact.new(graph:, **fact_kwargs)
          graph[module_name][name] = fact
        end
        graph
      end

      def prepare_fact_objects(input, module_filter = nil)
        graph = {}
        filter_graph(module_filter).map do |fact_kwargs|
          fact_kwargs in {module_name:, name:}
          graph[module_name] ||= {}

          if fact_kwargs.key? :per_entity
            graph[module_name][name] = {}
            entity_ids(input, fact_kwargs[:per_entity]).each do |entity_id|
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

      def entity_map(input, module_filter = nil)
        entity_map = {}
        filter_graph(module_filter).each do |fact_kwargs|
          if fact_kwargs.key? :per_entity
            entity_name = fact_kwargs[:per_entity]
            entity_map[entity_name] = entity_ids(input, entity_name)
          end
        end
        entity_map
      end
    end
  end
end
