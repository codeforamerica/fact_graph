class FactGraph::Fact
  attr_accessor :name, :module_name, :resolver, :dependencies, :input_schemas, :graph, :errors

  def initialize(name:, module_name:, graph:, def_proc:)
    @name = name
    @module_name = module_name
    @dependencies = {}
    @input_schemas = {}
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
    input_schemas[name] = Class.new(FactGraph::Input).class_exec(&schema)
  end

  def validate_input(input)
    input_schemas.each do |input_name, input_schema|
      # XXX: Is this a problem? Having multiple subclasses? Should we cache?
      result = input_schema.call("#{input_name}": input[input_name])
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
        # TODO: Should we filter structured inputs by schema keypaths here to make sure that they don't receive more
        #       than they need in structured inputs? Could use Dry::Schema::KeyMap#write to filter out unexpected keys
        input: input.select { |input_name, _| input_schemas.key? input_name }
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
