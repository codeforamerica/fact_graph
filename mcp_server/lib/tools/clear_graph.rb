# frozen_string_literal: true

class ClearGraph < MCP::Tool
  description "Clear the current graph state, removing all facts and test cases. " \
              "Use this to start fresh."

  input_schema(
    type: "object",
    properties: {
      keep_test_cases: {
        type: "boolean",
        description: "If true, keep test cases but clear facts (default: false)"
      }
    }
  )

  class << self
    def call(keep_test_cases: false, server_context:)
      graph_state = server_context[:graph_state]

      fact_count = graph_state.facts.length
      test_count = graph_state.test_cases.length
      context_count = graph_state.graph_contexts.length

      graph_state.clear(keep_test_cases: keep_test_cases)

      if keep_test_cases
        message = "Cleared #{fact_count} facts and #{context_count} graph contexts (kept #{test_count} test cases)"
      else
        message = "Cleared #{fact_count} facts, #{context_count} graph contexts, and #{test_count} test cases"
      end

      MCP::Tool::Response.new([{
        type: "text",
        text: message
      }])
    end
  end
end
