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
    graph.values.flat_map do |facts|
      facts.select do |fact_name, fact|
        fact.inputs.any? do |fact_input|
          fact_input.name == query_input[:name] && fact_input.attribute_name == query_input[:attribute_name]
        end
      end.values
    end
  end

  def facts_with_dependency(query_module_name, query_fact_name)
    graph.values.flat_map do |facts|
      facts.values.select do |fact|
        fact.dependencies[query_fact_name] == query_module_name
      end
    end
  end

  # consider marking facts used for output explicitly, rather than assuming (incorrectly) that leaf nodes = output
  def leaf_facts_depending_on_input(query_input)
    candidate_facts = facts_using_input(query_input)
    leaf_facts = Set.new
    while candidate_facts.count > 0
      candidate_fact = candidate_facts.shift
      facts_depending_on_candidate = facts_with_dependency(candidate_fact.module_name, candidate_fact.name)
      if facts_depending_on_candidate.count == 0
        leaf_facts << candidate_fact
      else
        candidate_facts.concat(facts_depending_on_candidate)
      end
    end
    leaf_facts
  end

  def self.bad_inputs(results)
    bad_inputs_to_facts = {}
    results.each do |graph_module, facts|
      facts.each do |fact_name, result|
        if result in { fact_bad_inputs:, fact_dependency_unmet: }
          fact_bad_inputs.each do |bad_input|
            bad_inputs_to_facts[bad_input] ||= []
            bad_inputs_to_facts[bad_input] << fact_name
          end
        end
      end
    end
    bad_inputs_to_facts
  end
end