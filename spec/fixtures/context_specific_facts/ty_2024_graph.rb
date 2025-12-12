class Ty2024Graph < FactGraph::Graph; end

class TaxYear2024Specifics < Ty2024Graph
  include Filer
  include Dependent

  in_module :filing_context do
    constant(:tax_year) { 2024 }
  end
end
