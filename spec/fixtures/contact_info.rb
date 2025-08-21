class ContactInfo < FactGraph::Graph
  fact :formatted_address do
    input :street_address do
      schema do
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
      data in input: { street_address: { street_number:, street_name:, city:, state:, zip_code: } }

      "#{street_number} #{street_name}, #{city}, #{state} #{zip_code}"
    end
  end
end
