require_dependency 'spree/calculator'

module Spree
  class Calculator::TaxjarCalculator < Calculator
    preference :api_key, :string

    CACHE_EXPIRATION_DURATION = 10.minutes

    def self.description
      Spree.t(:taxjar_calculator_description)
    end

    def compute_order(order)
      raise "Calculate tax for line_item and shipment and not order"
    end

    def compute_line_item(item)
      if rate.included_in_price
        0
      else
        round_to_two_places(tax_for_item(item))
      end
    end

    def compute_shipment(shipment)
      tax_for_shipment(shipment)
    end

    def compute_shipping_rate(shipping_rate)
      if rate.included_in_price
        raise Spree.t(:shipping_rate_exception_message)
      else
        0
      end
    end

   private

    def rate
      calculable
    end

    def tax_for_shipment(shipment)
      return 0 unless shipment.order.tax_address

      tax_for_shipment = cached_tax_for_shipment(shipment)

      unless tax_for_shipment
        logger.debug "[Taxjar] tax_for_shipment: #{shipment.inspect} => $0 (tax_for_shipment was nil)"
        return 0
      end

      tax_for_shipment.amount_to_collect.tap do |amount|
        logger.debug "[Taxjar] tax_for_shipment: #{shipment.inspect} => $#{amount}"
      end
    end

    def tax_for_item(item)
      return 0 unless item.order.tax_address

      tax_for_order = cached_tax_for_order(item.order)

      unless tax_for_order
        logger.debug "[Taxjar] tax_for_item order #{item.order.number}: lineitem #{item.id}, $#{item.amount.to_f}, promo: $#{item.promo_total} => $0 (tax_for_order was nil)"
        return 0
      end

      tax_for_order.breakdown.line_items.
        find { |line_item| line_item.id.to_i == item.id }.
        tax_collectable.tap do |tax_collectable|
          logger.debug "[Taxjar] tax_for_item order #{item.order.number}: lineitem #{item.id}, $#{item.amount.to_f}, promo: $#{item.promo_total} => $#{tax_collectable}"
        end
    end

    def cached_tax_for_order(order)
      Rails.cache.fetch(order_cache_key(order), expires_in: CACHE_EXPIRATION_DURATION) do
        Spree::Taxjar.new(preferred_api_key, order, nil, nil).calculate_tax_for_order
      end
    end

    def cached_tax_for_shipment(shipment)
      Rails.cache.fetch(shipment_cache_key(shipment), expires_in: CACHE_EXPIRATION_DURATION) do
        Spree::Taxjar.new(preferred_api_key, shipment.order, nil, shipment).calculate_tax_for_shipment
      end
    end

    def order_cache_key(order)
      # The cache key must include keys that represents the content of an order:
      # - list of items and their quantity
      # - shipping total cost before tax
      # - customer address
      # So that if any of these elements changes, we perform a new call to TaxJar.
      [
        'Taxjar-Spree::Order',
        :amount_to_collect,
        order.id,
        order.line_items.map(&:variant_id),
        order.line_items.map(&:quantity),
        order.shipments.map(&:total_before_tax),
        order.tax_address.state_id,
        order.tax_address.zipcode
      ]
    end

    def shipment_cache_key(shipment)
      [
        'Taxjar-Spree::Shipment',
        :amount_to_collect,
        shipment.order.id,
        shipment.id,
        shipment.cost,
        shipment.order.tax_address.state_id,
        shipment.order.tax_address.zipcode
      ]
    end

    # Imported from Spree::VatPriceCalculation
    def round_to_two_places(amount)
      BigDecimal.new(amount.to_s).round(2, BigDecimal::ROUND_HALF_UP)
    end
  end
end
