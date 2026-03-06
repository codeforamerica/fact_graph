# frozen_string_literal: true

class RemoveFact < MCP::Tool
  description "Remove a fact from the current graph."

  input_schema(
    type: "object",
    properties: {
      name: {
        type: "string",
        description: "Name of the fact to remove"
      },
      module_name: {
        type: "string",
        description: "Module containing the fact"
      }
    },
    required: ["name", "module_name"]
  )

  class << self
    def call(name:, module_name:, server_context:)
      graph_state = server_context[:graph_state]

      fact = graph_state.get_fact(name, module_name)
      unless fact
        return MCP::Tool::Response.new([{
          type: "text",
          text: "Fact '#{name}' not found in module '#{module_name}'"
        }])
      end

      graph_state.remove_fact(name, module_name)

      MCP::Tool::Response.new([{
        type: "text",
        text: "Removed fact '#{name}' from module '#{module_name}'"
      }])
    end
  end
end
