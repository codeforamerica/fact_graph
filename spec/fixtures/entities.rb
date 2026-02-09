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

  fact :eligible, per_entity: :applicants, allow_unmet_dependencies: true do
    dependency :income
    dependency :age

    proc do
      data in dependencies: { income:, age: }
      if (income.is_a?(Integer) && income < 100) ||
        (age.is_a?(Integer) && age > 100)
        true
      elsif (income in { fact_bad_inputs:, fact_dependency_unmet: }) ||
        (age in { fact_bad_inputs:, fact_dependency_unmet: })
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
