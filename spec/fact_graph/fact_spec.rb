# frozen_string_literal: true

RSpec.describe FactGraph::Fact do
  before do
    FactGraph::Graph.graph_registry = []
    load "spec/fixtures/contact_info.rb"
  end

  describe "#call" do
    let(:graph) { FactGraph::Graph.prepare_fact_objects(input) }

    context "when called with structured input that contains more fields than are required by a fact" do
      let(:input) do
        {
          street_address: {
            street_number: 1,
            street_name: "Sesame St",
            city: "New York",
            state: "New York",
            zip_code: "10123",
            county: "New York"
          }
        }
      end

      it "filters that input before passing it to #validate_input" do
        expect(graph[:contact_info][:formatted_address]).to receive(:validate_input).with(
          {
            street_address: {
              street_number: 1,
              street_name: "Sesame St",
              city: "New York",
              state: "New York",
              zip_code: "10123"
            }
          },
          {fact_bad_inputs: {}, fact_dependency_unmet: {}}
        )
        graph[:contact_info][:formatted_address].call(input, {})
      end
    end

    context "when all dependencies are satisfied" do
      let(:input) do
        {
          snail_mail_opt_in: false,
          street_address: {
            street_number: 1,
            street_name: "Sesame St",
            city: "New York",
            state: "New York",
            zip_code: "10123",
            county: "New York"
          }
        }
      end

      it "should render a good value" do
        results = {}
        graph[:contact_info][:can_receive_mail].call(input, results)
        expect(results[:contact_info][:can_receive_mail]).to eq false
      end
    end

    context "when some dependencies are unsatisfied" do
      let(:input) do
        {
          snail_mail_opt_in: false,
          street_address: {
            street_number: 1,
            street_name: "Sesame St",
            city: "New York",
            state: "New York",
            zip_code: "10123",
            county: "New York"
          }
        }
      end

      context "and the fact cannot resolve because of incomplete definition" do
        before do
          input[:snail_mail_opt_in] = true
          input[:unused_input] = true
        end

        it "should return :fact_incomplete_definition" do
          results = {}
          graph[:contact_info][:can_receive_mail].call(input, results)
          expect(results[:contact_info][:can_receive_mail]).to eq :fact_incomplete_definition
        end
      end

      context "and the fact can resolve despite the presence of data errors" do
        it "should return the appropriate value" do
          results = {}
          graph[:contact_info][:can_receive_mail].call(input, results)
          expect(results[:contact_info][:can_receive_mail]).to eq false
        end
      end
    end
  end
end
