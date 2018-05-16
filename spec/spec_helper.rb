# frozen_string_literal: true

plugin_test_dir = File.dirname(__FILE__)

require 'rubygems'
require 'bundler/setup'
require 'pry'

require 'logger'
require 'active_record'
require 'mongoid'

log_dir = File.expand_path('../log', __dir__)
ActiveRecord::Base.logger = Logger.new(log_dir + '/debug.log')

logger = Logger.new(log_dir + '/mongoid.log')

Mongoid.configure do |config|
  config.connect_to 'nested_set_test'
  config.logger = logger
  Mongo::Logger.logger = logger
end

require 'yaml'
require 'erb'
ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(IO.read(plugin_test_dir + '/db/database.yml')).result)
ActiveRecord::Base.establish_connection((ENV['DB'] ||= 'sqlite3mem').to_sym)
ActiveRecord::Migration.verbose = false

require 'combustion/database'
Combustion::Database.create_database(ActiveRecord::Base.configurations[ENV['DB']])
load(File.join(plugin_test_dir, 'db', 'schema.rb'))

require 'awesome_nested_set'
require 'support/models'
require 'support/mongoid_models'

begin
  require 'action_view'
rescue LoadError; end # action_view doesn't exist in Rails 4.0, but we need this for the tests to run with Rails 4.1
require 'action_controller'
require 'rspec/rails'
require 'database_cleaner'
RSpec.configure do |config|
  config.fixture_path = "#{plugin_test_dir}/fixtures"
  config.use_transactional_fixtures = true

  config.before(:suite) do
    DatabaseCleaner[:active_record].strategy = :transaction
    client = MongoUser.collection.client
    %w(mongo_categories mongo_notes mongo_things mongo_brokens mongo_users mongo_default_scoped_models).each do |model|
      fixtures = YAML.load_file "spec/fixtures/#{model}.yml"
      backup = Mongo::Collection.new client.database, "#{model}_back"
      fixtures.each do |_key, value|
        id = BSON::ObjectId(value['id'])
        update = value.except('id').merge(_id: id).transform_values do |v|
          begin
            BSON::ObjectId(v)
          rescue BSON::ObjectId::Invalid
            v
          end
        end
        backup.find_one_and_replace(
          { _id: id },
          update,
          upsert: true
        )
      end
    end
  end

  config.before(:context) do
    DatabaseCleaner.clean
  end

  config.after(:suite) do
    unless /sqlite/ === ENV['DB']
      Combustion::Database.drop_database(ActiveRecord::Base.configurations[ENV['DB']])
    end
  end
end
