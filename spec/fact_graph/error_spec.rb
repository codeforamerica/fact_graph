# frozen_string_literal: true

RSpec.describe FactGraph::Error do
  subject(:error) do
    described_class.new(
      fact_bad_inputs: {[:scale] => Set.new(["must be Numeric"])},
      fact_dependency_unmet: {}
    )
  end

  describe "#blank?" do
    it "is always true, even when it carries error detail" do
      expect(error.blank?).to be true
    end
  end

  describe "#present?" do
    it "is always false" do
      expect(error.present?).to be false
    end
  end

  describe "#presence" do
    it "collapses to nil like any other blank Rails value" do
      expect(error.presence).to be_nil
    end
  end

  describe "pattern matching" do
    it "still deconstructs for callers that need the error detail" do
      error in {fact_bad_inputs:, fact_dependency_unmet:}
      expect(fact_bad_inputs).to eq({[:scale] => Set.new(["must be Numeric"])})
      expect(fact_dependency_unmet).to eq({})
    end
  end

  describe "#any?" do
    it "is false for .empty" do
      expect(described_class.empty.any?).to be false
    end

    it "is true when either error hash has entries" do
      expect(error.any?).to be true
    end
  end
end
