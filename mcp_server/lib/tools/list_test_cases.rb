# frozen_string_literal: true

class ListTestCases < MCP::Tool
  description "List all test cases stored in the current session."

  input_schema(
    type: "object",
    properties: {}
  )

  class << self
    def call(server_context:)
      graph_state = server_context[:graph_state]

      if graph_state.test_cases.empty?
        return MCP::Tool::Response.new([{
          type: "text",
          text: "No test cases defined."
        }])
      end

      summary = graph_state.test_cases.map.with_index do |tc, i|
        {
          index: i,
          name: tc[:name],
          input_keys: tc[:input].keys,
          expected_modules: tc[:expected].keys
        }
      end

      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate(summary)
      }])
    end
  end
end
