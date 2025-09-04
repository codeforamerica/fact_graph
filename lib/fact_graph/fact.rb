class FactGraph::Fact
  attr_accessor :name, :module_name, :resolver, :dependencies, :input_schemas, :graph, :allow_unmet_dependencies

  def initialize(name:, module_name:, graph:, def_proc:, allow_unmet_dependencies: false)
    @name = name
    @module_name = module_name
    @dependencies = {}
    @input_schemas = {}
    @graph = graph
    @allow_unmet_dependencies = allow_unmet_dependencies

    @resolver = instance_eval(&def_proc)
  end

  def dependency(fact, from: nil)
    if from.nil?
      from = module_name
    end

    dependencies[fact] = from
  end

  def dependency_facts
    dependencies.each_with_object({}) do |values, result_hash|
      fact_name, module_name = values
      fact = graph[module_name][fact_name]
      raise "#{name}: could not find dependency #{fact_name} in module #{module_name}" if fact.nil?
      result_hash[fact_name] = fact
    end
  end

  def input(name, &schema)
    # XXX: Is this a problem? Having multiple subclasses? Should we cache?
    input_schemas[name] = Class.new(FactGraph::Input).class_exec(&schema)
  end

  def filter_input(input)
    # Filter out unused inputs
    required_inputs = input.select { |input_name, _| input_schemas.key? input_name }

    # Filter structured input down to only include keys that we require
    required_inputs.to_h do |input_name, _|
      # We expect to have at most one schema for any key in the input hash, so we don't try to merge filtered values
      [input_name, input_schemas[input_name].key_map.write(input)[input_name]]
    end
  end

  def validate_input(input, errors)
    input_schemas.each do |input_name, input_schema|
      result = input_schema.call("#{input_name}": input[input_name])
      if result.failure?
        result.errors.each do |error|
          errors[:fact_bad_inputs][error.path] ||= Set.new
          errors[:fact_bad_inputs][error.path].add(error.text)
        end
      end
    end
  end

  def call(input, results)
    return results[module_name][name] if results.key?(module_name) && results[module_name].key?(name)

    if !resolver.respond_to?(:call)
      results[module_name] ||= {}
      results[module_name][name] = resolver
      return resolver
    end

    data = FactGraph::DataContainer.new(
      {
        # TODO: Should dependencies be in module hashes to allow fact name collisions across modules?
        dependencies: dependency_facts.transform_values { |d| d.call(input, results) },
        input: filter_input(input)
      }
    )

    errors = {
      fact_bad_inputs: {},
      fact_dependency_unmet: Hash.new { |h, key| h[key] = [] }
    }

    validate_input(data.data[:input], errors)

    data.data[:dependencies].each do |key, dependency|
      if dependency in {fact_dependency_unmet: Hash} | {fact_bad_inputs: Array}
        bad_module = dependency_facts[key].module_name
        errors[:fact_dependency_unmet][bad_module] << key
      end
    end

    results[module_name] ||= {}

    if errors[:fact_dependency_unmet].any? || errors[:fact_bad_inputs].any?
      data_errors = errors
    end

    resolved_errors = nil

    if allow_unmet_dependencies
      data.data_errors = data_errors
    else
      resolved_errors = data_errors
    end

    results[module_name][name] = resolved_errors || data.instance_exec(&resolver)
    results[module_name][name]
  end
end
