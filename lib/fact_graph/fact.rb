require "dry/schema"
require "dry/monads"
Dry::Schema.load_extensions(:monads)

class FactGraph::Fact
  include Dry::Monads[:result, :validated, :list, :do]
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
      dependency_fact_name, dependency_module_name = values
      dependency_module = graph[dependency_module_name]
      raise "#{name}: while trying to evaluate dependency #{dependency_fact_name}, could not find module #{dependency_module_name}" if dependency_module.nil?
      dependency_fact = dependency_module[dependency_fact_name]
      raise "#{name}: could not find dependency #{dependency_fact_name} in module #{dependency_module_name}" if dependency_fact.nil?

      if dependency_fact.is_a? FactGraph::Fact
        result_hash[dependency_fact_name] = dependency_fact
      elsif dependency_fact.is_a? Hash
        result_hash[dependency_fact_name] = if per_entity
          # Take only the fact corresponding to our entity ID as the dependency
          dependency_fact[entity_id]
        else
          # Take the whole hash of {entity IDs => facts} as the dependency
          dependency_fact
        end
      end
    end
  end

  def input(name, **kwargs, &schema_blk)
    input_definitions[name] = kwargs.merge({validator: schema_blk.call})
  end

  def filter_input(input)
    # Filter out unused inputs
    required_inputs = input.select { |input_name, _| input_definitions.key? input_name }

    # Pull inputs expected from individual entities
    # TODO: We should enforce at initialization that both per_entity & entity_id are present if there are inputs with the per_entity key
    if per_entity && entity_id
      inputs_from_entities = input_definitions.select do |_input_name, input_definition|
        input_definition[:per_entity] == true
      end
      inputs_from_entities.each do |input_name, input_definition|
        required_inputs[input_name] = input[per_entity][entity_id][input_name]
      end
    end

    # Filter structured input down to only include keys that we expect using KeyMap#write
    required_inputs.to_h do |input_name, _|
      validator = input_definitions[input_name][:validator]
      # We expect to have at most one schema for any key in the input hash, so we don't try to merge filtered values
      [input_name, validator.key_map.write(required_inputs)[input_name]]
    end
  end

  def validate_input(input)
    input_validation_resultss = input_definitions.map do |input_name, input_definition|
      input_validator = input_definition[:validator]
      input_validator.call("#{input_name}": input[input_name]).to_monad
    end
  end

  def evaluate_dependencies(input, results)
    dependency_facts.transform_values do |dependency|
      if dependency.is_a? FactGraph::Fact
        dependency.call(input, results)
      elsif dependency.is_a? Hash
        dependency
          .transform_values { |fact| fact.call(input, results) }
          .filter { |_entity_id, result| result.success? }
      end
    end
  end

  def call(input, results)
    if per_entity
      return results.dig(module_name, name, entity_id) if results.dig(module_name, name, entity_id)
    elsif results.dig(module_name, name)
      return results.dig(module_name, name)
    end

    results[module_name] ||= {}

    if !resolver.respond_to?(:call)
      results[module_name][name] = resolver
      return resolver
    end

    filtered_input = filter_input(input)
    input_validation_results = validate_input(filtered_input)
    dependency_evaluation_result = evaluate_dependencies(input, results)

    errors = {
      fact_bad_inputs: {},
      fact_dependency_unmet: Hash.new { |h, key| h[key] = [] }
    }

    dependency_evaluation_result.each do |dependency_name, dependency_result|
      if dependency_result.failure?
        bad_module = dependency_facts[dependency_name].module_name
        errors[:fact_dependency_unmet][bad_module] << dependency_name
      end
    end

    input_validation_failures = input_validation_results.select(&:failure?)
    input_validation_failures.each do |input_result|
      input_result.failure.errors.each do |error|
        errors[:fact_bad_inputs][error.path] ||= Set.new
        errors[:fact_bad_inputs][error.path].add(error.text)
      end
    end

    if errors[:fact_dependency_unmet].any? || errors[:fact_bad_inputs].any?
      data_errors = Dry::Monads::Failure(errors)
    end

    resolved_errors = nil

    data = FactGraph::DataContainer.new(
      FactGraph::ResultHash.deep_cast({
        # TODO: Should dependencies be in module hashes to allow fact name collisions across modules?
        dependencies: dependency_evaluation_result,
        input: filtered_input
      })
    )

    if allow_unmet_dependencies
      data.data_errors = data_errors
    else
      resolved_errors = data_errors
    end

    puts "===="
    puts "FACT NAME: #{name}"
    puts "RESULTS SO FAR: #{results}"
    puts "DATA: #{data.data}"

    fact_value = data.instance_exec(&resolver)
    fact_result = fact_value.is_a?(Dry::Monads::Result) ? fact_value : Dry::Monads::Success(fact_value)

    if per_entity
      results[module_name][name] ||= {}
      results[module_name][name][entity_id] = resolved_errors || fact_result
    else
      results[module_name][name] = resolved_errors || fact_result
    end
  end
end
