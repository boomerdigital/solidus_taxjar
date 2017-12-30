module Spree
  class Taxjar
    attr_reader :client, :order, :reimbursement, :shipment

    def initialize(api_key, order = nil, reimbursement = nil, shipment = nil, fresh_lineitem = nil)
      # TODO: refactor into splat pattern to remove this arity dependancy

      # if fresh_lineitem is passed prefer that over the association
      # from the order, because the association from the order may be stale
      @order = order
      @shipment = shipment
      @reimbursement = reimbursement
      @fresh_lineitem = fresh_lineitem # TODO: code smell, this is here because solidus is asking for a tax to be calcualted
      # with stale data in the database
      @client = ::Taxjar::Client.new api_key: api_key
    end

    def create_refund_transaction_for_order
      if has_nexus? && !reimbursement_present?
        api_params = refund_params
        api_response = @client.create_refund(api_params)
        api_response
      end
    end

    def create_transaction_for_order
      if has_nexus?
        api_params = transaction_parameters
        if (SpreeTaxjar.extra_debugging)
          Rails.logger.debug "[Taxjar] create_transaction_for_order- for order #{@order.number}  api_params: #{ api_params.to_yaml}"
        end

        api_response = @client.create_order(api_params)
        if (SpreeTaxjar.extra_debugging)

          Rails.logger.debug "[Taxjar] create_transaction_for_order- for order #{@order.number}  api_response: #{ api_response.to_yaml}"
        end


        Rails.logger.debug "[Taxjar] create_transaction_for_order #{@order.number} api_response: #{api_response.inspect}"
        api_response
      end
    rescue HTTP::Error
      Rails.logger.error "[Taxjar] create_transaction_for_order-Failure: Failed to create transaction for order #{@order.number}"
      # Silently ignore
    end

    def delete_transaction_for_order
      if has_nexus?
        api_response = @client.delete_order(@order.number)
        Rails.logger.debug "[Taxjar] delete_transaction_for_order #{order.number} api_response: #{api_response.inspect}"
        api_response
      end
    rescue ::Taxjar::Error::NotFound => e
      Rails.logger.warn "[Taxjar] Taxjar::Error::NotFound: #{order.number} error_msg: #{e.message}"
    end

    def calculate_tax_for_shipment
      if has_nexus?
        api_params = shipment_tax_params
        begin
          api_response = @client.tax_for_order(api_params)
        rescue Taxjar::Error => e
          puts "[Taxjar] exception thrown calculate_tax_for_shipment - #{e.class.name}"
          puts "[Taxjar] exception thrown calculate_tax_for_shipment- #{e.class.name}"
          raise e if ! SpreeTaxjar.swallow_errors
        end
        api_response.amount_to_collect
      else
        0
      end
    rescue HTTP::Error
      raise e if ! SpreeTaxjar.swallow_errors
      Rails.logger.error "[Taxjar] Failure: Failed to calculate tax for shipment #{@shipment.id} (#{@shipment.order.number})"
      0
    end

    def has_nexus?
      nexus_regions = @client.nexus_regions
      if nexus_regions.present?
        nexus_states(nexus_regions).include?(tax_address_state_abbr)
      else
        false
      end
    rescue HTTP::Error
      Rails.logger.error "[Taxjar] Failure: Failed to determine nexus for #{@order.number}"
      false
    end

    def calculate_tax_for_order
      if has_nexus?
        api_params = tax_params
        begin
          api_response = @client.tax_for_order(api_params)
        rescue Taxjar::Error => e
          puts "[Taxjar] exception thrown in calculate_tax_for_order - #{e.class.name}"
          puts "[Taxjar] exception thrown in calculate_tax_for_order - #{e.class.name}"
          raise e if ! SpreeTaxjar.swallow_errors
        end


        if (SpreeTaxjar.extra_debugging)
          Rails.logger.debug "[Taxjar] calculate_tax_for_order- for order #{@order.number}  api_params: #{ api_params.to_yaml}"
          Rails.logger.debug "[Taxjar] calculate_tax_for_order- for order #{@order.number}  api_response: #{ api_response.to_yaml}, breakdown: #{ api_response.breakdown.inspect}"
        end
        api_response
      end
    rescue HTTP::Error
      Rails.logger.error "[Taxjar] Failure in calculate_tax_for_order: Failed to calcuate tax for #{@order.number}"
      nil
    end

    private

      def nexus_states(nexus_regions)
        nexus_regions.map { |record| record.region_code}
      end

      def tax_address_country_iso
        tax_address.country.iso
      end

      def tax_address_state_abbr
        tax_address.state.try(:abbr)
      end

      def tax_address_city
        tax_address.city
      end

      def tax_address_zip
        tax_address.zipcode
      end

      def tax_address
        @order.tax_address
      end

      def tax_params
        amount = @order.item_total + @order.promo_total + @order.shipment_total
        # TODO: this is a code smell but fixes a stale object problem
        if @fresh_lineitem && @fresh_lineitem.changed.include?('promo_total')
          amount += @fresh_lineitem.promo_total
        end
        {
          amount: amount.to_f, # Taxjar expects the charges after promotions are applied
          shipping: @order.shipment_total.to_f,
          to_state: tax_address_state_abbr,
          to_zip: tax_address_zip,
          line_items: taxable_line_items_params
        }
      end

      def taxable_line_items_params
        @order.line_items.map do |item|
          if @fresh_lineitem == item
            {
              id: @fresh_lineitem.id,
              quantity: @fresh_lineitem.quantity,
              unit_price: @fresh_lineitem.price.to_f,
              discount: @fresh_lineitem.promo_total.abs.to_f, # note: spree keeps promo_total as negative number; Taxjar expects positive number
              product_tax_code: @fresh_lineitem.tax_category.try(:tax_code)
            }
          else
            {
              id: item.id,
              quantity: item.quantity,
              unit_price: item.price.to_f,
              discount: item.promo_total.abs.to_f, # note: spree keeps promo_total as negative number; Taxjar expects positive number
              product_tax_code: item.tax_category.try(:tax_code)
            }
          end
        end
      end

      def reimbursement_present?
        @client.list_refunds(from_transaction_date: Date.today - 1, to_transaction_date: Date.today + 1).include?(@reimbursement.number)
      end

      def group_by_line_items
        @reimbursement.return_items.group_by { |item| item.inventory_unit.line_item_id }
      end

      def return_items_params
        group_by_line_items.map do |line_item, return_items|
          item = return_items.first
          {
            quantity: return_items.length,
            product_identifier: item.variant.sku,
            description: ActionView::Base.full_sanitizer.sanitize(item.variant.description).truncate(150),
            unit_price: item.pre_tax_amount,
            product_tax_code: item.variant.tax_category.try(:tax_code)
          }
        end
      end

      def refund_params
        address_params.merge({
          transaction_id: @reimbursement.number,
          transaction_reference_id: @order.number,
          transaction_date: @order.completed_at.as_json,
          amount: @reimbursement.return_items.sum('amount - included_tax_total'),
          shipping: 0,
          sales_tax: @reimbursement.return_items.sum(:additional_tax_total),
          line_items: return_items_params
        })
      end

      def transaction_parameters
        address_params.merge({
          transaction_id: @order.number,
          transaction_date: @order.completed_at.as_json,
          amount: @order.item_total + @order.promo_total + @order.shipment_total,
          shipping: @order.shipment_total,
          sales_tax: @order.additional_tax_total,
          line_items: line_item_params
        })
      end

      def address_params
        {
          to_country: tax_address_country_iso,
          to_zip: tax_address_zip,
          to_state: tax_address_state_abbr,
          to_city: tax_address_city
        }
      end

      def shipment_tax_params
        address_params.merge({
          amount: 0,
          shipping: @shipment.cost
        })
      end

      def line_item_params
        @order.line_items.map do |item|
          {
            quantity: item.quantity,
            product_identifier: item.sku,
            description: "#{item.product.name}: #{item.variant.options_text}",
            unit_price: item.price,
            sales_tax: item.additional_tax_total,
            discount: item.promo_total.abs,
            product_tax_code: item.tax_category.try(:tax_code)
          }
        end
      end
  end
end
