# frozen_string_literal: true

class ModifyFact < MCP::Tool
  description "Modify an existing fact in the current graph. Can update inputs, dependencies, " \
              "resolver logic, or convert between fact and constant."

  input_schema(
    type: "object",
    properties: {
      name: {
        type: "string",
        description: "Name of the fact to modify"
      },
      module_name: {
        type: "string",
        description: "Module containing the fact"
      },
      inputs: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            schema: { type: "string" },
            per_entity: { type: "boolean" }
          }
        },
        description: "New input definitions (replaces existing)"
      },
      dependencies: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            from: { type: "string" }
          }
        },
        description: "New dependencies (replaces existing)"
      },
      resolver: {
        type: "string",
        description: "New resolver proc body"
      },
      constant_value: {
        type: "string",
        description: "Convert to constant with this value (removes inputs/resolver)"
      },
      allow_unmet_dependencies: {
        type: "boolean",
        description: "If true, resolver runs even when dependencies have errors"
      }
    },
    required: ["name", "module_name"]
  )

  class << self
    def call(name:, module_name:, inputs: nil, dependencies: nil, resolver: nil,
             constant_value: nil, allow_unmet_dependencies: nil, server_context:)
      graph_state = server_context[:graph_state]

      fact = graph_state.get_fact(name, module_name)
      unless fact
        return MCP::Tool::Response.new([{
          type: "text",
          text: "Fact '#{name}' not found in module '#{module_name}'"
        }])
      end

      updates = {}
      updates[:inputs] = inputs if inputs
      updates[:dependencies] = dependencies if dependencies
      updates[:resolver] = resolver if resolver
      updates[:allow_unmet_dependencies] = allow_unmet_dependencies unless allow_unmet_dependencies.nil?

      if constant_value
        updates[:constant_value] = constant_value
        updates[:inputs] = []
        updates[:dependencies] = []
        updates[:resolver] = nil
      end

      graph_state.update_fact(name, module_name, updates)

      MCP::Tool::Response.new([{
        type: "text",
        text: "Modified fact '#{name}' in module '#{module_name}'"
      }])
    end
  end
end
