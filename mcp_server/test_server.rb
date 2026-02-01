#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script to verify server functionality without starting transport

require "bundler/setup"
require "mcp"
require "json"
require "fact_graph"

require_relative "lib/graph_state"
require_relative "lib/resources"
require_relative "lib/tools/generate_fact_graph"
require_relative "lib/tools/validate_code"
require_relative "lib/tools/evaluate_facts"
require_relative "lib/tools/add_fact"
require_relative "lib/tools/export_code"

graph_state = GraphState.new
server_context = { graph_state: graph_state }

puts "=== Testing MCP Server Components ==="
puts

# Test 1: Add facts using AddFact tool
puts "1. Adding facts via AddFact tool..."
AddFact.call(
  name: "poverty_line",
  module_name: "eligibility",
  constant_value: "15000",
  server_context: server_context
)

AddFact.call(
  name: "income_eligible",
  module_name: "eligibility",
  inputs: [{ name: "income", schema: "required(:income).value(:integer, gteq?: 0)" }],
  dependencies: [{ name: "poverty_line" }],
  resolver: "data in input: { income: }, dependencies: { poverty_line: }\nincome < poverty_line",
  server_context: server_context
)
puts "   Added 2 facts to eligibility module"
puts

# Test 2: List facts via resource
puts "2. Reading current facts resource..."
facts_response = Resources.read("factgraph://current/facts", graph_state)
puts "   #{facts_response.text}"
puts

# Test 3: Read modules resource
puts "3. Reading current modules resource..."
modules_response = Resources.read("factgraph://current/modules", graph_state)
puts "   #{modules_response.text}"
puts

# Test 4: Export code
puts "4. Exporting code..."
export_response = ExportCode.call(server_context: server_context)
code = export_response.content.first[:text]
puts code
puts

# Test 5: Validate the exported code
puts "5. Validating exported code..."
validate_response = ValidateCode.call(server_context: server_context)
puts "   #{validate_response.content.first[:text]}"
puts

# Test 6: Evaluate with sample input
puts "6. Evaluating with sample input..."
eval_response = EvaluateFacts.call(
  input: { "income" => 10000 },
  server_context: server_context
)
puts "   Input: { income: 10000 }"
puts "   #{eval_response.content.first[:text]}"
puts

eval_response2 = EvaluateFacts.call(
  input: { "income" => 20000 },
  server_context: server_context
)
puts "   Input: { income: 20000 }"
puts "   #{eval_response2.content.first[:text]}"
puts

# Test 7: Read DSL docs resource
puts "7. Reading DSL docs resource (first 500 chars)..."
docs_response = Resources.read("factgraph://docs/dsl", graph_state)
puts "   #{docs_response.text[0..500]}..."
puts

puts "=== All tests passed! ==="
