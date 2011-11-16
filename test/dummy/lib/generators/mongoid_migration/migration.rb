module MongoidMigration
  module Generators
    module Migration
      # Implement the required interface for Rails::Generators::Migration.
      def next_migration_number(dirname) #:nodoc:
        next_migration_number = current_migration_number(dirname) + 1
        [Time.now.utc.strftime("%Y%m%d%H%M%S"), "%.14d" % next_migration_number].max
      end
    end
  end
end