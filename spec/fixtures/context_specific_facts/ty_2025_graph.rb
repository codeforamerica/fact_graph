class Ty2025Graph < FactGraph::Graph; end

class TaxYear2025Specifics < Ty2025Graph
  include Filer
  include Dependent

  in_module :filing_context do
    constant(:tax_year) { 2025 }
  end
end
