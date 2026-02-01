# frozen_string_literal: true

class RunTestCases < MCP::Tool
  description "Run all stored test cases against the current fact graph. Returns detailed " \
              "results showing which tests passed and which failed with specific differences."

  input_schema(
    type: "object",
    properties: {}
  )

  class << self
    def call(server_context:)
      graph_state = server_context[:graph_state]
      code = graph_state.export_code

      if graph_state.test_cases.empty?
        return MCP::Tool::Response.new([{
          type: "text",
          text: JSON.pretty_generate({
            error: "No test cases defined. Use add_test_case first."
          })
        }])
      end

      if code.nil? || code.empty?
        return MCP::Tool::Response.new([{
          type: "text",
          text: JSON.pretty_generate({
            error: "No code to test. Use add_fact first."
          })
        }])
      end

      results = run_tests(code, graph_state.test_cases)

      MCP::Tool::Response.new([{
        type: "text",
        text: JSON.pretty_generate(results)
      }])
    end

    private

    def run_tests(code, test_cases)
      passed = 0
      failed = 0
      test_results = []

      test_cases.each_with_index do |test_case, index|
        result = run_single_test(code, test_case, index)
        test_results << result
        if result[:passed]
          passed += 1
        else
          failed += 1
        end
      end

      {
        summary: {
          total: test_cases.length,
          passed: passed,
          failed: failed
        },
        tests: test_results
      }
    end

    def run_single_test(code, test_case, index)
      name = test_case[:name]
      input = deep_symbolize_keys(test_case[:input])
      expected = deep_symbolize_keys(test_case[:expected])

      begin
        # Clear and evaluate code
        FactGraph::Graph.graph_registry = []
        eval(code)

        # Run evaluation
        actual = FactGraph::Evaluator.evaluate(input, graph_class: FactGraph::Graph)

        # Check expected values
        errors = compare_results(expected, actual)

        if errors.empty?
          {
            index: index,
            name: name,
            passed: true
          }
        else
          {
            index: index,
            name: name,
            passed: false,
            errors: errors,
            actual: stringify_keys(actual)
          }
        end
      rescue => e
        {
          index: index,
          name: name,
          passed: false,
          error: e.message
        }
      end
    end

    def compare_results(expected, actual)
      errors = []

      expected.each do |module_name, expected_facts|
        actual_module = actual[module_name]
        if actual_module.nil?
          errors << "Module '#{module_name}' not found in results"
          next
        end

        expected_facts.each do |fact_name, expected_value|
          actual_value = actual_module[fact_name]
          unless values_match?(expected_value, actual_value)
            errors << {
              fact: "#{module_name}.#{fact_name}",
              expected: expected_value,
              actual: actual_value
            }
          end
        end
      end

      errors
    end

    def values_match?(expected, actual)
      # Handle hash comparison (including nested)
      if expected.is_a?(Hash) && actual.is_a?(Hash)
        expected.all? do |k, v|
          actual.key?(k) && values_match?(v, actual[k])
        end
      else
        expected == actual
      end
    end

    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
            .transform_values { |v| deep_symbolize_keys(v) }
      when Array
        obj.map { |v| deep_symbolize_keys(v) }
      else
        obj
      end
    end

    def stringify_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_s).transform_values { |v| stringify_keys(v) }
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
