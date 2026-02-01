# frozen_string_literal: true

# Comprehensive validation pipeline for FactGraph code
# Returns structured errors that help LLMs iterate and fix issues
class CodeValidator
  attr_reader :code, :errors, :warnings, :facts_info

  def initialize(code)
    @code = code
    @errors = []
    @warnings = []
    @facts_info = []
  end

  def validate
    return self if code.nil? || code.empty?

    validate_syntax
    return self if errors.any?

    validate_structure
    return self if errors.any?

    validate_dependencies
    validate_input_schemas
    validate_resolvers

    self
  end

  def valid?
    errors.empty?
  end

  def to_h
    {
      valid: valid?,
      errors: errors,
      warnings: warnings,
      facts: facts_info
    }
  end

  def cleanup
    # Restore previous registry
    FactGraph::Graph.graph_registry = @previous_registry if @previous_registry
  end

  private

  def validate_syntax
    RubyVM::InstructionSequence.compile(code)
  rescue SyntaxError => e
    # Extract useful info from syntax error
    message = e.message
    line_match = message.match(/^[^:]+:(\d+):/)
    line_num = line_match ? line_match[1].to_i : nil

    errors << {
      type: "syntax_error",
      message: message.sub(/^[^:]+:\d+:\s*/, ""),
      line: line_num,
      suggestion: "Check for missing 'end' keywords, unclosed strings, or mismatched brackets"
    }
  end

  def validate_structure
    # Save and clear registry
    @previous_registry = FactGraph::Graph.graph_registry.dup
    FactGraph::Graph.graph_registry = []

    begin
      eval(code)

      if FactGraph::Graph.graph_registry.empty?
        errors << {
          type: "no_facts",
          message: "No facts were defined",
          suggestion: "Define at least one fact using 'fact :name do ... end' or 'constant(:name) { value }'"
        }
        return
      end

      # Collect facts info for later validation
      @facts_info = FactGraph::Graph.graph_registry.map do |fact|
        {
          name: fact[:name],
          module: fact[:module_name],
          has_resolver: fact[:def_proc].is_a?(Proc),
          per_entity: fact[:per_entity]
        }
      end
    rescue NameError => e
      errors << {
        type: "name_error",
        message: e.message,
        suggestion: "Check that all referenced classes and constants are defined. Common issue: missing 'require' statements."
      }
    rescue => e
      errors << {
        type: "evaluation_error",
        message: "#{e.class}: #{e.message}",
        suggestion: "Check for runtime errors in constant definitions or class bodies"
      }
    end
  end

  def validate_dependencies
    return if FactGraph::Graph.graph_registry.empty?

    fact_names_by_module = {}
    FactGraph::Graph.graph_registry.each do |fact|
      fact_names_by_module[fact[:module_name]] ||= Set.new
      fact_names_by_module[fact[:module_name]] << fact[:name]
    end

    # Build a temporary graph to check dependencies
    begin
      graph = FactGraph::Graph.prepare_fact_objects({})

      graph.each do |module_name, facts|
        facts.each do |fact_name, fact|
          next unless fact.is_a?(FactGraph::Fact)

          fact.dependencies.each do |dep_name, dep_module|
            unless fact_names_by_module[dep_module]&.include?(dep_name)
              errors << {
                type: "missing_dependency",
                message: "Fact '#{fact_name}' depends on '#{dep_name}' from module '#{dep_module}', but it doesn't exist",
                fact: fact_name,
                module: module_name,
                missing_dependency: dep_name,
                missing_from_module: dep_module,
                suggestion: "Define the '#{dep_name}' fact in a Graph class with module name '#{dep_module}', or fix the dependency reference"
              }
            end
          end
        end
      end
    rescue => e
      errors << {
        type: "dependency_check_error",
        message: "Error while checking dependencies: #{e.message}",
        suggestion: "There may be an issue with fact definitions preventing dependency analysis"
      }
    end
  end

  def validate_input_schemas
    return if FactGraph::Graph.graph_registry.empty?

    begin
      graph = FactGraph::Graph.prepare_fact_objects({})

      graph.each do |module_name, facts|
        facts.each do |fact_name, fact|
          next unless fact.is_a?(FactGraph::Fact)

          fact.input_definitions.each do |input_name, input_def|
            validator = input_def[:validator]

            unless validator.respond_to?(:call)
              errors << {
                type: "invalid_input_schema",
                message: "Input '#{input_name}' in fact '#{fact_name}' has invalid schema",
                fact: fact_name,
                input: input_name,
                suggestion: "Input schema must be a Dry::Schema.Params block that returns a callable schema"
              }
            end

            unless validator.respond_to?(:key_map)
              warnings << {
                type: "missing_key_map",
                message: "Input '#{input_name}' schema may not filter keys properly",
                fact: fact_name,
                input: input_name
              }
            end
          end
        end
      end
    rescue => e
      errors << {
        type: "schema_check_error",
        message: "Error while checking input schemas: #{e.message}",
        suggestion: "Check that all Dry::Schema.Params blocks are valid"
      }
    end
  end

  def validate_resolvers
    return if FactGraph::Graph.graph_registry.empty?

    FactGraph::Graph.graph_registry.each do |fact|
      # Constants don't need complex resolvers
      next if fact[:def_proc].nil?

      # Check if the def_proc returns a resolver
      begin
        # We can't fully validate resolvers without running them,
        # but we can check for common issues
        proc_source = fact[:def_proc].source_location
        if proc_source
          warnings << {
            type: "resolver_info",
            message: "Fact '#{fact[:name]}' resolver defined at #{proc_source.join(':')}",
            fact: fact[:name]
          }
        end
      rescue => e
        # source_location might not be available
      end
    end
  end
end
