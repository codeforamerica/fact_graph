class ContactInfo < FactGraph::Graph
  fact :formatted_address do
    input :street_address do
      required(:street_address).hash do
        required(:street_number).value(:integer)
        required(:street_name).value(:string)
        required(:city).value(:string)
        required(:state).value(:string)
        required(:zip_code).value(:string)
      end
    end

    proc do
      data in input: {street_address: {street_number:, street_name:, city:, state:, zip_code:}}

      "#{street_number} #{street_name}, #{city}, #{state} #{zip_code}"
    end
  end

  fact :street_number do
    input [:street_address, :street_number], value: :integer, gteq?: 0
  end

  fact :can_receive_mail, allow_unmet_dependencies: true do
    input :snail_mail_opt_in, value: :bool
    input :unused_input, value: :bool

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
