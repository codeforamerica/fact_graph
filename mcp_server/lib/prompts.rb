# frozen_string_literal: true

module Prompts
  # Step 1: Analyze policy and identify rules
  ANALYZE_POLICY = <<~PROMPT
    Analyze the following policy and break it down into discrete rules that can be implemented as facts.

    For each rule identified, specify:
    1. **Name**: A short, snake_case name for the rule (e.g., `income_eligible`, `age_requirement`)
    2. **Type**: Is this a `constant` (fixed value) or `fact` (computed from inputs/dependencies)?
    3. **Inputs**: What user-provided data does this rule need? Include the data type and any constraints.
    4. **Dependencies**: Does this rule depend on the result of other rules?
    5. **Logic**: How is the result computed? Be specific about thresholds, comparisons, and formulas.
    6. **Per-entity**: Does this rule apply once, or once per item in a collection (e.g., per household member)?

    Also identify:
    - What **module name** should group these facts (e.g., `eligibility`, `benefits`, `tax_credit`)
    - What **entities** exist if rules apply per-item (e.g., `members`, `applicants`, `dependents`)

    Format your response as a structured list.

    ---
    POLICY:
    %{policy_text}
  PROMPT

  # Step 2: Generate FactGraph code
  GENERATE_CODE = <<~PROMPT
    Generate FactGraph Ruby code implementing the following rules.

    ## FactGraph DSL Quick Reference

    ```ruby
    class MyFacts < FactGraph::Graph
      # Constants (fixed values)
      constant(:threshold) { 1000 }

      # Facts with inputs and dependencies
      fact :is_eligible do
        input :income do
          Dry::Schema.Params do
            required(:income).value(:integer, gteq?: 0)
          end
        end

        dependency :threshold

        proc do
          data in input: { income: }, dependencies: { threshold: }
          income < threshold
        end
      end

      # Per-entity facts (evaluated for each item in a collection)
      fact :member_eligible, per_entity: :members do
        input :age, per_entity: true do
          Dry::Schema.Params do
            required(:age).value(:integer, gteq?: 0)
          end
        end

        proc do
          data in input: { age: }
          age >= 18
        end
      end

      # Aggregate facts that depend on per-entity results
      fact :eligible_count do
        dependency :member_eligible  # Gets hash of {entity_id => result}

        proc do
          member_results = data[:dependencies][:member_eligible]
          member_results.values.count { |v| v == true }
        end
      end
    end
    ```

    ## Input Schema Types
    - `:integer` - whole numbers
    - `:string` - text
    - `:bool` - true/false
    - `type?: Numeric` - any number (integer or float)
    - `included_in?: ["a", "b"]` - enum values
    - `gteq?: 0` - greater than or equal
    - `lteq?: 100` - less than or equal
    - `array(:hash) { ... }` - array of objects

    ## Rules to Implement

    %{rules}

    ## Requirements
    1. Define all constants first, then facts
    2. Use descriptive names matching the rule names provided
    3. Include proper input validation with Dry::Schema
    4. Use pattern matching (`data in input: {...}, dependencies: {...}`) in resolvers
    5. Handle edge cases (division by zero, nil values, etc.)
    6. Class name should be `%{module_name}Facts` (e.g., `EligibilityFacts`)

    Generate only the Ruby code, no explanations.
  PROMPT

  # Combined single-shot prompt for simpler policies
  POLICY_TO_CODE = <<~PROMPT
    Convert the following policy into FactGraph Ruby code.

    ## FactGraph DSL Reference

    FactGraph is a Ruby DSL for declarative fact computation. Facts can depend on user inputs and other facts.

    ```ruby
    class PolicyFacts < FactGraph::Graph
      # Constants - fixed values
      constant(:limit) { 1000 }

      # Facts - computed values with inputs and dependencies
      fact :check_income do
        input :income do
          Dry::Schema.Params do
            required(:income).value(:integer, gteq?: 0)
          end
        end
        dependency :limit

        proc do
          data in input: { income: }, dependencies: { limit: }
          income < limit
        end
      end

      # Per-entity facts - computed for each item in a collection
      fact :person_eligible, per_entity: :people do
        input :age, per_entity: true do
          Dry::Schema.Params { required(:age).value(:integer) }
        end
        proc do
          data in input: { age: }
          age >= 18
        end
      end

      # Aggregates - depend on per-entity results
      fact :total_eligible do
        dependency :person_eligible
        proc do
          results = data[:dependencies][:person_eligible]
          results.values.count { |v| v == true }
        end
      end
    end
    ```

    ## Input Types
    - `:integer`, `:string`, `:bool`
    - `gteq?: N`, `lteq?: N` - comparisons
    - `included_in?: [...]` - enum
    - `array(:hash) { ... }` - arrays

    ## Example

    **Policy:** "People with income under $30,000 are eligible for assistance."

    **Code:**
    ```ruby
    class AssistanceFacts < FactGraph::Graph
      constant(:income_threshold) { 30_000 }

      fact :eligible do
        input :income do
          Dry::Schema.Params { required(:income).value(:integer, gteq?: 0) }
        end
        dependency :income_threshold

        proc do
          data in input: { income: }, dependencies: { income_threshold: }
          income < income_threshold
        end
      end
    end
    ```

    ---

    **Policy to implement:**
    %{policy_text}

    Generate the FactGraph Ruby code:
  PROMPT

  # Prompt for fixing validation errors
  FIX_ERRORS = <<~PROMPT
    The following FactGraph code has validation errors. Fix the code to resolve them.

    ## Current Code
    ```ruby
    %{code}
    ```

    ## Validation Errors
    %{errors}

    ## Common Fixes
    - **Syntax errors**: Check for missing `end` keywords, unclosed strings, mismatched brackets
    - **Missing dependency**: Define the missing fact, or fix the dependency reference
    - **Invalid input schema**: Ensure Dry::Schema.Params block returns a valid schema
    - **No facts defined**: Add at least one `fact` or `constant` definition

    Generate the corrected Ruby code only, no explanations.
  PROMPT

  # Prompt for adding a new fact to existing code
  ADD_FACT = <<~PROMPT
    Add a new fact to the following FactGraph code.

    ## Existing Code
    ```ruby
    %{code}
    ```

    ## New Fact to Add
    %{fact_description}

    ## Requirements
    - Add the new fact in the appropriate position (constants first, then facts)
    - Reuse existing constants/facts as dependencies where appropriate
    - Follow the same coding style as existing code
    - Ensure proper input validation

    Generate the complete updated Ruby code:
  PROMPT

  # Helper to format rules for the GENERATE_CODE prompt
  def self.format_rules(rules)
    rules.map.with_index(1) do |rule, i|
      lines = ["### Rule #{i}: #{rule[:name]}"]
      lines << "- Type: #{rule[:type]}"
      lines << "- Inputs: #{rule[:inputs].join(', ')}" if rule[:inputs]&.any?
      lines << "- Dependencies: #{rule[:dependencies].join(', ')}" if rule[:dependencies]&.any?
      lines << "- Per-entity: #{rule[:per_entity]}" if rule[:per_entity]
      lines << "- Logic: #{rule[:logic]}"
      lines.join("\n")
    end.join("\n\n")
  end

  # Get a prompt with variables substituted
  def self.render(template, **variables)
    result = template.dup
    variables.each do |key, value|
      result.gsub!("%{#{key}}", value.to_s)
    end
    result
  end

  # MCP Prompt definitions for registration with the server
  MCP_PROMPTS = [
    {
      name: "analyze_policy",
      description: "Break down a policy into discrete rules for FactGraph implementation",
      arguments: [
        { name: "policy_text", description: "The policy text to analyze", required: true }
      ],
      template: ANALYZE_POLICY
    },
    {
      name: "generate_code",
      description: "Generate FactGraph Ruby code from analyzed rules",
      arguments: [
        { name: "rules", description: "Structured rules from policy analysis", required: true },
        { name: "module_name", description: "Name for the facts module", required: true }
      ],
      template: GENERATE_CODE
    },
    {
      name: "policy_to_code",
      description: "Convert a policy directly to FactGraph code (single-shot)",
      arguments: [
        { name: "policy_text", description: "The policy text to implement", required: true }
      ],
      template: POLICY_TO_CODE
    },
    {
      name: "fix_errors",
      description: "Fix validation errors in FactGraph code",
      arguments: [
        { name: "code", description: "The code with errors", required: true },
        { name: "errors", description: "The validation errors to fix", required: true }
      ],
      template: FIX_ERRORS
    },
    {
      name: "add_fact",
      description: "Add a new fact to existing FactGraph code",
      arguments: [
        { name: "code", description: "The existing code", required: true },
        { name: "fact_description", description: "Description of the fact to add", required: true }
      ],
      template: ADD_FACT
    }
  ]
end
