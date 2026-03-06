# frozen_string_literal: true

class AddTestCase < MCP::Tool
  description "Add a test case to validate the current fact graph. Test cases are stored " \
              "in the session and can be run with run_test_cases."

  input_schema(
    type: "object",
    properties: {
      name: {
        type: "string",
        description: "Descriptive name for this test case"
      },
      input: {
        type: "object",
        description: "Input data for the test"
      },
      expected: {
        type: "object",
        description: "Expected results (partial match - only specified facts are checked)"
      }
    },
    required: ["name", "input", "expected"]
  )

  class << self
    def call(name:, input:, expected:, server_context:)
      graph_state = server_context[:graph_state]

      test_case = {
        name: name,
        input: input,
        expected: expected
      }

      graph_state.add_test_case(test_case)

      MCP::Tool::Response.new([{
        type: "text",
        text: "Added test case '#{name}' (#{graph_state.test_cases.length} total)"
      }])
    end
  end
end
