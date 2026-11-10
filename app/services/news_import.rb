# frozen_string_literal: true

# The News Import (GLOSSARY.md, "News Hub"; spec #355, ticket #359): the
# one-time move of the Game News Archive's messages into the News Hub as
# imported News Items, hidden until staff assign their News Categories.
module NewsImport
  # Counts of imported News Items: sorted (with a News Category), unsorted,
  # and removed by staff with `skip`.
  def self.status
    counts = NewsItem.imported.group(Arel.sql("category_key IS NOT NULL")).count
    { sorted: counts.fetch(true, 0), unsorted: counts.fetch(false, 0), removed: NewsImportRemoval.count }
  end
end
