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
        case data
        # User doesn't want snail mail so we can bomb out early
        in input: {snail_mail_opt_in: false}
          false
          # You might imagine that we are checking that the address actually
          # exists and can be mailed to
          # in dependencies: {formatted_address: String}
        end
      end
    end
  end
end
