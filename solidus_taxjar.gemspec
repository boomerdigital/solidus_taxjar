# encoding: UTF-8
Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'solidus_taxjar'
  s.version     = '3.2.0'
  s.summary     = 'Solidus extension to calculate sales tax in states of USA'
  s.description = 'Solidus extension for providing TaxJar services in USA'
  s.required_ruby_version = '>= 2.1.0'

  s.author    = ['Nimish Gupta', 'Tanmay Sinha', 'Eric Anderson']
  s.email     = ['nimish.gupta@vinsol.com', 'tanmay@vinsol.com', 'e@pix.sc']
  s.license = 'BSD-3'

  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'solidus'
  s.add_dependency 'taxjar-ruby', '~> 2.2'

  s.add_development_dependency 'capybara'
  s.add_development_dependency 'coffee-rails'
  s.add_development_dependency 'database_cleaner'
  s.add_development_dependency 'factory_bot'
  s.add_development_dependency 'ffaker'
  s.add_development_dependency 'rspec-rails'
  s.add_development_dependency 'sass-rails'
  s.add_development_dependency 'selenium-webdriver'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'sqlite3'
  s.add_development_dependency 'shoulda-matchers'
  s.add_development_dependency 'rspec-activemodel-mocks'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
end
