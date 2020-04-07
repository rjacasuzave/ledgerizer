module Ledgerizer
  class EntryExecutor
    include Ledgerizer::Validators
    include Ledgerizer::Formatters

    delegate :new_movements, to: :executable_entry, prefix: false

    def initialize(config:, tenant:, document:, entry_code:, entry_date:)
      tenant_definition = get_tenant_definition!(config, tenant)
      @tenant = tenant
      @executable_entry = Ledgerizer::Execution::Entry.new(
        document: document,
        entry_definition: get_entry_definition!(tenant_definition, entry_code),
        entry_date: entry_date
      )
    end

    def add_movement(movement_type:, account_name:, accountable:, amount:)
      executable_entry.add_new_movement(
        movement_type: movement_type,
        account_name: account_name,
        accountable: accountable,
        amount: amount
      )
    end

    def execute
      validate_existent_movements!
      validate_zero_trial_balance!(executable_entry.new_movements)
      entry = find_or_initialize_entry

      ActiveRecord::Base.transaction do
        if entry.persisted?
          update_old_entries(entry)
        else
          create_new_entry(entry, executable_entry.new_movements)
        end
      end

      true
    end

    private

    attr_reader :executable_entry, :tenant

    def find_or_initialize_entry
      entry_data = {
        code: executable_entry.code,
        document: executable_entry.document
      }

      entries = tenant.entries
      entry = entries.where(entry_data).order(:created_at).last
      return entry if entry

      entries.build(entry_data)
    end

    def update_old_entries(entry)
      adjusted_movements = get_adjusted_movements(entry)
      return if adjusted_movements.none?

      validate_zero_trial_balance!(adjusted_movements)
      validate_adjustment_date_greater_than_old_entry_date!(entry)
      adjustment_entry = entry.dup
      create_new_entry(adjustment_entry, adjusted_movements)
    end

    def get_adjusted_movements(entry)
      executable_entry.old_movements(entry).inject([]) do |result, old_movement|
        adjusted_movement = adjust_old_movement(old_movement)
        result << adjusted_movement if adjusted_movement
        result
      end + executable_entry.new_movements
    end

    def create_new_entry(entry, movements)
      entry.entry_date = executable_entry.entry_date
      entry.save!
      movements.each { |movement| entry.create_line!(movement) }
    end

    def adjust_old_movement(old_movement)
      new_movement = get_new_from_old_movement(old_movement)
      old_amount = old_movement.amount
      new_amount = new_movement&.amount || 0
      diff = new_amount - old_amount
      return if diff.zero?

      old_movement.amount = diff
      old_movement
    end

    def get_new_from_old_movement(old_movement)
      found = executable_entry.new_movements.find { |new_movement| old_movement == new_movement }
      return unless found

      executable_entry.new_movements.delete(found)
    end

    def get_tenant_definition!(config, tenant)
      validate_active_record_instance!(tenant, "tenant")
      tenant_definition = config.find_tenant(tenant)
      return tenant_definition if tenant_definition

      raise_error("can't find tenant for given #{tenant.model_name} model")
    end

    def get_entry_definition!(tenant_definition, entry_code)
      code = format_to_symbol_identifier(entry_code)
      entry_definition = tenant_definition.find_entry(code)
      return entry_definition if entry_definition

      raise_error("invalid entry code #{entry_code} for given tenant")
    end

    def validate_existent_movements!
      raise_error("can't execute entry without movements") if executable_entry.new_movements.none?
    end

    def validate_adjustment_date_greater_than_old_entry_date!(entry)
      if entry.entry_date > executable_entry.entry_date
        raise_error(
          "adjustment date (#{executable_entry.entry_date}) must be greater \
than old entry date (#{entry.entry_date})"
        )
      end
    end

    def validate_zero_trial_balance!(movements)
      raise_error("trial balance must be zero") unless zero_trial_balance?(movements)
    end

    def zero_trial_balance?(movements)
      movements.inject(0) do |sum, movement|
        amount = movement.signed_amount
        amount = -amount if movement.credit?
        sum += amount
        sum
      end.zero?
    end
  end
end
