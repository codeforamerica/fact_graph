# frozen_string_literal: true

RSpec.describe FactGraph::DataContainer do
  let(:data_errors) { "I am data errors" }

  describe "#data_errors" do
    it "should return :fact_incomplete_definition when data errors is nil" do
      container = described_class.new(data_errors: nil)

      expect(container.data_errors).to eq :fact_incomplete_definition
    end

    it "should return :fact_incomplete_definition when no data errors are passed in" do
      container = described_class.new

      expect(container.data_errors).to eq :fact_incomplete_definition
    end

    it "should return data_errors when it is not nil" do
      container = described_class.new(data_errors: data_errors)

      expect(container.data_errors).to eq(data_errors)
    end
  end

  describe "#must_match" do
    it "should not raise an exception when a pattern match error is indicated" do
      container = described_class.new(data_errors: data_errors)

      expect do
        container.must_match { 5 => String }
      end.not_to raise_exception
    end

    it "should return data_errors when a pattern match error is indicated" do
      container = described_class.new(data_errors: data_errors)

      expect(container.must_match { 5 => String }).to eq(data_errors)
    end

    it "should return the value returned by the block when there are no pattern match errors" do
      container = described_class.new

      lambda_to_return_value = -> { "foo" }

      expect(container.must_match(&lambda_to_return_value)).to eq "foo"
    end

    it "should re-raise any error other than a pattern match error" do
      container = described_class.new

      expect { container.must_match { raise StandardError.new("I am a failure!") } }.to raise_exception(StandardError)
    end
  end
end
