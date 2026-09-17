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

    # A failure is never a value worth rendering, so it collapses to nil under
    # Rails' `#presence` the same way `false`/`nil`/blank strings do — callers
    # that just want "a value or nothing" don't need to special-case failures.
    def blank? = true
  end
end
