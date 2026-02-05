# frozen_string_literal: true

class AddGraphContext < MCP::Tool
  description "Add a graph context for multi-graph support. Graph contexts allow you to have " \
              "shared facts (used by all contexts) and context-specific facts (e.g., different " \
              "constants or rules for CO vs NJ, or 2024 vs 2025)."

  input_schema(
    type: "object",
    properties: {
      name: {
        type: "string",
        description: "Name of the graph context (e.g., 'co_2025', 'nj_2024')"
      },
      base_class_name: {
        type: "string",
        description: "Optional custom base class name. Defaults to CamelCase + 'Graph' (e.g., 'Co2025Graph')"
      }
    },
    required: ["name"]
  )

  class << self
    def call(name:, base_class_name: nil, server_context:)
      graph_state = server_context[:graph_state]

      context = graph_state.add_graph_context(name, base_class_name: base_class_name)

      MCP::Tool::Response.new([{
        type: "text",
        text: "Added graph context '#{name}' with base class '#{context[:base_class_name]}'"
      }])
    end
  end
end
