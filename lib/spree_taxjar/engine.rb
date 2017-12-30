module SpreeTaxjar
  class << self
    mattr_accessor :extra_debugging, :swallow_errors
    self.extra_debugging = false
    self.swallow_errors = true # set to fails to raise on taxjar errors

    # add default values of more config vars here
  end

  # this function maps the vars from your app into your engine
  def self.setup(&block)
    yield self
  end

  class Engine < Rails::Engine
    require 'spree/core'
    require 'taxjar'

    config.autoload_paths += %W(#{config.root}/lib)

    isolate_namespace Spree
    engine_name 'spree_taxjar'

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end


    initializer 'spree.register.calculators' do |app|
      app.config.spree.calculators.tax_rates << Spree::Calculator::TaxjarCalculator
    end

    config.to_prepare &method(:activate).to_proc
  end
end
