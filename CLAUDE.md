# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Run all tests:** `bundle exec rake spec`
- **Run single test file:** `bundle exec rspec spec/path/to/spec.rb`
- **Run specific test:** `bundle exec rspec spec/path/to/spec.rb:LINE_NUMBER`
- **Lint:** `bundle exec rubocop`
- **Auto-fix lint issues:** `bundle exec rubocop -a`
- **Run tests and lint:** `bundle exec rake` (default task)
- **Install dependencies:** `bundle install`
- **Interactive console:** `bin/console`

## Architecture

FactGraph is a Ruby gem for declarative fact computation with dependency resolution and input validation. Facts are organized into modules, form a dependency graph, and are evaluated lazily.

### Core Components

**Graph** (`lib/fact_graph.rb`) - Base class for defining fact collections. Subclass `FactGraph::Graph` to define facts using the DSL:
- `fact :name do ... end` - Define a computed fact
- `constant :name { value }` - Define a constant value
- `in_module :module_name do ... end` - Override the module name for facts within the block

**Fact** (`lib/fact_graph/fact.rb`) - Individual fact definition containing:
- `input :name do Dry::Schema.Params { ... } end` - Declare required input with validation
- `dependency :fact_name, from: :module_name` - Declare dependency on another fact
- A resolver proc that computes the fact value using `data` (a DataContainer)

**Input Validation** - Inputs use [Dry::Schema](https://dry-rb.org/gems/dry-schema/) for validation. Common types:

| Type | Example |
|------|---------|
| Integer | `required(:age).value(:integer, gteq?: 0)` |
| String | `required(:name).value(:string)` |
| Boolean | `required(:is_citizen).value(:bool)` |
| Enum | `required(:status).value(:string, included_in?: ["single", "married"])` |
| Range | `required(:age).value(:integer, gteq?: 0, lteq?: 120)` |
| Date | `required(:dob).value(:date)` |
| Optional | `optional(:email).value(:string)` |

**Evaluator** (`lib/fact_graph/evaluator.rb`) - Orchestrates evaluation:
- `Evaluator.evaluate(input, graph_class:, module_filter:)` - Evaluate all facts
- `Evaluator.input_errors(results)` - Extract validation errors from results

**DataContainer** (`lib/fact_graph/data_container.rb`) - Wrapper passed to resolver procs providing access to `data[:input]` and `data[:dependencies]`. The `must_match` helper catches `NoMatchingPatternError` for pattern matching.

### Key Patterns

**Fact Results** - A fact evaluates to either its computed value or an error hash:
```ruby
{ fact_bad_inputs: { [:path] => Set.new(["error"]) }, fact_dependency_unmet: {} }
```

**Entity Facts** - Facts can be computed per-entity using `per_entity: :entity_name`:
```ruby
fact :income, per_entity: :applicants do
  input :income, per_entity: true do ... end
  proc { data[:input][:income] }
end
```

Input structure: `{ applicants: [{ income: 30000 }, { income: 15000 }] }`
Result structure: `{ my_module: { income: { 0 => 30000, 1 => 15000 } } }`

**Aggregating Per-Entity Results** - A regular (non-per-entity) fact depending on a per-entity fact receives a hash of `{entity_index => value}`:
```ruby
fact :eligible_count do
  dependency :member_eligible  # Gets { 0 => true, 1 => false, ... }

  proc do
    results = data[:dependencies][:member_eligible]
    results.values.count { |v| v == true }
  end
end
```

**Graph Subclasses and Fact Registration** - Facts defined in a class are registered on that class's **parent's** `graph_registry`, not the class itself. This enables composition patterns:

```ruby
# Simple case: facts go to FactGraph::Graph.graph_registry
class MyFacts < FactGraph::Graph
  fact :foo do ... end
end
FactGraph::Evaluator.evaluate(input, graph_class: FactGraph::Graph)
```

**Multiple Contexts with Shared Facts** - Use intermediate classes and mixins to create separate graphs that share some facts but differ in others:

```ruby
# Shared facts as a mixin (uses ActiveSupport::Concern)
module SharedEligibility
  extend ActiveSupport::Concern
  included do
    in_module :eligibility do
      fact :income_eligible do ... end
    end
  end
end

# Context-specific graphs with separate registries
class Colorado2024Graph < FactGraph::Graph; end
class Colorado2024 < Colorado2024Graph
  include SharedEligibility
  in_module :limits do
    constant(:income_limit) { 30_000 }  # 2024-specific
  end
end

class Colorado2025Graph < FactGraph::Graph; end
class Colorado2025 < Colorado2025Graph
  include SharedEligibility
  in_module :limits do
    constant(:income_limit) { 32_000 }  # 2025-specific
  end
end

# Evaluate each context separately
FactGraph::Evaluator.evaluate(input, graph_class: Colorado2024Graph)
FactGraph::Evaluator.evaluate(input, graph_class: Colorado2025Graph)
```

The intermediate classes (`Colorado2024Graph`, `Colorado2025Graph`) each have their own `graph_registry`, so facts don't mix between contexts. See `spec/fixtures/context_specific_facts/` for complete examples.

**Pattern Matching** - Resolver procs use Ruby pattern matching to destructure data:
```ruby
proc do
  data in input: { field: }, dependencies: { other_fact: }
  # compute result
end
```

**Allow Unmet Dependencies** - Facts can opt-in to partial evaluation using the `allow_unmet_dependencies: true` parameter:

```ruby
fact :early_eligibility_check, allow_unmet_dependencies: true do
  dependency :income
  dependency :age

  proc do
    data in dependencies: { income:, age: }

    # Check if dependencies are error hashes (missing/invalid input)
    income_error = income in { fact_bad_inputs:, fact_dependency_unmet: }
    age_error = age in { fact_bad_inputs:, fact_dependency_unmet: }

    # Can determine ineligibility from income alone
    if income.is_a?(Integer) && income > 100_000
      false  # Definitely ineligible, don't need age
    elsif age.is_a?(Integer) && age < 18
      false  # Definitely ineligible, don't need income
    elsif income_error || age_error
      data_errors  # Can't determine yet, propagate errors
    else
      true  # Both present and within bounds
    end
  end
end
```

Key behaviors:
- **Default (`allow_unmet_dependencies: false`)**: If any input fails validation or any dependency returns an error, the resolver proc does NOT run. The fact returns an error hash instead.
- **With `allow_unmet_dependencies: true`**: The resolver proc ALWAYS runs. Errors are stored in `data.data_errors` (accessible via `data_errors` helper) instead of preventing execution.
- **Error detection**: Check if a value is an error with pattern matching: `value in { fact_bad_inputs:, fact_dependency_unmet: }`
- **Error propagation**: Return `data_errors` from the resolver to propagate errors to dependent facts.

Use cases:
- Short-circuit evaluation (determine ineligibility without collecting all data)
- Aggregating per-entity results where some entities may have errors
- Progressive/phased data collection where early facts guide which later questions to ask

## MCP Server

The `mcp_server/` directory contains an MCP server for interactively building and testing fact graphs. Start with `mcp_server/start.sh` (configured in `.mcp.json`).

### Resources
- `factgraph://docs/dsl` - Complete DSL reference with examples
- `factgraph://examples/{name}` - Working examples: `simple_income`, `snap_benefits`, `household_members`, `tax_credit`, `multi_graph`, `progressive_screening`
- `factgraph://current/facts` and `factgraph://current/modules` - Current session state

### Key Tools
- `add_fact` / `modify_fact` / `remove_fact` - Manage facts in session state
- `evaluate_facts` - Test facts against sample input
- `validate_code` - Check for syntax and structural errors
- `export_code` - Generate Ruby code from session state (single_file or per_module)
- `add_test_case` / `run_test_cases` - Define and run test cases
- `add_graph_context` - Set up multi-graph contexts for shared + context-specific facts
- `get_required_inputs` - Trace all input schemas needed for specific modules
