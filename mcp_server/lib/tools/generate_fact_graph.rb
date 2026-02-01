# frozen_string_literal: true

class GenerateFactGraph < MCP::Tool
  description "Generate a FactGraph implementation from a natural language policy description. " \
              "Returns Ruby code defining Graph subclasses with facts, inputs, and dependencies."

  input_schema(
    type: "object",
    properties: {
      policy: {
        type: "string",
        description: "Natural language description of the policy rules and eligibility criteria"
      },
      module_name: {
        type: "string",
        description: "Name for the generated module (optional, will be inferred from policy if not provided)"
      }
    },
    required: ["policy"]
  )

  class << self
    def call(policy:, module_name: nil, server_context:)
      # TODO: This is where the LLM-generated code will come from
      # For now, return a stub that shows the expected format
      # The generated code is returned for display only - use add_fact to build the graph
      code = generate_stub_code(policy, module_name)

      MCP::Tool::Response.new([{
        type: "text",
        text: code
      }])
    end

    private

    def generate_stub_code(policy, module_name)
      module_name ||= "GeneratedPolicy"
      <<~RUBY
        # Generated FactGraph for: #{policy[0..50]}...
        # TODO: Replace with actual LLM-generated implementation

        class #{module_name}Facts < FactGraph::Graph
          # Define facts here based on policy rules
        end
      RUBY
    end
  end
end
