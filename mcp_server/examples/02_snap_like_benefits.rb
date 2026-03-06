# frozen_string_literal: true

# Example 2: SNAP-like Benefits Eligibility
#
# POLICY DESCRIPTION:
# Eligibility for food assistance is based on household income relative to
# the Federal Poverty Level (FPL), which varies by household size.
#
# RULES:
# - Gross monthly income must be at or below 130% of FPL
# - Net monthly income (after deductions) must be at or below 100% of FPL
# - Assets must be below $2,750 (or $4,250 if household includes elderly/disabled)
# - Standard deduction of $198 applies to all households
# - 20% of earned income is deducted

module Examples
  module SnapLikeBenefits
    POLICY_TEXT = <<~POLICY
      Eligibility for food assistance is based on:
      1. Gross monthly income at or below 130% of Federal Poverty Level (FPL)
      2. Net monthly income at or below 100% of FPL (after deductions)
      3. Assets below $2,750 ($4,250 if elderly/disabled member present)

      FPL by household size (monthly):
      - 1 person: $1,255
      - 2 people: $1,705
      - 3 people: $2,155
      - 4 people: $2,605
      - Each additional: +$450

      Deductions:
      - Standard deduction: $198
      - Earned income deduction: 20% of earned income
    POLICY

    FACT_GRAPH_CODE = <<~RUBY
      class SnapEligibilityFacts < FactGraph::Graph
        # Constants
        constant(:base_fpl) { 1255 }
        constant(:fpl_per_additional) { 450 }
        constant(:gross_income_limit_percent) { 130 }
        constant(:net_income_limit_percent) { 100 }
        constant(:standard_deduction) { 198 }
        constant(:earned_income_deduction_percent) { 20 }
        constant(:asset_limit_standard) { 2750 }
        constant(:asset_limit_elderly_disabled) { 4250 }

        # Calculate FPL for household size
        fact :federal_poverty_level do
          input :household_size do
            Dry::Schema.Params do
              required(:household_size).value(:integer, gteq?: 1)
            end
          end

          dependency :base_fpl
          dependency :fpl_per_additional

          proc do
            data in input: { household_size: }, dependencies: { base_fpl:, fpl_per_additional: }
            if household_size == 1
              base_fpl
            elsif household_size == 2
              1705
            elsif household_size == 3
              2155
            elsif household_size == 4
              2605
            else
              2605 + (household_size - 4) * fpl_per_additional
            end
          end
        end

        # Gross income test (130% FPL)
        fact :gross_income_eligible do
          input :gross_monthly_income do
            Dry::Schema.Params do
              required(:gross_monthly_income).value(:integer, gteq?: 0)
            end
          end

          dependency :federal_poverty_level
          dependency :gross_income_limit_percent

          proc do
            data in input: { gross_monthly_income: },
                   dependencies: { federal_poverty_level:, gross_income_limit_percent: }
            limit = (federal_poverty_level * gross_income_limit_percent) / 100
            gross_monthly_income <= limit
          end
        end

        # Calculate net income
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
          dependency :federal_poverty_level
          dependency :net_income_limit_percent

          proc do
            data in dependencies: { net_monthly_income:, federal_poverty_level:, net_income_limit_percent: }
            limit = (federal_poverty_level * net_income_limit_percent) / 100
            net_monthly_income <= limit
          end
        end

        # Asset test
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

        # Final eligibility
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

    TEST_CASES = [
      {
        description: "Low-income single person, eligible",
        input: {
          household_size: 1,
          gross_monthly_income: 1000,
          earned_income: 800,
          total_assets: 500,
          has_elderly_or_disabled: false
        },
        expected: {
          snap_eligibility_facts: {
            federal_poverty_level: 1255,
            gross_income_eligible: true,
            net_monthly_income: 642,  # 1000 - 198 - (800 * 0.20)
            net_income_eligible: true,
            asset_eligible: true,
            eligible: true
          }
        }
      },
      {
        description: "Family of 4, income too high",
        input: {
          household_size: 4,
          gross_monthly_income: 4000,
          earned_income: 3500,
          total_assets: 1000,
          has_elderly_or_disabled: false
        },
        expected: {
          snap_eligibility_facts: {
            federal_poverty_level: 2605,
            gross_income_eligible: false,  # 4000 > 2605 * 1.30 = 3386
            eligible: false
          }
        }
      },
      {
        description: "Elderly person with higher asset limit",
        input: {
          household_size: 1,
          gross_monthly_income: 1200,
          earned_income: 0,
          total_assets: 3000,
          has_elderly_or_disabled: true
        },
        expected: {
          snap_eligibility_facts: {
            asset_eligible: true,  # 3000 < 4250
            eligible: true
          }
        }
      }
    ]
  end
end
