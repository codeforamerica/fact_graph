#!/usr/bin/env ruby
# frozen_string_literal: true

# Test that all example policies work correctly

require "bundler/setup"
require "fact_graph"
require "json"

Dir.glob("examples/*.rb").sort.each { |f| require_relative f }

def test_example(name, mod)
  puts "=" * 60
  puts "Testing: #{name}"
  puts "=" * 60

  code = mod::FACT_GRAPH_CODE
  test_cases = mod::TEST_CASES

  # Clear registry and load the code
  FactGraph::Graph.graph_registry = []
  eval(code)

  passed = 0
  failed = 0

  test_cases.each_with_index do |test_case, i|
    description = test_case[:description]
    input = test_case[:input]
    expected = test_case[:expected]

    # Evaluate
    results = FactGraph::Evaluator.evaluate(input, graph_class: FactGraph::Graph)

    # Check expected values (partial match - only check keys in expected)
    errors = []
    expected.each do |module_name, expected_facts|
      actual_module = results[module_name]
      if actual_module.nil?
        errors << "Module #{module_name} not found in results"
        next
      end

      expected_facts.each do |fact_name, expected_value|
        actual_value = actual_module[fact_name]
        if actual_value != expected_value
          errors << "#{module_name}.#{fact_name}: expected #{expected_value.inspect}, got #{actual_value.inspect}"
        end
      end
    end

    if errors.empty?
      puts "  ✓ #{description}"
      passed += 1
    else
      puts "  ✗ #{description}"
      errors.each { |e| puts "    - #{e}" }
      failed += 1
    end
  end

  puts
  puts "  Results: #{passed} passed, #{failed} failed"
  puts

  failed == 0
end

all_passed = true

# Test each example
all_passed &= test_example("Simple Income Threshold", Examples::SimpleIncomeThreshold)
all_passed &= test_example("SNAP-like Benefits", Examples::SnapLikeBenefits)
all_passed &= test_example("Household Members", Examples::HouseholdMembers)
all_passed &= test_example("Tax Credit Phaseout", Examples::TaxCreditPhaseout)

puts "=" * 60
if all_passed
  puts "All examples passed!"
else
  puts "Some examples failed!"
  exit 1
end
