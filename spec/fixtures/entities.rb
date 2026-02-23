class ApplicantFacts < FactGraph::Graph
  # This fact module shows several usage patterns:
  # 1. Per-Entity Facts, used when you have an arbitrary number of some type of input
  # 2. Allowing unmet dependencies, which is useful when a fact should be able to take a known value with only a subset
  #    of its inputs or dependencies present (such as when you want to bump someone out of a flow as soon as you can
  #    make a determination)

  constant(:age_threshold) { 100 }
  constant(:income_threshold) { 100 }

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

  fact :age, per_entity: :applicants do
    input :age, per_entity: true do
      Dry::Schema.Params do
        required(:age).value(:integer)
      end
    end

    proc do
      data[:input][:age]
    end
  end

  fact :income_under_threshold, per_entity: :applicants do
    dependency :income
    dependency :income_threshold

    proc do
      data in dependencies: {income:, income_threshold:}
      income < income_threshold
    end
  end

  fact :age_over_threshold, per_entity: :applicants do
    dependency :age
    dependency :age_threshold

    proc do
      data in dependencies: {age:, age_threshold:}
      age > age_threshold
    end
  end

  fact :eligible, per_entity: :applicants, allow_unmet_dependencies: true do
    dependency :income_under_threshold
    dependency :age_over_threshold

    proc do
      case data[:dependencies]
      in income_under_threshold: true
        true
      in age_over_threshold: true
        true
      in income: Hash
        data_errors
      in age: Hash
        data_errors
      else
        false
      end
    end
  end

  fact :num_eligible_applicants do
    dependency :eligible

    proc do
      data in dependencies: { eligible: }
      eligible.values.count { |v| v == true }
    end
  end
end
