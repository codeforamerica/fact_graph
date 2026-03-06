# frozen_string_literal: true

require_relative "../code_validator"

class ValidateCode < MCP::Tool
  description "Validate FactGraph Ruby code for syntax errors, structural issues, and common problems. " \
              "Returns detailed, structured errors to help fix issues. " \
              "Checks: Ruby syntax, Graph subclass definitions, dependency references, input schemas."

  input_schema(
    type: "object",
    properties: {
      test_input: {
        type: "object",
        description: "Optional sample input to test evaluation against"
      }
    }
  )

  class << self
    def call(test_input: nil, server_context:)
      graph_state = server_context[:graph_state]
      code = graph_state.export_code

      if code.nil? || code.empty?
        return error_response("No code to validate. Use add_fact first.")
      end

      # Run validation pipeline
      validator = CodeValidator.new(code).validate
      result = validator.to_h

      # If valid and test_input provided, also run evaluation
      if validator.valid? && test_input
        eval_result = test_evaluation(code, test_input)
        result[:test_evaluation] = eval_result
      end

      # Cleanup
      validator.cleanup

      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate(result)
      }])
    end

    private

    def error_response(message)
      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate({
          valid: false,
          errors: [{ type: "validation_error", message: message }],
          warnings: [],
          facts: []
        })
      }])
    end

    def test_evaluation(code, test_input)
      begin
        # Clear and evaluate
        FactGraph::Graph.graph_registry = []
        eval(code)

        # Symbolize input keys
        symbolized_input = deep_symbolize_keys(test_input)

        # Evaluate
        results = FactGraph::Evaluator.evaluate(symbolized_input, graph_class: FactGraph::Graph)

        # Check for errors in results
        fact_errors = extract_fact_errors(results)

        {
          success: fact_errors.empty?,
          input: test_input,
          results: stringify_results(results),
          fact_errors: fact_errors
        }
      rescue => e
        {
          success: false,
          error: e.message,
          backtrace: e.backtrace.first(3)
        }
      end
    end

    def extract_fact_errors(results)
      errors = []
      results.each do |module_name, facts|
        facts.each do |fact_name, result|
          if result.is_a?(Hash) && (result[:fact_bad_inputs] || result[:fact_dependency_unmet])
            errors << {
              module: module_name.to_s,
              fact: fact_name.to_s,
              bad_inputs: result[:fact_bad_inputs]&.transform_keys(&:to_s),
              unmet_dependencies: result[:fact_dependency_unmet]&.transform_keys(&:to_s)
            }
          end
        end
      end
      errors
    end

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
      when Symbol
        obj.to_s
      else
        obj
      end
    end
  end
end
