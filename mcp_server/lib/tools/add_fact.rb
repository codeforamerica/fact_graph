# frozen_string_literal: true

class AddFact < MCP::Tool
  description "Add a new fact to the current FactGraph. Specify the fact name, module, " \
              "inputs, dependencies, and resolver logic."

  input_schema(
    type: "object",
    properties: {
      name: {
        type: "string",
        description: "Name of the fact (e.g., 'income_eligible')"
      },
      module_name: {
        type: "string",
        description: "Module to add the fact to (e.g., 'eligibility')"
      },
      inputs: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            schema: { type: "string", description: "Dry::Schema definition as Ruby code" },
            per_entity: { type: "boolean" }
          }
        },
        description: "Input definitions for this fact"
      },
      dependencies: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            from: { type: "string", description: "Module name to import from (optional)" }
          }
        },
        description: "Dependencies on other facts"
      },
      resolver: {
        type: "string",
        description: "Ruby code for the resolver proc body"
      },
      per_entity: {
        type: "string",
        description: "Entity name if this is a per-entity fact (e.g., 'applicants')"
      },
      constant_value: {
        type: "string",
        description: "If this is a constant, provide the value instead of inputs/resolver"
      },
      allow_unmet_dependencies: {
        type: "boolean",
        description: "If true, resolver runs even when dependencies have errors. " \
                     "Use for short-circuit evaluation or aggregating partial results."
      }
    },
    required: ["name", "module_name"]
  )

  class << self
    def call(name:, module_name:, inputs: nil, dependencies: nil, resolver: nil,
             per_entity: nil, constant_value: nil, allow_unmet_dependencies: nil, server_context:)
      graph_state = server_context[:graph_state]

      fact_def = {
        name: name,
        module_name: module_name,
        inputs: inputs || [],
        dependencies: dependencies || [],
        resolver: resolver,
        per_entity: per_entity,
        constant_value: constant_value,
        allow_unmet_dependencies: allow_unmet_dependencies
      }

      graph_state.add_fact(fact_def)

      MCP::Tool::Response.new([{
        type: "text",
        text: "Added fact '#{name}' to module '#{module_name}'"
      }])
    end
  end
end
