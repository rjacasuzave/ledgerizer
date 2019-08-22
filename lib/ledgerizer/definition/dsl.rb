module Ledgerizer
  module Definition
    module Dsl
      extend ActiveSupport::Concern

      class_methods do
        def tenant(model_name, &block)
          in_context do
            @current_tenant = definition.add_tenant(infer_tenant_class!(model_name))
            block&.call
          end
        ensure
          @current_tenant = nil
        end

        def accounts(currency: nil, &block)
          in_context do
            @current_tenant.currency = format_currency!(currency)
            block&.call
          end
        end

        def in_context
          current_method = caller_locations(1, 1)[0].label.to_sym
          validate_context!(current_method)
          current_context << current_method
          yield
        ensure
          current_context.pop
        end

        def validate_context!(current_method)
          dependencies = ctx_dependencies_map[current_method]

          if current_context != dependencies
            if dependencies.any?
              raise_error("'#{current_method}' needs to run inside '#{dependencies.last}' block")
            else
              raise_error("'#{current_method}' can't run inside '#{current_context.last}' block")
            end
          end
        end

        def ctx_dependencies_map
          {
            tenant: [],
            accounts: [:tenant]
          }
        end

        def current_context
          @current_context ||= []
        end

        def format_currency!(currency)
          formatted_currency = currency.to_s.downcase.to_sym
          return :usd if formatted_currency.blank?
          return formatted_currency if Money::Currency.table.key?(formatted_currency)

          raise_error("invalid currency '#{currency}' given")
        end

        def infer_tenant_class!(model_name)
          model_name.to_s.classify.constantize
        rescue NameError
          raise_error("tenant name must be an ActiveRecord model name")
        end

        def raise_error(msg)
          raise Ledgerizer::DslError.new(msg)
        end

        def definition
          @definition ||= Ledgerizer::Definition::Config.new
        end
      end
    end
  end
end
