require "active_support/core_ext/string"
require "method_source"

class FactGraph::Evaluator
  class << self
    def call_fact(fact, input, results)
      # Convert Fact instances to their resolved values
      if fact.is_a? FactGraph::Fact
        fact.call(input, results)
      elsif fact.is_a? Hash
        fact.each do |_entity_id, per_entity_fact|
          per_entity_fact.call(input, results)
        end
      end
    end

    def evaluate(input, graph_class: nil,  module_filter: nil)
      graph_class ||= FactGraph::Graph
      graph = graph_class.prepare_fact_objects(input, module_filter)
      results = graph.transform_values { |_| {} }
      graph.each do |module_name, module_hash|
        module_hash.values.each do |fact|
          call_fact(fact, input, results)
        end
      end
      results
    end

    def fact_metadata(fact, result)
      metadata = {
        module: fact.module_name,
        fact: fact.name,
        value: result,
        code: fact.resolver.respond_to?(:call) ? fact.resolver.source : fact.resolver,
        dependencies: fact.dependency_facts.map do |dep_fact_name, dep_fact|
          dep_info = {
            module: dep_fact.module_name,
            fact: dep_fact.name,
          }
          dep_info[:entity_id] = dep_fact.entity_id if dep_fact.entity_id
          dep_info
        end,
        inputs: fact.input_definitions.keys
      }
      metadata[:entity_id] = fact.entity_id if fact.entity_id
      metadata
    end

    # Placeholder until we move values/errors back onto Fact objects
    def evaluate_with_metadata(input, graph_class: nil, module_filter: nil)
      graph_class ||= FactGraph::Graph
      graph = graph_class.prepare_fact_objects(input, module_filter)

      results = graph.transform_values { |_| {} }
      metadata = graph.transform_values { |_| {} }
      graph.each do |module_name, module_hash|
        module_hash.each do |fact_name, fact|
          call_fact(fact, input, results)

          if fact.is_a? FactGraph::Fact
            result = results[module_name][fact_name]
            metadata[module_name][fact_name] = fact_metadata(fact, result)
          elsif fact.is_a? Hash
            fact.each do |entity_id, per_entity_fact|
              result = results[module_name][fact_name][entity_id]
              metadata[module_name][fact_name][entity_id] = fact_metadata(fact, result)
            end
          end
        end
      end
      metadata
    end

    def key_matches_key_path?(key, key_path)
      return false unless key_path.is_a?(Array) && key_path.count.positive?

      case key
      when Dry::Schema::KeyMap
        key.keys.any? do |key|
          key_matches_key_path?(key, key_path)
        end
      when Dry::Schema::Key::Array
        match = key.name == key_path[0].to_s
        match &&= key_path[1].is_a?(Integer) if key_path.count > 1
        match &&= key_matches_key_path?(key.member, key_path[2..]) if key_path.count > 2
        match
      when Dry::Schema::Key::Hash
        match = key.name == key_path[0].to_s
        match &&= key_matches_key_path?(key.members, key_path[1..]) if key_path.count > 1
        match
      when Dry::Schema::Key
        key.name == key_path[0].to_s && key_path.count == 1
      else
        false
      end
    end

    def facts_using_input(query_input, graph_class: nil,  module_filter: nil)
      graph_class ||= FactGraph::Graph
      graph = graph_class.prepare_fact_objects(module_filter)
      graph.flat_map do |_, facts|
        facts.select do |_, fact|
          fact.input_definitions.any? do |_, input_definition|
            validator = input_definition[:validator]
            key_matches_key_path?(validator.key_map, query_input)
          end
        end.values
      end
    end

    def facts_with_dependency(query_module_name, query_fact_name, graph_class: nil,  module_filter: nil)
      graph_class ||= FactGraph::Graph
      graph = graph_class.prepare_fact_objects(module_filter)
      graph.flat_map do |_, facts|
        facts.select do |_, fact|
          fact.dependencies[query_fact_name] == query_module_name
        end.values
      end
    end

    # consider marking facts used for output explicitly, rather than assuming (incorrectly) that leaf nodes = output
    def leaf_facts_depending_on_input(query_input)
      candidate_facts = facts_using_input(query_input)
      leaf_facts = Set.new
      while candidate_facts.count.positive?
        candidate_fact = candidate_facts.shift
        facts_depending_on_candidate = facts_with_dependency(candidate_fact.module_name, candidate_fact.name)
        if facts_depending_on_candidate.count.zero?
          leaf_facts << candidate_fact
        else
          candidate_facts.concat(facts_depending_on_candidate)
        end
      end
      leaf_facts.to_a
    end

    def input_errors(results)
      errors = {}
      results.each_value do |facts|
        facts.each_value do |result|
          next unless result in { fact_bad_inputs: }

          errors.merge!(fact_bad_inputs) do |_bad_input_key_path, old_error_messages, new_error_messages|
            old_error_messages.merge(new_error_messages)
          end
        end
      end
      errors
    end
  end
end
