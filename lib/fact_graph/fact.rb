class FactGraph::Fact
  attr_accessor :name, :module_name, :resolver, :dependencies, :inputs, :graph, :errors

  def initialize(name:, module_name:, graph:, def_proc:)
    @name = name
    @module_name = module_name
    @dependencies = {}
    @inputs = []
    @graph = graph
    @errors = {
      fact_bad_inputs: [],
      fact_dependency_unmet: Hash.new { |h, key| h[key] = [] }
    }

    @resolver = instance_eval(&def_proc)
  end

  def dependency(fact, from: nil)
    if from.nil?
      from = module_name
    end

    dependencies[fact] = from
  end

  def dependency_facts
    dependencies.reduce({}) do |result_hash, values|
      fact_name, module_name = values
      fact = graph[module_name][fact_name]
      raise "#{name}: could not find dependency #{fact_name} in module #{module_name}" if fact.nil?
      result_hash[fact_name] = fact
      result_hash
    end
  end

  def input(name, &schema)
    inputs << { name:, schema: }
  end

  def validate_input(input)
    inputs.each do |input_definition|
      # XXX: Is this a problem? Having multiple subclasses? Should we cache?
      defined_input = Class.new(FactGraph::Input).class_exec(&input_definition[:schema])
      result = defined_input.call("#{input_definition[:name]}": input[input_definition[:name]])
      if result.success?
        result.to_h
      else
        errors[:fact_bad_inputs] << result.errors.to_h
      end
    end
  end

  def call(input, results)
    return resolver unless resolver.respond_to?(:call)
    return results[module_name][name] if results.has_key?(module_name) && results[module_name].has_key?(name)

    data = FactGraph::DataContainer.new(
      {
        # TODO: Should dependencies be in module hashes to allow fact name collisions across modules?
        dependencies: dependency_facts.transform_values { |d| d.call(input, results) },
        input: input.select { |key, value|
          # TODO: Figure out a way to make this lookup constant time
          inputs.any? { |input_definition| input_definition[:name] == key }
        }
      }
    )

    validate_input(data.data[:input])

    data.data[:dependencies].each do |key, dependency|
      case dependency
      in { fact_dependency_unmet: Hash } | { fact_bad_inputs: Array }
        bad_module = dependency_facts[key].module_name
        errors[:fact_dependency_unmet][bad_module] << key
      else
      end
    end

    results[module_name] ||= {}

    if errors[:fact_dependency_unmet].values.any? || errors[:fact_bad_inputs].any?
      results[module_name][name] = errors
      return results[module_name][name]
    end

    begin
      results[module_name][name] = data.instance_exec(&resolver)
      return results[module_name][name]
    end
  end
end
