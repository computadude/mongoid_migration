require 'mongoid_migration'
require 'rails'

module MongoidMigration
  class Railtie < Rails::Railtie
    rake_tasks do
      load "tasks/mongoid_migration_tasks.rake"
    end
  end
end