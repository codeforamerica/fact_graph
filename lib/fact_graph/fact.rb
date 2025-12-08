class FactGraph::Fact
  attr_accessor :name, :module_name, :resolver, :dependencies, :input_definitions, :graph, :per_entity, :entity_id, :allow_unmet_dependencies

  def initialize(name:, module_name:, graph:, def_proc:, per_entity: nil, entity_id: nil, allow_unmet_dependencies: false)
    @name = name
    @module_name = module_name
    @dependencies = {}
    @input_definitions = {}
    @graph = graph
    @per_entity = per_entity
    @entity_id = entity_id
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

      if fact.is_a? FactGraph::Fact
        result_hash[fact_name] = fact
      elsif fact.is_a? Hash
        result_hash[fact_name] = fact[entity_id]
      end
    end
  end

  def input(name, **kwargs, &schema)
    # XXX: Is this a problem? Having multiple subclasses? Should we cache?
    input_definitions[name] = kwargs.merge({ validator: Class.new(FactGraph::Input).class_exec(&schema) })
  end

  def filter_input(input)
    # Filter out unused inputs
    required_inputs = input.select { |input_name, _| input_definitions.key?(input_name) }

    # Pull inputs expected from individual entities
    # TODO: We should enforce at initialization that both per_entity & entity_id are present if there are inputs with the per_entity key
    if per_entity && entity_id
      inputs_from_entities = input_definitions.select do |_input_name, input_definition|
        input_definition.key? :from_entity
      end
      inputs_from_entities.each do |input_name, input_definition|
        entity_name = input_definition[:from_entity] # TODO: Again with unenforced constraints - this should only ever be the same as our per_entity attribute
        required_inputs[input_name] = input[entity_name][entity_id][input_name]
      end
    end

    # Filter structured input down to only include keys that we expect using KeyMap#write
    required_inputs.to_h do |input_name, _|
      validator = input_definitions[input_name][:validator]
      # We expect to have at most one schema for any key in the input hash, so we don't try to merge filtered values
      [input_name, validator.key_map.write(required_inputs)[input_name]]
    end
  end

  def validate_input(input, errors)
    input_definitions.each do |input_name, input_definition|
      input_validator = input_definition[:validator]
      result = input_validator.call("#{input_name}": input[input_name])
      if result.failure?
        result.errors.each do |error|
          errors[:fact_bad_inputs][error.path] ||= Set.new
          errors[:fact_bad_inputs][error.path].add(error.text)
        end
      end
    end
  end

  def call(input, results)
    if per_entity
      return results.dig(module_name, name, entity_id) if results.dig(module_name, name, entity_id)
    else
      return results.dig(module_name, name) if results.dig(module_name, name)
    end

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
      if dependency in { fact_dependency_unmet: Hash } | { fact_bad_inputs: Array }
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

    if per_entity
      results[module_name][name] ||= {}
      results[module_name][name][entity_id] = resolved_errors || data.instance_exec(&resolver)
    else
      results[module_name][name] = resolved_errors || data.instance_exec(&resolver)
    end
  end
end
