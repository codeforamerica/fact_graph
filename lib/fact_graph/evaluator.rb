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

  def key_matches_key_path?(key, key_path)
    return false unless key_path.is_a?(Array) && key_path.count.positive?

    case key
    when Dry::Schema::KeyMap
      key.keys.any? do |key|
        key_matches_key_path?(key, key_path)
      end
    when Dry::Schema::Key::Array
      match = key.name == key_path[0]
      match &&= key_path[1].is_a?(Integer) if key_path.count > 1
      match &&= key_matches_key_path?(key.member, key_path[2..]) if key_path.count > 2
      match
    when Dry::Schema::Key::Hash
      match = key.name == key_path[0]
      match &&= key_matches_key_path?(key.members, key_path[1..]) if key_path.count > 1
      match
    when Dry::Schema::Key
      key.name == key_path[0] && key_path.count == 1
    else
      false
    end
  end

  def facts_using_input(query_input)
    graph.flat_map do |_, facts|
      facts.select do |_, fact|
        fact.input_schemas.any? do |_, input_schema|
          key_matches_key_path?(input_schema.key_map, query_input)
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

  def self.input_errors(results)
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
