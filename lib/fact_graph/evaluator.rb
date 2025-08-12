require "active_support/core_ext/string"

class FactGraph::Evaluator
  attr_accessor :graph

  def initialize(module_filter = nil)
    self.graph = FactGraph::Graph.prepare_fact_objects(module_filter)
  end

  def evaluate(input)
    results = {}
    graph.transform_values do |fact_hash|
      # Iterate module hash returning fact hash of all facts in module
      fact_hash.transform_values do |f|
        # Convert Fact instances to their resolved values
        f.call(input, results)
      end
    end
    results
  end

  def facts_using_input(query_input)
    graph.flat_map do |_, facts|
      facts.select do |_, fact|
        fact.input_schemas.any? do |_, input_schema|
          # This uses a private API of Dry::Schema::KeyMap (#to_dot_notation)
          # Alternatively, it could be implemented with our own recursive traversal
          input_schema.key_map.to_dot_notation.any? do |key_dot_notation|
            # HACK: We use #starts_with? here to support querying for part of the key path, but it allows for bugs if
            #       one input's name is actually a substring of another's
            key_dot_notation.starts_with?(query_input)
          end
        end
      end.values
    end
  end

  def facts_with_dependency(query_module_name, query_fact_name)
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

  def self.bad_inputs(results)
    errors = {}
    results.each_value do |facts|
      facts.each_value do |result|
        next unless result in { fact_bad_inputs:, fact_dependency_unmet: }

        fact_bad_inputs.each do |bad_input|
          # each bad input has a hash of keys:[errors], but there should only be one key by convention
          bad_input.each do |input_name, input_errors|
            case errors[input_name]
            when Array
              errors[input_name].concat(input_errors)
            when Hash
              errors[input_name].merge(input_errors)
            else
              errors[input_name] = input_errors
            end
          end
        end
      end
    end
    errors
  end
end
