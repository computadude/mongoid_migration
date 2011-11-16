require 'generators/mongoid_migration/migration'
 
class MongoidMigrationGenerator < Rails::Generators::NamedBase
  
  include Rails::Generators::Migration
  extend MongoidMigration::Generators::Migration
  
  source_root File.expand_path("../templates", __FILE__)
  
  def create_migration_file
    migration_template "mongoid_migration.rb", "mongodb/migrate/#{file_name}.rb"
  end
  
end
