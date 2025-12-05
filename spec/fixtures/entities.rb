class ApplicantFacts < FactGraph::Graph
  constant :income_threshold do
    100
  end

  constant :age_threshold do
    100
  end

  fact :num_applicants do
    input :applicants do
      schema do
        required(:applicants).array(:hash)
      end
    end

    proc do
      data in input: { applicants: }
      applicants.count
    end
  end

  fact :income do
    input :applicants do
      schema do
        required(:applicants).array(:hash) do
          required(:income).value(:integer)
        end
      end
    end

    proc do
      data in input: { applicants: }
      applicants.map do |applicant|
        applicant[:income]
      end
    end
  end

  fact :age do
    input :applicants do
      schema do
        required(:applicants).array(:hash) do
          required(:age).value(:integer)
        end
      end
    end

    proc do
      data in input: { applicants: }
      applicants.map do |applicant|
        applicant[:age]
      end
    end
  end

  fact :eligible, allow_unmet_dependencies: true do
    dependency :income
    dependency :age
    dependency :num_applicants
    dependency :income_threshold
    dependency :age_threshold

    proc do
      data in dependencies: { income:, age:, num_applicants:, income_threshold:, age_threshold: }
      (0...num_applicants).map do |applicant_index|
        if income[applicant_index]&.<(income_threshold) || age[applicant_index]&.>(age_threshold)
          true
        elsif (income in {fact_bad_inputs:, fact_dependency_unmet:}) ||
          (age in {fact_bad_inputs:, fact_dependency_unmet:})
          data_errors
        else
          false
        end
      end
    end
  end
end
