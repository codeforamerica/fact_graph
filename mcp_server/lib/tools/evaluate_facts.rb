# frozen_string_literal: true

class EvaluateFacts < MCP::Tool
  description "Evaluate the current FactGraph against sample input data. " \
              "Returns the computed fact values or any errors encountered."

  input_schema(
    type: "object",
    properties: {
      input: {
        type: "object",
        description: "Input data to evaluate the fact graph against"
      },
      code: {
        type: "string",
        description: "Ruby code to evaluate (optional, uses current graph state if not provided)"
      },
      module_filter: {
        type: "array",
        items: { type: "string" },
        description: "Optional list of module names to evaluate (evaluates all if not provided)"
      }
    },
    required: ["input"]
  )

  class << self
    def call(input:, code: nil, module_filter: nil, server_context:)
      graph_state = server_context[:graph_state]
      code ||= graph_state.code

      if code.nil? || code.empty?
        return MCP::Tool::Response.new([{
          type: "text",
          text: JSON.generate({ error: "No code to evaluate" })
        }])
      end

      begin
        # Clear the global registry before evaluating new code
        # (facts register to FactGraph::Graph.graph_registry via superclass)
        FactGraph::Graph.graph_registry = []

        # Evaluate code - this registers facts to FactGraph::Graph.graph_registry
        eval(code)

        # Convert string keys to symbols for input
        symbolized_input = deep_symbolize_keys(input)

        # Evaluate using FactGraph::Graph (where facts are registered)
        module_filter_syms = module_filter&.map(&:to_sym)
        results = FactGraph::Evaluator.evaluate(
          symbolized_input,
          graph_class: FactGraph::Graph,
          module_filter: module_filter_syms
        )

        MCP::Tool::Response.new([{
          type: "text",
          text: JSON.generate({ results: stringify_results(results) })
        }])
      rescue => e
        MCP::Tool::Response.new([{
          type: "text",
          text: JSON.generate({ error: e.message, backtrace: e.backtrace.first(5) })
        }])
      end
    end

    private

    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize_keys(v) }
      when Array
        obj.map { |v| deep_symbolize_keys(v) }
      else
        obj
      end
    end

    def stringify_results(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_s).transform_values { |v| stringify_results(v) }
      when Set
        obj.to_a
      else
        obj
      end
    end
  end
end
