require "enumerize"
require "require_all"
require "money-rails"

require_rel "ledgerizer/extensions/*.rb"
require_rel "ledgerizer/util/*.rb"
require_rel "ledgerizer/definition/*.rb"
require_rel "ledgerizer/engine.rb"
require_rel "ledgerizer/entry_executor.rb"

module Ledgerizer
  include Definition::Dsl

  def self.setup
    yield self
  end
end
