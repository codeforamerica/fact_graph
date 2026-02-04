# frozen_string_literal: true

module Resources
  STATIC_RESOURCES = [
    MCP::Resource.new(
      uri: "factgraph://docs/dsl",
      name: "dsl_documentation",
      description: "Complete FactGraph DSL reference documentation with examples",
      mime_type: "text/markdown"
    ),
    MCP::Resource.new(
      uri: "factgraph://examples",
      name: "examples_index",
      description: "Index of all available FactGraph examples",
      mime_type: "application/json"
    )
  ]

  DYNAMIC_RESOURCES = [
    MCP::Resource.new(
      uri: "factgraph://current/facts",
      name: "current_facts",
      description: "List of all facts currently defined in the graph",
      mime_type: "application/json"
    ),
    MCP::Resource.new(
      uri: "factgraph://current/modules",
      name: "current_modules",
      description: "List of modules in the current graph with their fact counts",
      mime_type: "application/json"
    )
  ]

  TEMPLATES = [
    MCP::ResourceTemplate.new(
      uri_template: "factgraph://current/facts/{name}",
      name: "fact_detail",
      description: "Details of a specific fact by name",
      mime_type: "application/json"
    ),
    MCP::ResourceTemplate.new(
      uri_template: "factgraph://examples/{name}",
      name: "example",
      description: "A specific example (simple_income, snap_benefits, household_members, tax_credit, progressive_screening)",
      mime_type: "text/markdown"
    )
  ]

  EXAMPLES = {
    "simple_income" => {
      title: "Simple Income Threshold",
      description: "Basic eligibility based on income threshold",
      patterns: ["constants", "single input", "simple comparison"],
      policy: "A person is eligible for assistance if their annual income is below $30,000.",
      code: <<~RUBY
        class SimpleEligibilityFacts < FactGraph::Graph
          constant(:income_threshold) { 30_000 }

          fact :eligible do
            input :income do
              Dry::Schema.Params do
                required(:income).value(:integer, gteq?: 0)
              end
            end

            dependency :income_threshold

            proc do
              data in input: { income: }, dependencies: { income_threshold: }
              income < income_threshold
            end
          end
        end
      RUBY
    },
    "snap_benefits" => {
      title: "SNAP-like Benefits Eligibility",
      description: "Multi-factor eligibility with income limits, deductions, and asset tests",
      patterns: ["multiple constants", "chained dependencies", "conditional logic", "calculations"],
      policy: <<~POLICY,
        Eligibility for food assistance is based on:
        1. Gross monthly income at or below 130% of Federal Poverty Level (FPL)
        2. Net monthly income at or below 100% of FPL (after deductions)
        3. Assets below $2,750 ($4,250 if elderly/disabled member present)

        FPL for single person: $1,255/month
        Deductions: $198 standard + 20% of earned income
      POLICY
      code: <<~RUBY
        class SnapEligibilityFacts < FactGraph::Graph
          # Constants
          constant(:base_fpl) { 1255 }
          constant(:gross_income_limit_percent) { 130 }
          constant(:net_income_limit_percent) { 100 }
          constant(:standard_deduction) { 198 }
          constant(:earned_income_deduction_percent) { 20 }
          constant(:asset_limit_standard) { 2750 }
          constant(:asset_limit_elderly_disabled) { 4250 }

          # Gross income test (130% FPL)
          fact :gross_income_eligible do
            input :gross_monthly_income do
              Dry::Schema.Params do
                required(:gross_monthly_income).value(:integer, gteq?: 0)
              end
            end

            dependency :base_fpl
            dependency :gross_income_limit_percent

            proc do
              data in input: { gross_monthly_income: },
                     dependencies: { base_fpl:, gross_income_limit_percent: }
              limit = (base_fpl * gross_income_limit_percent) / 100
              gross_monthly_income <= limit
            end
          end

          # Calculate net income after deductions
          fact :net_monthly_income do
            input :gross_monthly_income do
              Dry::Schema.Params do
                required(:gross_monthly_income).value(:integer, gteq?: 0)
              end
            end

            input :earned_income do
              Dry::Schema.Params do
                required(:earned_income).value(:integer, gteq?: 0)
              end
            end

            dependency :standard_deduction
            dependency :earned_income_deduction_percent

            proc do
              data in input: { gross_monthly_income:, earned_income: },
                     dependencies: { standard_deduction:, earned_income_deduction_percent: }
              earned_deduction = (earned_income * earned_income_deduction_percent) / 100
              [gross_monthly_income - standard_deduction - earned_deduction, 0].max
            end
          end

          # Net income test (100% FPL)
          fact :net_income_eligible do
            dependency :net_monthly_income
            dependency :base_fpl
            dependency :net_income_limit_percent

            proc do
              data in dependencies: { net_monthly_income:, base_fpl:, net_income_limit_percent: }
              limit = (base_fpl * net_income_limit_percent) / 100
              net_monthly_income <= limit
            end
          end

          # Asset test with conditional limit
          fact :asset_eligible do
            input :total_assets do
              Dry::Schema.Params do
                required(:total_assets).value(:integer, gteq?: 0)
              end
            end

            input :has_elderly_or_disabled do
              Dry::Schema.Params do
                required(:has_elderly_or_disabled).value(:bool)
              end
            end

            dependency :asset_limit_standard
            dependency :asset_limit_elderly_disabled

            proc do
              data in input: { total_assets:, has_elderly_or_disabled: },
                     dependencies: { asset_limit_standard:, asset_limit_elderly_disabled: }
              limit = has_elderly_or_disabled ? asset_limit_elderly_disabled : asset_limit_standard
              total_assets < limit
            end
          end

          # Final eligibility combines all tests
          fact :eligible do
            dependency :gross_income_eligible
            dependency :net_income_eligible
            dependency :asset_eligible

            proc do
              data in dependencies: { gross_income_eligible:, net_income_eligible:, asset_eligible: }
              gross_income_eligible && net_income_eligible && asset_eligible
            end
          end
        end
      RUBY
    },
    "household_members" => {
      title: "Per-Household-Member Eligibility",
      description: "Per-entity facts with aggregation",
      patterns: ["per_entity facts", "aggregate from per-entity", "entity dependencies"],
      policy: <<~POLICY,
        Each household member is individually assessed:
        - Must be a US citizen or qualified non-citizen
        - Must be under 65 years old OR have a documented disability

        Benefits: $200 per month per eligible household member
      POLICY
      code: <<~RUBY
        class HouseholdFacts < FactGraph::Graph
          constant(:benefit_per_member) { 200 }

          # Per-member citizenship check
          fact :citizenship_eligible, per_entity: :members do
            input :is_citizen_or_qualified, per_entity: true do
              Dry::Schema.Params do
                required(:is_citizen_or_qualified).value(:bool)
              end
            end

            proc do
              data in input: { is_citizen_or_qualified: }
              is_citizen_or_qualified
            end
          end

          # Per-member age/disability check
          fact :age_eligible, per_entity: :members do
            input :age, per_entity: true do
              Dry::Schema.Params do
                required(:age).value(:integer, gteq?: 0)
              end
            end

            input :has_disability, per_entity: true do
              Dry::Schema.Params do
                required(:has_disability).value(:bool)
              end
            end

            proc do
              data in input: { age:, has_disability: }
              age < 65 || has_disability
            end
          end

          # Combined per-member eligibility
          fact :member_eligible, per_entity: :members do
            dependency :citizenship_eligible
            dependency :age_eligible

            proc do
              data in dependencies: { citizenship_eligible:, age_eligible: }
              citizenship_eligible && age_eligible
            end
          end

          # Aggregate: count eligible members
          fact :eligible_member_count do
            dependency :member_eligible

            proc do
              member_results = data[:dependencies][:member_eligible]
              member_results.values.count { |v| v == true }
            end
          end

          # Aggregate: total monthly benefit
          fact :monthly_benefit do
            dependency :eligible_member_count
            dependency :benefit_per_member

            proc do
              data in dependencies: { eligible_member_count:, benefit_per_member: }
              eligible_member_count * benefit_per_member
            end
          end

          # Aggregate: household has at least one eligible member
          fact :household_eligible do
            dependency :eligible_member_count

            proc do
              data in dependencies: { eligible_member_count: }
              eligible_member_count > 0
            end
          end
        end
      RUBY
    },
    "tax_credit" => {
      title: "Tax Credit with Phase-out",
      description: "Credit calculation with phase-in, plateau, and phase-out ranges",
      patterns: ["conditional thresholds", "phase calculations", "min/max clamping"],
      policy: <<~POLICY,
        Refundable tax credit for workers:

        Single filers:
        - Phase-in: 34% of earned income up to $10,000 (max credit $3,400)
        - Plateau: Full $3,400 credit for income $10,000-$15,000
        - Phase-out: Reduces by 16% of income over $15,000
        - Fully phased out at $36,250

        Married filing jointly:
        - Same phase-in and plateau
        - Phase-out begins at $20,000 instead of $15,000
      POLICY
      code: <<~RUBY
        class TaxCreditFacts < FactGraph::Graph
          # Constants
          constant(:phase_in_rate) { 34 }
          constant(:phase_in_end) { 10_000 }
          constant(:max_credit) { 3_400 }
          constant(:phase_out_rate) { 16 }
          constant(:phase_out_start_single) { 15_000 }
          constant(:phase_out_start_married) { 20_000 }

          # Determine phase-out start based on filing status
          fact :phase_out_start do
            input :filing_status do
              Dry::Schema.Params do
                required(:filing_status).value(:string, included_in?: ["single", "married"])
              end
            end

            dependency :phase_out_start_single
            dependency :phase_out_start_married

            proc do
              data in input: { filing_status: },
                     dependencies: { phase_out_start_single:, phase_out_start_married: }
              filing_status == "married" ? phase_out_start_married : phase_out_start_single
            end
          end

          # Calculate phase-in credit amount
          fact :phase_in_credit do
            input :earned_income do
              Dry::Schema.Params do
                required(:earned_income).value(:integer, gteq?: 0)
              end
            end

            dependency :phase_in_rate
            dependency :phase_in_end
            dependency :max_credit

            proc do
              data in input: { earned_income: },
                     dependencies: { phase_in_rate:, phase_in_end:, max_credit: }
              income_for_phase_in = [earned_income, phase_in_end].min
              [(income_for_phase_in * phase_in_rate) / 100, max_credit].min
            end
          end

          # Calculate phase-out reduction
          fact :phase_out_reduction do
            input :earned_income do
              Dry::Schema.Params do
                required(:earned_income).value(:integer, gteq?: 0)
              end
            end

            dependency :phase_out_start
            dependency :phase_out_rate

            proc do
              data in input: { earned_income: },
                     dependencies: { phase_out_start:, phase_out_rate: }
              if earned_income <= phase_out_start
                0
              else
                ((earned_income - phase_out_start) * phase_out_rate) / 100
              end
            end
          end

          # Final credit amount
          fact :credit_amount do
            dependency :phase_in_credit
            dependency :phase_out_reduction

            proc do
              data in dependencies: { phase_in_credit:, phase_out_reduction: }
              [phase_in_credit - phase_out_reduction, 0].max
            end
          end

          # Whether any credit is available
          fact :eligible_for_credit do
            dependency :credit_amount

            proc do
              data in dependencies: { credit_amount: }
              credit_amount > 0
            end
          end
        end
      RUBY
    },
    "progressive_screening" => {
      title: "Progressive Screening with allow_unmet_dependencies",
      description: "Early eligibility screening that short-circuits when ineligibility is determined",
      patterns: ["allow_unmet_dependencies", "short-circuit evaluation", "progressive data collection", "error handling"],
      policy: <<~POLICY,
        Benefits screening with progressive data collection:

        Phase 1 - Income screening:
        - If gross income exceeds 200% FPL, immediately ineligible
        - No need to collect additional details

        Phase 2 - Per-member data (only if income-eligible):
        - Collect age and citizenship for each member
        - Members can be individually ineligible without blocking others

        This demonstrates:
        - `allow_unmet_dependencies: true` parameter on fact definition
        - Checking for error hashes in resolver: `value in { fact_bad_inputs:, fact_dependency_unmet: }`
        - Returning `data_errors` to propagate errors when needed
        - Short-circuiting to avoid unnecessary data collection
      POLICY
      code: <<~RUBY
        class ProgressiveScreeningFacts < FactGraph::Graph
          constant(:income_limit_percentage) { 200 }
          constant(:fpl_single) { 1255 }

          # Phase 1: Quick income screen
          fact :income_eligible do
            input :gross_monthly_income do
              Dry::Schema.Params { required(:gross_monthly_income).value(:integer, gteq?: 0) }
            end

            input :household_size do
              Dry::Schema.Params { required(:household_size).value(:integer, gteq?: 1) }
            end

            dependency :fpl_single
            dependency :income_limit_percentage

            proc do
              data in input: { gross_monthly_income:, household_size: },
                     dependencies: { fpl_single:, income_limit_percentage: }
              # Simplified FPL calculation
              fpl = fpl_single + ((household_size - 1) * 450)
              limit = (fpl * income_limit_percentage) / 100
              gross_monthly_income <= limit
            end
          end

          # Per-member age input (only collected if income_eligible)
          fact :age, per_entity: :members do
            input :age, per_entity: true do
              Dry::Schema.Params { required(:age).value(:integer, gteq?: 0) }
            end

            proc { data[:input][:age] }
          end

          # Per-member citizenship input
          fact :is_citizen, per_entity: :members do
            input :is_citizen, per_entity: true do
              Dry::Schema.Params { required(:is_citizen).value(:bool) }
            end

            proc { data[:input][:is_citizen] }
          end

          # Per-member eligibility - uses allow_unmet_dependencies for short-circuit
          fact :member_eligible, per_entity: :members, allow_unmet_dependencies: true do
            dependency :age
            dependency :is_citizen

            proc do
              data in dependencies: { age:, is_citizen: }

              # Check if dependencies have errors (missing input)
              age_error = age in { fact_bad_inputs:, fact_dependency_unmet: }
              citizen_error = is_citizen in { fact_bad_inputs:, fact_dependency_unmet: }

              # Can short-circuit on citizenship alone
              if is_citizen == false
                false  # Definitely ineligible, don't need age
              elsif age.is_a?(Integer) && age >= 65
                false  # Definitely ineligible (for this example)
              elsif age_error || citizen_error
                data_errors  # Still need more data
              else
                true  # All criteria met
              end
            end
          end

          # Aggregate: count eligible members
          # Uses allow_unmet_dependencies to handle partial per-entity results
          fact :eligible_member_count, allow_unmet_dependencies: true do
            dependency :member_eligible

            proc do
              member_results = data[:dependencies][:member_eligible]

              # member_eligible is a hash of {entity_id => true/false/error_hash}
              if member_results.is_a?(Hash)
                member_results.values.count { |v| v == true }
              else
                0
              end
            end
          end

          # Final eligibility combines income check and member count
          fact :household_eligible, allow_unmet_dependencies: true do
            dependency :income_eligible
            dependency :eligible_member_count

            proc do
              data in dependencies: { income_eligible:, eligible_member_count: }

              # Check for errors
              income_error = income_eligible in { fact_bad_inputs:, fact_dependency_unmet: }
              count_error = eligible_member_count in { fact_bad_inputs:, fact_dependency_unmet: }

              # Short-circuit: if income ineligible, done
              if income_eligible == false
                false
              elsif income_error
                data_errors  # Need income data first
              elsif eligible_member_count.is_a?(Integer) && eligible_member_count > 0
                true  # At least one eligible member
              elsif count_error
                data_errors  # Need member data
              else
                false  # No eligible members
              end
            end
          end
        end
      RUBY
    }
  }

  def self.all_resources
    STATIC_RESOURCES + DYNAMIC_RESOURCES
  end

  def self.read(uri, graph_state)
    case uri
    when "factgraph://docs/dsl"
      read_dsl_docs
    when "factgraph://examples"
      read_examples_index
    when %r{^factgraph://examples/(.+)$}
      read_example($1)
    when "factgraph://current/facts"
      read_current_facts(graph_state)
    when "factgraph://current/modules"
      read_current_modules(graph_state)
    when %r{^factgraph://current/facts/(.+)$}
      read_fact_detail($1, graph_state)
    else
      nil
    end
  end

  def self.read_dsl_docs
    MCP::Resource::TextContents.new(
      uri: "factgraph://docs/dsl",
      mime_type: "text/markdown",
      text: DSL_DOCS
    )
  end

  def self.read_examples_index
    index = EXAMPLES.map do |key, ex|
      {
        name: key,
        title: ex[:title],
        description: ex[:description],
        patterns: ex[:patterns],
        uri: "factgraph://examples/#{key}"
      }
    end

    MCP::Resource::TextContents.new(
      uri: "factgraph://examples",
      mime_type: "application/json",
      text: JSON.pretty_generate(index)
    )
  end

  def self.read_example(name)
    example = EXAMPLES[name]
    return nil unless example

    content = <<~MARKDOWN
      # #{example[:title]}

      #{example[:description]}

      **Patterns demonstrated:** #{example[:patterns].join(", ")}

      ## Policy

      #{example[:policy]}

      ## Implementation

      ```ruby
      #{example[:code]}
      ```
    MARKDOWN

    MCP::Resource::TextContents.new(
      uri: "factgraph://examples/#{name}",
      mime_type: "text/markdown",
      text: content
    )
  end

  def self.read_current_facts(graph_state)
    facts_summary = graph_state.facts.map do |fact|
      {
        name: fact[:name],
        module: fact[:module_name],
        type: fact[:constant_value] ? "constant" : "fact",
        per_entity: fact[:per_entity],
        dependencies: (fact[:dependencies] || []).map { |d| d[:name] },
        inputs: (fact[:inputs] || []).map { |i| i[:name] }
      }
    end

    MCP::Resource::TextContents.new(
      uri: "factgraph://current/facts",
      mime_type: "application/json",
      text: JSON.pretty_generate(facts_summary)
    )
  end

  def self.read_current_modules(graph_state)
    modules_summary = graph_state.modules.map do |mod_name|
      facts = graph_state.facts_in_module(mod_name)
      {
        name: mod_name,
        fact_count: facts.count,
        facts: facts.map { |f| f[:name] }
      }
    end

    MCP::Resource::TextContents.new(
      uri: "factgraph://current/modules",
      mime_type: "application/json",
      text: JSON.pretty_generate(modules_summary)
    )
  end

  def self.read_fact_detail(name, graph_state)
    fact = graph_state.get_fact(name)
    return nil unless fact

    MCP::Resource::TextContents.new(
      uri: "factgraph://current/facts/#{name}",
      mime_type: "application/json",
      text: JSON.pretty_generate(fact)
    )
  end

  DSL_DOCS = <<~MARKDOWN
    # FactGraph DSL Reference

    FactGraph is a Ruby DSL for declarative fact computation with dependency resolution and input validation. Use it to implement policy rules as composable, testable facts.

    ## Quick Start

    ```ruby
    class EligibilityFacts < FactGraph::Graph
      constant(:income_limit) { 30_000 }

      fact :eligible do
        input :income do
          Dry::Schema.Params { required(:income).value(:integer, gteq?: 0) }
        end
        dependency :income_limit

        proc do
          data in input: { income: }, dependencies: { income_limit: }
          income < income_limit
        end
      end
    end

    # Evaluate
    results = FactGraph::Evaluator.evaluate({ income: 25000 }, graph_class: FactGraph::Graph)
    # => { eligibility_facts: { income_limit: 30000, eligible: true } }
    ```

    ## Core Concepts

    ### Graph Classes

    Each `FactGraph::Graph` subclass defines a module of related facts. The module name is derived from the class name (or overridden with `in_module`):
    - `EligibilityFacts` → `:eligibility_facts`
    - `SnapBenefits` → `:snap_benefits`

    **Important:** Facts are registered on the **parent class's** `graph_registry`, not the defining class:

    ```ruby
    class MyFacts < FactGraph::Graph
      fact :foo do ... end  # Registered on FactGraph::Graph.graph_registry
    end

    # Evaluate using the parent class:
    FactGraph::Evaluator.evaluate(input, graph_class: FactGraph::Graph)
    ```

    This enables multiple Graph subclasses to share facts while having context-specific differences. Use intermediate classes and mixins for separate registries.

    ### Constants

    Fixed values that don't depend on input:

    ```ruby
    constant(:poverty_line) { 15000 }
    constant(:max_age) { 65 }
    constant(:benefit_rate) { 0.34 }
    ```

    ### Facts

    Computed values with inputs and/or dependencies:

    ```ruby
    fact :is_eligible do
      # 1. Declare inputs with validation
      input :income do
        Dry::Schema.Params { required(:income).value(:integer, gteq?: 0) }
      end

      # 2. Declare dependencies on other facts
      dependency :poverty_line

      # 3. Resolver proc computes the result
      proc do
        data in input: { income: }, dependencies: { poverty_line: }
        income < poverty_line
      end
    end
    ```

    ## Input Validation

    Inputs use [Dry::Schema](https://dry-rb.org/gems/dry-schema/) for validation:

    ```ruby
    input :applicant do
      Dry::Schema.Params do
        required(:name).value(:string)
        required(:age).value(:integer, gteq?: 0, lteq?: 120)
        required(:income).value(:integer, gteq?: 0)
        optional(:email).value(:string)
        required(:filing_status).value(:string, included_in?: ["single", "married", "head_of_household"])
      end
    end
    ```

    **Common type validations:**
    | Type | Example |
    |------|---------|
    | Integer | `value(:integer)` |
    | String | `value(:string)` |
    | Boolean | `value(:bool)` |
    | Numeric | `value(type?: Numeric)` |
    | Enum | `value(:string, included_in?: ["a", "b"])` |
    | Range | `value(:integer, gteq?: 0, lteq?: 100)` |
    | Array of hashes | `array(:hash) { required(:name).value(:string) }` |

    ## Dependencies

    Facts can depend on other facts in the same or different modules:

    ```ruby
    # Same module (inferred from class name)
    dependency :income_limit

    # Different module
    dependency :federal_poverty_level, from: :government_facts
    ```

    Dependencies are resolved automatically - you just declare what you need.

    ## Resolver Patterns

    ### Pattern Matching (Recommended)

    ```ruby
    proc do
      data in input: { income:, age: }, dependencies: { limit: }
      income < limit && age >= 18
    end
    ```

    ### Hash Access

    ```ruby
    proc do
      income = data[:input][:income]
      limit = data[:dependencies][:limit]
      income < limit
    end
    ```

    ### Calculations

    ```ruby
    proc do
      data in input: { gross_income:, deductions: }, dependencies: { rate: }
      net = gross_income - deductions
      (net * rate) / 100
    end
    ```

    ### Conditional Logic

    ```ruby
    proc do
      data in input: { filing_status: }, dependencies: { single_limit:, married_limit: }
      filing_status == "married" ? married_limit : single_limit
    end
    ```

    ### Clamping Values

    ```ruby
    proc do
      data in input: { income: }, dependencies: { max_credit: }
      calculated = income * 0.34
      [calculated, max_credit].min  # Cap at max
      [calculated, 0].max           # Floor at 0
    end
    ```

    ## Per-Entity Facts

    Compute facts for each item in a collection (e.g., household members):

    ```ruby
    fact :member_eligible, per_entity: :members do
      input :age, per_entity: true do
        Dry::Schema.Params { required(:age).value(:integer) }
      end

      proc do
        data in input: { age: }
        age >= 18
      end
    end
    ```

    **Input structure:**
    ```ruby
    {
      members: [
        { age: 35 },
        { age: 12 },
        { age: 67 }
      ]
    }
    ```

    **Result structure:**
    ```ruby
    {
      my_facts: {
        member_eligible: { 0 => true, 1 => false, 2 => true }
      }
    }
    ```

    ### Aggregating Per-Entity Results

    Create a regular fact that depends on a per-entity fact to aggregate:

    ```ruby
    fact :eligible_count do
      dependency :member_eligible  # Gets { 0 => true, 1 => false, ... }

      proc do
        results = data[:dependencies][:member_eligible]
        results.values.count { |v| v == true }
      end
    end

    fact :total_benefit do
      dependency :eligible_count
      dependency :benefit_per_person

      proc do
        data in dependencies: { eligible_count:, benefit_per_person: }
        eligible_count * benefit_per_person
      end
    end
    ```

    ## Error Handling

    When inputs are invalid or dependencies fail, facts return error hashes instead of values:

    ```ruby
    {
      fact_bad_inputs: {
        [:income] => Set.new(["must be an integer"])
      },
      fact_dependency_unmet: {
        other_module: [:failed_fact]
      }
    }
    ```

    ### Partial Evaluation with `allow_unmet_dependencies`

    By default, if any input fails validation or any dependency returns an error, the resolver proc does NOT run - the fact returns an error hash instead.

    Use `allow_unmet_dependencies: true` as a **parameter to the fact** (not a method call) to make the resolver run even with errors:

    ```ruby
    fact :early_eligibility_check, allow_unmet_dependencies: true do
      dependency :income
      dependency :age

      proc do
        data in dependencies: { income:, age: }

        # Check if dependencies are error hashes using pattern matching
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

    **Key behaviors:**
    - **Error detection**: Check if a value is an error with: `value in { fact_bad_inputs:, fact_dependency_unmet: }`
    - **Error propagation**: Return `data_errors` from the resolver to propagate errors to dependent facts
    - **Short-circuit evaluation**: Return a definite result (true/false) when you have enough info, even if other inputs are missing

    **Use cases:**
    - Progressive data collection (determine ineligibility early without collecting all data)
    - Aggregating per-entity results where some entities may have errors
    - Short-circuit evaluation to avoid unnecessary questions

    ## Complete Examples

    See these resources for full working examples:
    - `factgraph://examples/simple_income` - Basic threshold check
    - `factgraph://examples/snap_benefits` - Multi-factor eligibility
    - `factgraph://examples/household_members` - Per-entity with aggregation
    - `factgraph://examples/tax_credit` - Phase-in/phase-out calculations
    - `factgraph://examples/progressive_screening` - Short-circuit evaluation with `allow_unmet_dependencies`

    ## Best Practices

    1. **Name facts descriptively** - `income_eligible` not `check1`
    2. **Use constants for thresholds** - Makes policy changes easy
    3. **Keep resolvers simple** - One computation per fact
    4. **Chain dependencies** - Build complex logic from simple facts
    5. **Validate inputs strictly** - Catch bad data early
    6. **Use pattern matching** - More readable than hash access
  MARKDOWN
end
