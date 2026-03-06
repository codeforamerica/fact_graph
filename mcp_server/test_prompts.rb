#!/usr/bin/env ruby
# frozen_string_literal: true

# Test prompt templates

require "bundler/setup"
require_relative "lib/prompts"
require_relative "lib/prompts/examples"

puts "=" * 60
puts "Testing Prompt Templates"
puts "=" * 60
puts

# Test 1: Render ANALYZE_POLICY
puts "1. ANALYZE_POLICY prompt"
puts "-" * 40
policy = "People with income under $30,000 and assets under $5,000 are eligible for assistance."
prompt = Prompts.render(Prompts::ANALYZE_POLICY, policy_text: policy)
puts "Input policy: #{policy}"
puts "Rendered prompt length: #{prompt.length} chars"
puts "Contains policy text: #{prompt.include?(policy)}"
puts

# Test 2: Render POLICY_TO_CODE
puts "2. POLICY_TO_CODE prompt"
puts "-" * 40
prompt = Prompts.render(Prompts::POLICY_TO_CODE, policy_text: policy)
puts "Rendered prompt length: #{prompt.length} chars"
puts "Contains DSL reference: #{prompt.include?('FactGraph DSL Reference')}"
puts "Contains example: #{prompt.include?('income_threshold')}"
puts

# Test 3: Render FIX_ERRORS
puts "3. FIX_ERRORS prompt"
puts "-" * 40
code = "class Broken < FactGraph::Graph\n  fact :x do\nend"
errors = "Syntax error: unexpected end"
prompt = Prompts.render(Prompts::FIX_ERRORS, code: code, errors: errors)
puts "Rendered prompt length: #{prompt.length} chars"
puts "Contains code: #{prompt.include?('class Broken')}"
puts "Contains errors: #{prompt.include?('Syntax error')}"
puts

# Test 4: Format examples
puts "4. Few-shot examples"
puts "-" * 40
examples = Prompts.format_examples(count: 2)
puts "Formatted examples length: #{examples.length} chars"
puts "Contains simple_threshold policy: #{examples.include?('income is below $30,000')}"
puts "Contains multi_factor policy: #{examples.include?('130%')}"
puts

# Test 5: Get specific example
puts "5. Get specific example"
puts "-" * 40
ex = Prompts.get_example("per_entity")
puts "Example name: #{ex[:name]}"
puts "Policy preview: #{ex[:policy][0..80]}..."
puts "Code preview: #{ex[:code][0..80]}..."
puts

# Test 6: Verify examples are valid FactGraph code
puts "6. Validate example code"
puts "-" * 40
require "fact_graph"

Prompts::EXAMPLES.each do |ex|
  FactGraph::Graph.graph_registry = []
  begin
    eval(ex[:code])
    facts_count = FactGraph::Graph.graph_registry.length
    puts "  #{ex[:name]}: ✓ (#{facts_count} facts)"
  rescue => e
    puts "  #{ex[:name]}: ✗ #{e.message}"
  end
end
puts

puts "=" * 60
puts "All prompt tests completed!"
puts "=" * 60
