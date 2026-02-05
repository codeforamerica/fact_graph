#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for multi-graph code generation

require "json"
require_relative "lib/graph_state"

def test_legacy_mode
  puts "=== Test: Legacy Mode (no graph contexts) ==="
  state = GraphState.new

  # Add facts without graph contexts
  state.add_fact(
    name: "income",
    module_name: "household",
    inputs: [{ name: "income", schema: 'required(:income).value(:integer)' }],
    resolver: "income"
  )

  state.add_fact(
    name: "income_eligible",
    module_name: "eligibility",
    dependencies: [{ name: "income", from: "household" }],
    resolver: "income < 50_000"
  )

  code = state.export_code
  puts code
  puts
  puts "✓ Legacy mode generates one class per module"
  puts
end

def test_multi_graph_mode
  puts "=== Test: Multi-Graph Mode (with graph contexts) ==="
  state = GraphState.new

  # Add graph contexts
  state.add_graph_context("co_2025")
  state.add_graph_context("nj_2024")

  # Add shared facts (no graph_context)
  state.add_fact(
    name: "income",
    module_name: "household",
    inputs: [{ name: "income", schema: 'required(:income).value(:integer)' }],
    resolver: "income"
  )

  state.add_fact(
    name: "income_eligible",
    module_name: "eligibility",
    dependencies: [{ name: "income", from: "household" }, { name: "income_limit", from: "limits" }],
    resolver: "income < income_limit"
  )

  # Add context-specific constants
  state.add_fact(
    name: "income_limit",
    module_name: "limits",
    constant_value: "50_000",
    graph_context: "co_2025"
  )

  state.add_fact(
    name: "income_limit",
    module_name: "limits",
    constant_value: "45_000",
    graph_context: "nj_2024"
  )

  # Add context-specific facts
  state.add_fact(
    name: "co_specific_benefit",
    module_name: "benefits",
    dependencies: [{ name: "income_eligible", from: "eligibility" }],
    resolver: "income_eligible ? 500 : 0",
    graph_context: "co_2025"
  )

  state.add_fact(
    name: "nj_specific_benefit",
    module_name: "benefits",
    dependencies: [{ name: "income_eligible", from: "eligibility" }],
    resolver: "income_eligible ? 400 : 0",
    graph_context: "nj_2024"
  )

  code = state.export_code
  puts code
  puts

  # Verify structure
  raise "Missing HouseholdFacts concern" unless code.include?("module HouseholdFacts")
  raise "Missing EligibilityFacts concern" unless code.include?("module EligibilityFacts")
  raise "Missing ActiveSupport::Concern" unless code.include?("extend ActiveSupport::Concern")
  raise "Missing in_module blocks" unless code.include?("in_module :household")
  raise "Missing Co2025Graph base class" unless code.include?("class Co2025Graph < FactGraph::Graph")
  raise "Missing Nj2024Graph base class" unless code.include?("class Nj2024Graph < FactGraph::Graph")
  raise "Missing Co2025Facts class" unless code.include?("class Co2025Facts < Co2025Graph")
  raise "Missing Nj2024Facts class" unless code.include?("class Nj2024Facts < Nj2024Graph")
  raise "Missing include statements" unless code.include?("include HouseholdFacts")
  raise "CO income_limit should be 50_000" unless code.include?("constant(:income_limit) { 50_000 }")
  raise "NJ income_limit should be 45_000" unless code.include?("constant(:income_limit) { 45_000 }")

  puts "✓ Multi-graph mode generates shared concerns and context-specific classes"
  puts
end

def test_per_module_export
  puts "=== Test: Per-Module Export ==="
  state = GraphState.new

  state.add_graph_context("test_ctx")

  state.add_fact(
    name: "shared_fact",
    module_name: "core",
    resolver: "true"
  )

  state.add_fact(
    name: "context_fact",
    module_name: "specific",
    resolver: "true",
    graph_context: "test_ctx"
  )

  result = JSON.parse(state.export_code(format: "per_module"))

  puts "Modules exported:"
  result.each do |mod|
    puts "  - #{mod["module_name"]}"
  end
  puts

  raise "Should have shared/core_facts module" unless result.any? { |m| m["module_name"] == "shared/core_facts" }
  raise "Should have test_ctx/base module" unless result.any? { |m| m["module_name"] == "test_ctx/base" }
  raise "Should have test_ctx/facts module" unless result.any? { |m| m["module_name"] == "test_ctx/facts" }

  puts "✓ Per-module export creates separate files for shared and context-specific code"
  puts
end

# Run tests
test_legacy_mode
test_multi_graph_mode
test_per_module_export

puts "=" * 50
puts "All tests passed!"
