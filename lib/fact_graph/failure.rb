module FactGraph
  # The value a fact resolves to when its own inputs are invalid, or one of its
  # dependencies failed to resolve. Supports pattern matching the same way the
  # plain hash it replaces did (`in {fact_bad_inputs:, fact_dependency_unmet:}`),
  # since `Data` generates `#deconstruct_keys` for free.
  Failure = Data.define(:fact_bad_inputs, :fact_dependency_unmet) do
    def self.empty
      new(
        fact_bad_inputs: {},
        fact_dependency_unmet: Hash.new { |h, key| h[key] = [] }
      )
    end

    def any?
      fact_bad_inputs.any? || fact_dependency_unmet.any?
    end

    def [](key) = to_h[key]
  end
end
