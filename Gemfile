source 'https://rubygems.org'
gemspec

gem 'builder', '~> 3.0'
gem 'activesupport', '~> 3.2'
gem 'rails', '~> 3.2'
gem 'pry'
gem 'jruby-openssl', :platforms => :jruby
gem 'moip-assinaturas', github: 'edools/moip-assinaturas', tag: '0.6.3'
gem 'pagarme', '~> 2.1.2'
gem 'httparty', '~> 0.13.7'

group :test, :remote_test do
  # gateway-specific dependencies, keeping these gems out of the gemspec
  gem 'braintree', '>= 2.50.0'
end
