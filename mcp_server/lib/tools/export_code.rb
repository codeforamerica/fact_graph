# frozen_string_literal: true

class ExportCode < MCP::Tool
  description "Export the current graph state as Ruby code. " \
              "Returns the complete FactGraph implementation ready to save to a file."

  input_schema(
    type: "object",
    properties: {
      format: {
        type: "string",
        enum: ["single_file", "per_module"],
        description: "Output format: single_file (default) or per_module"
      }
    }
  )

  class << self
    def call(format: "single_file", server_context:)
      graph_state = server_context[:graph_state]

      code = graph_state.export_code(format: format)

      if code.nil? || code.empty?
        return MCP::Tool::Response.new([{
          type: "text",
          text: "No facts defined yet. Use add_fact or generate_fact_graph first."
        }])
      end

      MCP::Tool::Response.new([{
        type: "text",
        text: code
      }])
    end
  end
end
