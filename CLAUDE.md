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

**Graph Subclasses** - Create separate graphs with shared/specific facts by subclassing Graph and including mixins (see `spec/fixtures/context_specific_facts/`).

**Pattern Matching** - Resolver procs use Ruby pattern matching to destructure data:
```ruby
proc do
  data in input: { field: }, dependencies: { other_fact: }
  # compute result
end
```
