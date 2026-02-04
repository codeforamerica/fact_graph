#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "mcp"
require "json"
require "fact_graph"

# Load library code
require_relative "lib/graph_state"
require_relative "lib/resources"
require_relative "lib/code_validator"
require_relative "lib/prompts"
require_relative "lib/prompts/examples"

# Load tools
require_relative "lib/tools/validate_code"
require_relative "lib/tools/evaluate_facts"
require_relative "lib/tools/add_fact"
require_relative "lib/tools/modify_fact"
require_relative "lib/tools/remove_fact"
require_relative "lib/tools/export_code"
require_relative "lib/tools/add_test_case"
require_relative "lib/tools/run_test_cases"
require_relative "lib/tools/list_test_cases"
require_relative "lib/tools/clear_graph"
require_relative "lib/tools/get_required_inputs"

# Initialize graph state
graph_state = GraphState.new

# Create the MCP server
server = MCP::Server.new(
  name: "factgraph_policy_server",
  version: "0.1.0",
  tools: [
    ValidateCode,
    EvaluateFacts,
    AddFact,
    ModifyFact,
    RemoveFact,
    ExportCode,
    AddTestCase,
    RunTestCases,
    ListTestCases,
    ClearGraph,
    GetRequiredInputs
  ],
  resources: Resources.all_resources,
  server_context: {
    graph_state: graph_state
  }
)

# Register resource templates
Resources::TEMPLATES.each do |template|
  server.resources = server.resources + [template]
end

# Handle resource reads
server.resources_read_handler do |uri, server_context|
  Resources.read(uri, server_context[:graph_state])
end

# Register prompts
server.define_prompt(
  name: "analyze_policy",
  description: "Break down a policy into discrete rules for FactGraph implementation",
  arguments: [
    { name: "policy_text", description: "The policy text to analyze", required: true }
  ]
) do |args, _server_context|
  Prompts.render(Prompts::ANALYZE_POLICY, policy_text: args[:policy_text])
end

server.define_prompt(
  name: "policy_to_code",
  description: "Convert a policy directly to FactGraph Ruby code",
  arguments: [
    { name: "policy_text", description: "The policy text to implement", required: true }
  ]
) do |args, _server_context|
  Prompts.render(Prompts::POLICY_TO_CODE, policy_text: args[:policy_text])
end

server.define_prompt(
  name: "fix_errors",
  description: "Fix validation errors in FactGraph code",
  arguments: [
    { name: "code", description: "The code with errors", required: true },
    { name: "errors", description: "The validation errors to fix", required: true }
  ]
) do |args, _server_context|
  Prompts.render(Prompts::FIX_ERRORS, code: args[:code], errors: args[:errors])
end

server.define_prompt(
  name: "add_fact",
  description: "Add a new fact to existing FactGraph code",
  arguments: [
    { name: "code", description: "The existing code", required: true },
    { name: "fact_description", description: "Description of the fact to add", required: true }
  ]
) do |args, _server_context|
  Prompts.render(Prompts::ADD_FACT, code: args[:code], fact_description: args[:fact_description])
end

# Run with stdio transport
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
