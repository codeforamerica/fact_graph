class ApplicantFacts < FactGraph::Graph
  constant :income_threshold do
    100
  end

  constant :age_threshold do
    100
  end

  fact :income, per_entity: :applicants do
    input :income, per_entity: true do
      schema do
        required(:income).value(:integer)
      end
    end

    proc do
      data[:input][:income]
    end
  end

  fact :age, per_entity: :applicants do
    input :age, per_entity: true do
      schema do
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
    dependency :income_threshold
    dependency :age_threshold

    proc do
      data in dependencies: { income:, age:, income_threshold:, age_threshold: }
      if (income.is_a?(Integer) && income < income_threshold) ||
        (age.is_a?(Integer) && age > age_threshold)
        true
      elsif (income in { fact_bad_inputs:, fact_dependency_unmet: }) ||
        (age in { fact_bad_inputs:, fact_dependency_unmet: })
        data_errors
      else
        false
      end
    end
  end
end
