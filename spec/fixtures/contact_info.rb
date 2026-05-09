class ContactInfo < FactGraph::Graph
  fact :formatted_address do
    input :street_address do
      Dry::Schema.Params do
        required(:street_address).hash do
          required(:street_number).value(:integer)
          required(:street_name).value(:string)
          required(:city).value(:string)
          required(:state).value(:string)
          required(:zip_code).value(:string)
        end
      end
    end

    proc do
      data in input: {street_address: {street_number:, street_name:, city:, state:, zip_code:}}

      "#{street_number} #{street_name}, #{city}, #{state} #{zip_code}"
    end
  end

  fact :can_receive_mail, allow_unmet_dependencies: true do
    input :snail_mail_opt_in do
      Dry::Schema.Params do
        required(:snail_mail_opt_in).value(:bool)
      end
    end

    input :unused_input do
      Dry::Schema.Params do
        required(:unused_input).value(:bool)
      end
    end

    dependency :formatted_address

    proc do
      must_match do
        puts "DATA IN THE FACT: #{data}"
        puts ""
        case data
        # User doesn't want snail mail so we can bomb out early
        in input: {snail_mail_opt_in: false}
          false
        # This is a purposefully under-specified fact to test DataContainer's exception handling.
        # A more realistic version of this fact would contain the following lines:

        # in dependencies: {formatted_address: Dry::Monads::Failure}
        #   false
        # in input: {snail_mail_opt_in: true}, dependencies: {formatted_address: String}
        #   true
        end
      end
    end
  end
end
