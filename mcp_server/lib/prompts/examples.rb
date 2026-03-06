# frozen_string_literal: true

module Prompts
  # Few-shot examples for policy-to-code generation
  EXAMPLES = [
    {
      name: "simple_threshold",
      policy: "A person is eligible for assistance if their annual income is below $30,000.",
      analysis: <<~ANALYSIS,
        ## Module: eligibility

        ### Rule 1: income_threshold
        - Type: constant
        - Value: 30000

        ### Rule 2: eligible
        - Type: fact
        - Inputs: income (integer, >= 0)
        - Dependencies: income_threshold
        - Logic: income < income_threshold
      ANALYSIS
      code: <<~RUBY
        class EligibilityFacts < FactGraph::Graph
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
    {
      name: "multi_factor",
      policy: <<~POLICY,
        Eligibility requires:
        - Gross income at or below 130% of Federal Poverty Level (FPL)
        - Assets below $2,750 (or $4,250 if elderly/disabled)
        FPL for a single person is $1,255/month.
      POLICY
      analysis: <<~ANALYSIS,
        ## Module: snap_eligibility

        ### Rule 1: fpl_single
        - Type: constant
        - Value: 1255

        ### Rule 2: gross_income_limit_percent
        - Type: constant
        - Value: 130

        ### Rule 3: asset_limit_standard
        - Type: constant
        - Value: 2750

        ### Rule 4: asset_limit_elderly
        - Type: constant
        - Value: 4250

        ### Rule 5: income_eligible
        - Type: fact
        - Inputs: gross_income (integer, >= 0)
        - Dependencies: fpl_single, gross_income_limit_percent
        - Logic: gross_income <= (fpl_single * gross_income_limit_percent / 100)

        ### Rule 6: asset_eligible
        - Type: fact
        - Inputs: total_assets (integer, >= 0), is_elderly_or_disabled (boolean)
        - Dependencies: asset_limit_standard, asset_limit_elderly
        - Logic: total_assets < (is_elderly_or_disabled ? asset_limit_elderly : asset_limit_standard)

        ### Rule 7: eligible
        - Type: fact
        - Dependencies: income_eligible, asset_eligible
        - Logic: income_eligible AND asset_eligible
      ANALYSIS
      code: <<~RUBY
        class SnapEligibilityFacts < FactGraph::Graph
          constant(:fpl_single) { 1255 }
          constant(:gross_income_limit_percent) { 130 }
          constant(:asset_limit_standard) { 2750 }
          constant(:asset_limit_elderly) { 4250 }

          fact :income_eligible do
            input :gross_income do
              Dry::Schema.Params do
                required(:gross_income).value(:integer, gteq?: 0)
              end
            end

            dependency :fpl_single
            dependency :gross_income_limit_percent

            proc do
              data in input: { gross_income: },
                     dependencies: { fpl_single:, gross_income_limit_percent: }
              limit = (fpl_single * gross_income_limit_percent) / 100
              gross_income <= limit
            end
          end

          fact :asset_eligible do
            input :total_assets do
              Dry::Schema.Params do
                required(:total_assets).value(:integer, gteq?: 0)
              end
            end

            input :is_elderly_or_disabled do
              Dry::Schema.Params do
                required(:is_elderly_or_disabled).value(:bool)
              end
            end

            dependency :asset_limit_standard
            dependency :asset_limit_elderly

            proc do
              data in input: { total_assets:, is_elderly_or_disabled: },
                     dependencies: { asset_limit_standard:, asset_limit_elderly: }
              limit = is_elderly_or_disabled ? asset_limit_elderly : asset_limit_standard
              total_assets < limit
            end
          end

          fact :eligible do
            dependency :income_eligible
            dependency :asset_eligible

            proc do
              data in dependencies: { income_eligible:, asset_eligible: }
              income_eligible && asset_eligible
            end
          end
        end
      RUBY
    },
    {
      name: "per_entity",
      policy: <<~POLICY,
        Each household member is assessed individually:
        - Must be a US citizen
        - Must be under 65 or have a disability
        Benefits are $200 per eligible member.
      POLICY
      analysis: <<~ANALYSIS,
        ## Module: household
        ## Entity: members

        ### Rule 1: benefit_per_member
        - Type: constant
        - Value: 200

        ### Rule 2: citizenship_ok
        - Type: fact
        - Per-entity: members
        - Inputs: is_citizen (boolean, per-entity)
        - Logic: is_citizen == true

        ### Rule 3: age_ok
        - Type: fact
        - Per-entity: members
        - Inputs: age (integer, per-entity), has_disability (boolean, per-entity)
        - Logic: age < 65 OR has_disability

        ### Rule 4: member_eligible
        - Type: fact
        - Per-entity: members
        - Dependencies: citizenship_ok, age_ok
        - Logic: citizenship_ok AND age_ok

        ### Rule 5: eligible_count
        - Type: fact (aggregate)
        - Dependencies: member_eligible
        - Logic: count of members where member_eligible is true

        ### Rule 6: total_benefit
        - Type: fact
        - Dependencies: eligible_count, benefit_per_member
        - Logic: eligible_count * benefit_per_member
      ANALYSIS
      code: <<~RUBY
        class HouseholdFacts < FactGraph::Graph
          constant(:benefit_per_member) { 200 }

          fact :citizenship_ok, per_entity: :members do
            input :is_citizen, per_entity: true do
              Dry::Schema.Params do
                required(:is_citizen).value(:bool)
              end
            end

            proc do
              data in input: { is_citizen: }
              is_citizen
            end
          end

          fact :age_ok, per_entity: :members do
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

          fact :member_eligible, per_entity: :members do
            dependency :citizenship_ok
            dependency :age_ok

            proc do
              data in dependencies: { citizenship_ok:, age_ok: }
              citizenship_ok && age_ok
            end
          end

          fact :eligible_count do
            dependency :member_eligible

            proc do
              results = data[:dependencies][:member_eligible]
              results.values.count { |v| v == true }
            end
          end

          fact :total_benefit do
            dependency :eligible_count
            dependency :benefit_per_member

            proc do
              data in dependencies: { eligible_count:, benefit_per_member: }
              eligible_count * benefit_per_member
            end
          end
        end
      RUBY
    }
  ]

  # Format examples for inclusion in prompts
  def self.format_examples(count: 2)
    EXAMPLES.take(count).map do |ex|
      <<~EXAMPLE
        ---
        **Policy:** #{ex[:policy].strip}

        **Code:**
        ```ruby
        #{ex[:code].strip}
        ```
      EXAMPLE
    end.join("\n")
  end

  # Get a specific example by name
  def self.get_example(name)
    EXAMPLES.find { |ex| ex[:name] == name }
  end
end
