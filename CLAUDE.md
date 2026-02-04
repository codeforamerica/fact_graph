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
