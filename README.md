# FactGraph

FactGraph is a Ruby gem for defining and evaluating interdependent facts as a directed acyclic graph (DAG). You declare what each fact is, what inputs it needs, and what other facts it depends on. The evaluator resolves dependencies in order, validates inputs, and captures errors in the result — so evaluation continues even when some inputs are invalid or missing, and every result tells you whether it succeeded or why it did not.

This makes it well-suited for rule engines, benefits-eligibility calculations, and similar domains: rather than failing fast on the first bad input, you get a complete picture of every fact's outcome in a single pass.

## Installation

Add to your Gemfile:

```ruby
gem "fact_graph", github: "codeforamerica/fact_graph"
```

Then run `bundle install`.

## Dependencies

### dry-schema

[dry-schema](https://dry-rb.org/gems/dry-schema) handles input validation. Each fact declares its expected inputs as `Dry::Schema.Params` blocks; the evaluator runs those schemas against the provided input and captures any errors in the result hash rather than raising. This keeps invalid input from silently propagating through the graph — downstream facts that depend on a fact with bad inputs are skipped and their results carry a `fact_dependency_unmet` marker.

### ActiveSupport

[ActiveSupport](https://guides.rubyonrails.org/active_support_core_extensions.html) is used internally by the gem for string utilities — specifically `String#underscore`, which auto-derives a fact's module name from its graph class name (e.g., `MathFacts` → `:math_facts`).

It is also the natural choice for structuring composable fact mixins in your own code. `ActiveSupport::Concern` provides an `included do` hook that runs class-level DSL calls (`fact`, `in_module`, etc.) against the including graph class rather than the mixin module itself. See [Context-specific graphs](#context-specific-graphs) for an example.

## Core concepts

| Term | Meaning |
|---|---|
| **Fact** | A named value: a constant, a value derived from input, or a value derived from other facts |
| **Graph** | A subclass of `FactGraph::Graph` that holds a set of fact definitions |
| **Module** | A logical grouping of facts within a graph; auto-derived from the class name or set explicitly with `in_module` |
| **Entity fact** | A fact evaluated once per entity in a collection (e.g., once per applicant) |
| **Aggregate fact** | A non-entity fact that can depend on entity facts; receives a `{entity_id => value}` hash |

## Defining facts

### Constants

```ruby
class MathFacts < FactGraph::Graph
  constant(:pi) { 3.14 }
end
```

`constant` is an alias for `fact` — use it to signal that a fact has no dependencies or inputs.

### Facts with input

Use `dry-schema` blocks to declare and validate input:

```ruby
class MathFacts < FactGraph::Graph
  fact :squared_scale do
    input :scale do
      Dry::Schema.Params do
        required(:scale).value(type?: Numeric, gteq?: 0)
      end
    end

    proc do
      data in input: { scale: }
      scale * scale
    end
  end
end
```

The fact's proc receives a `data` hash with `:input` and `:dependencies` keys. Use Ruby's pattern-matching (`in`) to destructure it.

### Facts with dependencies

Declare dependencies on other facts with `dependency`. Use `from:` to reference a fact in another module:

```ruby
class CircleFacts < FactGraph::Graph
  fact :areas do
    input :circles do
      Dry::Schema.Params do
        required(:circles).array(:hash) do
          required(:radius).value(:integer)
        end
      end
    end

    dependency :pi, from: :math_facts
    dependency :squared_scale, from: :math_facts

    proc do
      data in input: { circles: }, dependencies: { pi:, squared_scale: }
      circles.map do |circle|
        circle in radius:
        pi * radius * radius * squared_scale
      end
    end
  end
end
```

If `from:` is omitted, the dependency is assumed to be in the same module.

### Entity facts

Use `per_entity:` to evaluate a fact once per entity in a collection. Inputs for entity facts also carry `per_entity: true`:

```ruby
class ApplicantFacts < FactGraph::Graph
  fact :income, per_entity: :applicants do
    input :income, per_entity: true do
      Dry::Schema.Params do
        required(:income).value(:integer)
      end
    end

    proc do
      data[:input][:income]
    end
  end
end
```

Entity facts produce `{ entity_id => value }` results (e.g., `{ 0 => 45000, 1 => 32000 }`).

### Aggregate facts depending on entity facts

A non-entity fact can depend on an entity fact. It receives the full `{entity_id => value}` hash, with any error entries filtered out:

```ruby
fact :num_eligible_applicants do
  dependency :eligible

  proc do
    data in dependencies: { eligible: }
    eligible.values.count { |v| v == true }
  end
end
```

### Handling unmet dependencies

By default, a fact is skipped if any of its dependencies have errors. Set `allow_unmet_dependencies: true` to let the fact inspect error results and decide its own behavior:

```ruby
fact :eligible, per_entity: :applicants, allow_unmet_dependencies: true do
  dependency :income
  dependency :age

  proc do
    data in dependencies: { income:, age: }
    if income.is_a?(Integer) && income < 100
      true
    elsif (income in { fact_bad_inputs:, fact_dependency_unmet: }) ||
          (age in { fact_bad_inputs:, fact_dependency_unmet: })
      data_errors
    else
      false
    end
  end
end
```

`data_errors` returns a `{ fact_incomplete_definition: ... }` sentinel that downstream facts can detect.

`must_match` is a convenience wrapper that runs a pattern-match block and falls back to `data_errors` on `NoMatchingPatternError`:

```ruby
proc do
  must_match do
    case data
    in input: { snail_mail_opt_in: false }
      false
    end
  end
end
```

## Evaluating facts

Call `FactGraph::Evaluator.evaluate` with an input hash:

```ruby
results = FactGraph::Evaluator.evaluate({
  scale: 3,
  circles: [{ radius: 5 }, { radius: 10 }]
})
```

Results are a nested hash keyed by module name, then fact name:

```ruby
{
  math_facts: {
    pi: 3.14,
    squared_scale: 9
  },
  circle_facts: {
    areas: [706.5, 2826.0]
  }
}
```

### Error results

When input fails validation, the fact's result contains:

```ruby
{
  fact_bad_inputs: {
    [:circles, 0, :radius] => #<Set {"must be an integer"}>,
  },
  fact_dependency_unmet: {}
}
```

When a dependency has errors, the fact is skipped and its result contains:

```ruby
{
  fact_bad_inputs: {},
  fact_dependency_unmet: { circle_facts: [:areas] }
}
```

Use `FactGraph::Evaluator.input_errors(results)` to collect all `fact_bad_inputs` entries from a result set into a single hash.

## Context-specific graphs

Use `ActiveSupport::Concern` mixins and graph subclasses to compose graphs for different contexts:

```ruby
# Define shared fact groups as mixins
module Filer
  extend ActiveSupport::Concern

  included do
    in_module :filer do
      constant(:year_of_birth) { 1990 }

      fact :age do
        dependency :tax_year, from: :filing_context
        dependency :year_of_birth

        proc do
          data in { dependencies: { tax_year:, year_of_birth: } }
          tax_year - year_of_birth
        end
      end
    end
  end
end

# Define a base graph class per context
class Ty2024Graph < FactGraph::Graph; end

# Include the mixins and add context-specific constants
class TaxYear2024Specifics < Ty2024Graph
  include Filer
  include Dependent

  in_module :filing_context do
    constant(:tax_year) { 2024 }
  end
end
```

Evaluate against a specific graph class:

```ruby
results = FactGraph::Evaluator.evaluate(input, graph_class: Ty2024Graph)
```

## Querying the graph

These methods let you inspect the fact graph without evaluating it:

```ruby
# Find facts that use a specific input key path
FactGraph::Evaluator.facts_using_input([:circles, 0, :radius])

# Find facts that depend on a specific fact
FactGraph::Evaluator.facts_with_dependency(:math_facts, :pi)

# Trace which leaf (output) facts ultimately depend on a given input
FactGraph::Evaluator.leaf_facts_depending_on_input([:income])
```

All three accept optional `graph_class:` and `module_filter:` keyword arguments.

## Development

```bash
bundle install
bundle exec rspec
```

Use `bin/console` for an interactive prompt to experiment with the gem.
