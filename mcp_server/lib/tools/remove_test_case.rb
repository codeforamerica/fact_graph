# frozen_string_literal: true

class RemoveTestCase < MCP::Tool
  description "Remove a test case by index (0-based). Use list_test_cases to see current indices."

  input_schema(
    type: "object",
    properties: {
      index: {
        type: "integer",
        description: "Index of the test case to remove (0-based)"
      }
    },
    required: ["index"]
  )

  class << self
    def call(index:, server_context:)
      graph_state = server_context[:graph_state]

      if index < 0 || index >= graph_state.test_cases.length
        return MCP::Tool::Response.new([{
          type: "text",
          text: "Invalid index #{index}. There are #{graph_state.test_cases.length} test cases (indices 0-#{graph_state.test_cases.length - 1})"
        }])
      end

      removed = graph_state.remove_test_case(index)

      MCP::Tool::Response.new([{
        type: "text",
        text: "Removed test case '#{removed[:name]}' (#{graph_state.test_cases.length} remaining)"
      }])
    end
  end
end
