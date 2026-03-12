class FactGraph::FactErrors
  def initialize(fact_bad_inputs:, fact_dependency_unmet:)
    @hash = {fact_bad_inputs:, fact_dependency_unmet:}
  end

  def to_hash = @hash.dup

  delegate :==, :[], :deconstruct_keys, to: :@hash
end
