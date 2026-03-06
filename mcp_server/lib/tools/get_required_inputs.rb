# frozen_string_literal: true

class GetRequiredInputs < MCP::Tool
  description "Get the required inputs for evaluating specific modules. " \
              "Traces dependencies across modules and returns all input schemas needed. " \
              "Useful for determining which form fields are needed for a specific program."

  input_schema(
    type: "object",
    properties: {
      module_filter: {
        type: "array",
        items: { type: "string" },
        description: "List of module names to get inputs for (e.g., ['snap']). If not provided, returns all inputs."
      }
    }
  )

  class << self
    def call(module_filter: nil, server_context:)
      graph_state = server_context[:graph_state]

      if graph_state.facts.empty?
        return error_response("No facts defined. Use add_fact first.")
      end

      # Build dependency graph
      all_facts = graph_state.facts
      facts_by_key = build_facts_index(all_facts)

      # Determine which modules to analyze
      target_modules = if module_filter && !module_filter.empty?
        module_filter.map(&:to_s)
      else
        graph_state.modules.map(&:to_s)
      end

      # Find all facts needed (including dependencies)
      needed_facts = find_all_needed_facts(target_modules, all_facts, facts_by_key)

      # Extract inputs from needed facts
      inputs_by_module = extract_inputs(needed_facts)

      # Build response
      result = {
        target_modules: target_modules,
        required_inputs: inputs_by_module,
        input_summary: build_input_summary(inputs_by_module),
        sample_input: build_sample_input(inputs_by_module)
      }

      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate(result)
      }])
    end

    private

    def error_response(message)
      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate({ error: message })
      }])
    end

    def build_facts_index(facts)
      facts.each_with_object({}) do |fact, index|
        key = "#{fact[:module_name]}:#{fact[:name]}"
        index[key] = fact
      end
    end

    def find_all_needed_facts(target_modules, all_facts, facts_by_key)
      needed = Set.new
      to_process = []

      # Start with all facts in target modules
      all_facts.each do |fact|
        if target_modules.include?(fact[:module_name].to_s)
          key = "#{fact[:module_name]}:#{fact[:name]}"
          to_process << key
        end
      end

      # Recursively find dependencies
      while to_process.any?
        key = to_process.shift
        next if needed.include?(key)

        needed.add(key)
        fact = facts_by_key[key]
        next unless fact

        # Add dependencies
        (fact[:dependencies] || []).each do |dep|
          dep_module = dep[:from]&.to_s || fact[:module_name].to_s
          dep_key = "#{dep_module}:#{dep[:name]}"
          to_process << dep_key unless needed.include?(dep_key)
        end
      end

      # Return the actual fact objects
      needed.map { |key| facts_by_key[key] }.compact
    end

    def extract_inputs(facts)
      inputs_by_module = {}

      facts.each do |fact|
        next unless fact[:inputs] && fact[:inputs].any?

        module_name = fact[:module_name].to_s
        inputs_by_module[module_name] ||= []

        fact[:inputs].each do |input|
          input_info = {
            name: input[:name],
            fact: fact[:name],
            schema: input[:schema],
            per_entity: input[:per_entity] || false,
            required: input[:schema]&.include?("required(")
          }
          inputs_by_module[module_name] << input_info
        end
      end

      # Deduplicate inputs by name within each module
      inputs_by_module.transform_values do |inputs|
        inputs.uniq { |i| i[:name] }
      end
    end

    def build_input_summary(inputs_by_module)
      summary = []
      inputs_by_module.each do |module_name, inputs|
        inputs.each do |input|
          summary << {
            field: input[:name],
            module: module_name,
            required: input[:required],
            per_entity: input[:per_entity]
          }
        end
      end
      summary.sort_by { |s| [s[:required] ? 0 : 1, s[:module], s[:field]] }
    end

    def build_sample_input(inputs_by_module)
      sample = {}
      inputs_by_module.each do |_module_name, inputs|
        inputs.each do |input|
          sample[input[:name]] = infer_sample_value(input)
        end
      end
      sample
    end

    def infer_sample_value(input)
      schema = input[:schema] || ""

      # Check for specific types in schema
      if schema.include?(":array")
        if schema.include?("hash do")
          [{}]  # Array of objects
        else
          []
        end
      elsif schema.include?(":bool")
        false
      elsif schema.include?(":integer")
        0
      elsif schema.include?(":string")
        if schema.include?("included_in?:")
          # Extract first valid value
          match = schema.match(/included_in\?:\s*%w\[([^\]]+)\]/)
          match ? match[1].split.first : ""
        else
          ""
        end
      else
        nil
      end
    end
  end
end
