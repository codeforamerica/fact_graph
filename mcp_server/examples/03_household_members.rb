# frozen_string_literal: true

# Example 3: Per-Household-Member Eligibility with Aggregate
#
# POLICY DESCRIPTION:
# A household applies for assistance. Each household member is individually
# assessed for eligibility based on their age and citizenship status.
# The household receives benefits based on the count of eligible members.
#
# RULES:
# - Each member must be a US citizen or qualified non-citizen
# - Each member must be under 65 OR have a disability
# - Benefit amount is $200 per eligible member
#
# This example demonstrates:
# - Per-entity facts (evaluated for each household member)
# - Aggregate facts that depend on per-entity results

module Examples
  module HouseholdMembers
    POLICY_TEXT = <<~POLICY
      Each household member is individually assessed:
      - Must be a US citizen or qualified non-citizen
      - Must be under 65 years old OR have a documented disability

      Benefits:
      - $200 per month per eligible household member
    POLICY

    FACT_GRAPH_CODE = <<~RUBY
      class HouseholdFacts < FactGraph::Graph
        constant(:benefit_per_member) { 200 }

        # Per-member eligibility based on citizenship
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

        # Per-member eligibility based on age/disability
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

        # Aggregate: count of eligible members
        # Uses allow_unmet_dependencies to access per-entity results even if some fail
        fact :eligible_member_count, allow_unmet_dependencies: true do
          dependency :member_eligible

          proc do
            member_results = data[:dependencies][:member_eligible]

            # member_eligible is a hash of {entity_id => true/false/error}
            if member_results.is_a?(Hash)
              member_results.values.count { |v| v == true }
            else
              0
            end
          end
        end

        # Aggregate: total monthly benefit amount
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

    TEST_CASES = [
      {
        description: "Family with 2 eligible, 1 ineligible member",
        input: {
          members: [
            { is_citizen_or_qualified: true, age: 35, has_disability: false },  # eligible
            { is_citizen_or_qualified: true, age: 70, has_disability: true },   # eligible (has disability)
            { is_citizen_or_qualified: false, age: 40, has_disability: false }  # not eligible (citizenship)
          ]
        },
        expected: {
          household_facts: {
            citizenship_eligible: { 0 => true, 1 => true, 2 => false },
            age_eligible: { 0 => true, 1 => true, 2 => true },
            member_eligible: { 0 => true, 1 => true, 2 => false },
            eligible_member_count: 2,
            monthly_benefit: 400,
            household_eligible: true
          }
        }
      },
      {
        description: "Single elderly person without disability",
        input: {
          members: [
            { is_citizen_or_qualified: true, age: 70, has_disability: false }
          ]
        },
        expected: {
          household_facts: {
            citizenship_eligible: { 0 => true },
            age_eligible: { 0 => false },  # 70 >= 65 and no disability
            member_eligible: { 0 => false },
            eligible_member_count: 0,
            monthly_benefit: 0,
            household_eligible: false
          }
        }
      },
      {
        description: "All members eligible",
        input: {
          members: [
            { is_citizen_or_qualified: true, age: 30, has_disability: false },
            { is_citizen_or_qualified: true, age: 8, has_disability: false },
            { is_citizen_or_qualified: true, age: 5, has_disability: false }
          ]
        },
        expected: {
          household_facts: {
            member_eligible: { 0 => true, 1 => true, 2 => true },
            eligible_member_count: 3,
            monthly_benefit: 600,
            household_eligible: true
          }
        }
      }
    ]
  end
end
