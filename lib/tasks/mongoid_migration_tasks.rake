namespace :db do
  namespace :mongoid do
    
    namespace :migration do
      desc 'Runs the "up" for a given migration VERSION.'
      task :up => :environment do
        version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
        raise "VERSION is required" unless version
        MongoidMigration::Migrator.run(:up, "mongodb/migrate/", version)
      end

      desc 'Runs the "down" for a given migration VERSION.'
      task :down => :environment do
        version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
        raise "VERSION is required" unless version
        MongoidMigration::Migrator.run(:down, "mongodb/migrate/", version)
      end

      desc "Display status of migrations"
      task :status => :environment do
        if File.exists? File.join(Rails.root, 'mongodb', 'migrate')
          db_list = MongoidMigration::Migration.all.map &:version
          file_list = []
          Dir.foreach(File.join(Rails.root, 'mongodb', 'migrate')) do |file|
            # only files matching "20091231235959_some_name.rb" pattern
            if match_data = /(\d{14})_(.+)\.rb/.match(file)
              status = db_list.delete(match_data[1]) ? 'up' : 'down'
              file_list << [status, match_data[1], match_data[2]]
            end
          end
          # output
          puts "#{"Status".center(8)}  #{"Migration ID".ljust(14)}  Migration Name"
          puts "-" * 50
          file_list.each do |file|
            puts "#{file[0].center(8)}  #{file[1].ljust(14)}  #{file[2].humanize}"
          end
          db_list.each do |version|
            puts "#{'up'.center(8)}  #{version.ljust(14)}  *** NO FILE ***"
          end
        else
          p "No migration files"
        end
        puts
      end
    end
    
    desc "Retrieves the current schema version number"
    task :version => :environment do
      puts "Current version: #{MongoidMigration::Migrator.current_version}"
    end
    
    desc "Migrate the database (options: VERSION=x, VERBOSE=false)."
    task :migrate => :environment do
      MongoidMigration::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
      MongoidMigration::Migrator.migrate 'mongodb/migrate', ENV["VERSION"] ? ENV["VERSION"].to_i : nil
    end
    
    desc 'Rolls migrations back to the previous version (specify steps w/ STEP=n).'
    task :rollback => :environment do
      step = ENV['STEP'] ? ENV['STEP'].to_i : 1
      MongoidMigration::Migrator.rollback('mongodb/migrate/', step)
    end
    
    desc 'Pushes migrations to the next version (specify steps w/ STEP=n).'
    task :forward => :environment do
      step = ENV['STEP'] ? ENV['STEP'].to_i : 1
      MongoidMigration::Migrator.forward('mongodb/migrate/', step)
    end
  end
end

