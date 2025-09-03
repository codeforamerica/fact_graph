# frozen_string_literal: true

RSpec.describe FactGraph::DataContainer do
  let(:test_lambda) do
    -> { "I am a test lambda" }
  end

  describe "#data_errors" do
    it "should call the proc passed" do
      expect(test_lambda).to receive(:call).once

      container = described_class.new(data_errors: test_lambda)

      container.data_errors
    end

    it "should return :fact_incomplete_definition when the lambda return value is nil" do
      container = described_class.new(data_errors: -> {})

      expect(container.data_errors).to eq :fact_incomplete_definition
    end

    it "should return :fact_incomplete_definition when no lambda is passed in" do
      container = described_class.new

      expect(container.data_errors).to eq :fact_incomplete_definition
    end

    it "should return the value from the proc when the value is not nil" do
      container = described_class.new(data_errors: test_lambda)

      expect(container.data_errors).to eq("I am a test lambda")
    end
  end

  describe "#must_match" do
    it "should call data_errors when a pattern match error is indicated" do
      container = described_class.new(data_errors: test_lambda)

      expect(test_lambda).to receive(:call).once

      expect do
        container.must_match { 5 => String }
      end.not_to raise_exception
    end

    it "should return the value returned by the block when there are no pattern match errors" do
      container = described_class.new

      lambda_to_return_value = -> { "foo" }

      expect(container.must_match(&lambda_to_return_value)).to eq "foo"
    end

    it "should raise any error other than a pattern match error" do
      container = described_class.new

      expect { container.must_match { raise StandardError.new("I am a failure!") } }.to raise_exception(StandardError)
    end
  end
end
