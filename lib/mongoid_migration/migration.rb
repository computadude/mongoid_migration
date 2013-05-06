require 'active_support/core_ext/kernel/singleton_class'
require 'active_support/core_ext/module/aliasing'
require 'active_support/core_ext/module/delegation'
require 'mongoid'

module MongoidMigration
  class MongoidMigrationError < StandardError
  end
  
  # Exception that can be raised to stop migrations from going backwards.
  class IrreversibleMigration < MongoidMigrationError
  end

  class DuplicateMigrationVersionError < MongoidMigrationError#:nodoc:
    def initialize(version)
      super("Multiple migrations have the version number #{version}")
    end
  end

  class DuplicateMigrationNameError < MongoidMigrationError#:nodoc:
    def initialize(name)
      super("Multiple migrations have the name #{name}")
    end
  end

  class UnknownMigrationVersionError < MongoidMigrationError #:nodoc:
    def initialize(version)
      super("No migration with version number #{version}")
    end
  end

  class IllegalMigrationNameError < MongoidMigrationError#:nodoc:
    def initialize(name)
      super("Illegal name for migration file: #{name}\n\t(only lower case letters, numbers, and '_' allowed)")
    end
  end
  
  # MigrationProxy is used to defer loading of the actual migration classes
  # until they are needed
  class MigrationProxy
    
    attr_accessor :name, :version, :filename, :basename, :scope

    delegate :migrate, :announce, :write, :to=>:migration

    private

      def migration
        @migration ||= load_migration
      end

      def load_migration
        require(File.expand_path(filename))
        name.constantize
      end
  end

  class Migration
    
    include Mongoid::Document
  	include Mongoid::Timestamps

  	validates_presence_of :version
  	validates_uniqueness_of :version

  	field :version

  	index(version: 1)
  	
    @@verbose = true
    cattr_accessor :verbose

    class << self
      def copy(destination, sources, options = {})
        copied = []
        FileUtils.mkdir_p(destination) unless File.exists?(destination)

        destination_migrations = MongoidMigration::Migrator.new(:up, destination).migrations
        last = destination_migrations.last
        sources.each do |scope, path|
          source_migrations = MongoidMigration::Migrator.new(:up, path).migrations

          source_migrations.each do |migration|
            source = File.read(migration.filename)
            source = "# This migration comes from #{scope} (originally #{migration.version})\n#{source}"

            if duplicate = destination_migrations.detect { |m| m.name == migration.name }
              if options[:on_skip] && duplicate.scope != scope.to_s
                options[:on_skip].call(scope, migration)
              end
              next
            end

            migration.version = next_migration_number(last ? last.version + 1 : 0).to_i
            new_path = File.join(destination, "#{migration.version}_#{migration.name.underscore}.#{scope}.rb")
            old_path, migration.filename = migration.filename, new_path
            last = migration

            File.open(migration.filename, "w") { |f| f.write source }
            copied << migration
            options[:on_copy].call(scope, migration, old_path) if options[:on_copy]
            destination_migrations << migration
          end
        end

        copied
      end
      
      def next_migration_number(number)
        [Time.now.utc.strftime("%Y%m%d%H%M%S"), "%.14d" % number].max
      end
      
      def up_with_benchmarks #:nodoc:
        migrate(:up)
      end

      def down_with_benchmarks #:nodoc:
        migrate(:down)
      end

      # Execute this migration in the named direction
      def migrate(direction)
        return unless respond_to?(direction)

        case direction
          when :up   then announce "migrating"
          when :down then announce "reverting"
        end

        result = nil
        time = Benchmark.measure { result = send("#{direction}_without_benchmarks") }

        case direction
          when :up   then announce "migrated (%.4fs)" % time.real; write
          when :down then announce "reverted (%.4fs)" % time.real; write
        end

        result
      end

      # Because the method added may do an alias_method, it can be invoked
      # recursively. We use @ignore_new_methods as a guard to indicate whether
      # it is safe for the call to proceed.
      def singleton_method_added(sym) #:nodoc:
        return if defined?(@ignore_new_methods) && @ignore_new_methods

        begin
          @ignore_new_methods = true

          case sym
            when :up, :down
              singleton_class.send(:alias_method_chain, sym, "benchmarks")
          end
        ensure
          @ignore_new_methods = false
        end
      end

      def write(text="")
        puts(text) if verbose
      end

      def announce(message)
        version = defined?(@version) ? @version : nil

        text = "#{version} #{name}: #{message}"
        length = [0, 75 - text.length].max
        write "== %s %s" % [text, "=" * length]
      end

      def say(message, subitem=false)
        write "#{subitem ? "   ->" : "--"} #{message}"
      end

      def say_with_time(message)
        say(message)
        result = nil
        time = Benchmark.measure { result = yield }
        say "%.4fs" % time.real, :subitem
        say("#{result} rows", :subitem) if result.is_a?(Integer)
        result
      end

      def suppress_messages
        save, self.verbose = verbose, false
        yield
      ensure
        self.verbose = save
      end
    end
    
  end
  
  class Migrator#:nodoc:
    class << self
      def migrate(migrations_path, target_version = nil)
        case
          when target_version.nil?
            up(migrations_path, target_version)
          when current_version == 0 && target_version == 0
          when current_version > target_version
            down(migrations_path, target_version)
          else
            up(migrations_path, target_version)
        end
      end

      def rollback(migrations_path, steps=1)
        move(:down, migrations_path, steps)
      end

      def forward(migrations_path, steps=1)
        move(:up, migrations_path, steps)
      end

      def up(migrations_path, target_version = nil)
        self.new(:up, migrations_path, target_version).migrate
      end

      def down(migrations_path, target_version = nil)
        self.new(:down, migrations_path, target_version).migrate
      end

      def run(direction, migrations_path, target_version)
        self.new(direction, migrations_path, target_version).run
      end

      def migrations_path
        'mongodb/migrate'
      end

      def get_all_versions
        Migration.all.map {|e| e.version.to_i}.sort
      end

      def current_version
        get_all_versions.max || 0
      end

      private

      def move(direction, migrations_path, steps)
        migrator = self.new(direction, migrations_path)
        start_index = migrator.migrations.index(migrator.current_migration)

        if start_index
          finish = migrator.migrations[start_index + steps]
          version = finish ? finish.version : 0
          send(direction, migrations_path, version)
        end
      end
    end

    def initialize(direction, migrations_path, target_version = nil)
      @direction, @migrations_path, @target_version = direction, migrations_path, target_version
    end

    def current_version
      migrated.last || 0
    end

    def current_migration
      migrations.detect { |m| m.version == current_version }
    end

    def run
      target = migrations.detect { |m| m.version == @target_version }
      raise UnknownMigrationVersionError.new(@target_version) if target.nil?
      unless (up? && migrated.include?(target.version.to_i)) || (down? && !migrated.include?(target.version.to_i))
        target.migrate(@direction)
        record_version_state_after_migrating(target.version)
      end
    end

    def migrate
      current = migrations.detect { |m| m.version == current_version }
      target = migrations.detect { |m| m.version == @target_version }

      if target.nil? && !@target_version.nil? && @target_version > 0
        raise UnknownMigrationVersionError.new(@target_version)
      end

      start = up? ? 0 : (migrations.index(current) || 0)
      finish = migrations.index(target) || migrations.size - 1
      runnable = migrations[start..finish]

      # skip the last migration if we're headed down, but not ALL the way down
      runnable.pop if down? && !target.nil?

      runnable.each do |migration|
        Rails.logger.info "Migrating to #{migration.name} (#{migration.version})" if Rails.logger

        # On our way up, we skip migrating the ones we've already migrated
        next if up? && migrated.include?(migration.version.to_i)

        # On our way down, we skip reverting the ones we've never migrated
        if down? && !migrated.include?(migration.version.to_i)
          migration.announce 'never migrated, skipping'; migration.write
          next
        end

        begin
          migration.migrate(@direction)
          record_version_state_after_migrating(migration.version)
        rescue => e
          raise StandardError, "An error has occurred, all later migrations canceled:\n\n#{e}", e.backtrace
        end
      end
    end

    def migrations
      @migrations ||= begin
        files = Dir["#{@migrations_path}/[0-9]*_*.rb"]

        migrations = files.inject([]) do |klasses, file|
          version, name, scope = file.scan(/([0-9]+)_([_a-z0-9]*)\.?([a-z]*).rb/).first

          raise IllegalMigrationNameError.new(file) unless version
          version = version.to_i

          if klasses.detect { |m| m.version == version }
            raise DuplicateMigrationVersionError.new(version)
          end

          if klasses.detect { |m| m.name == name.camelize }
            raise DuplicateMigrationNameError.new(name.camelize)
          end

          migration = MigrationProxy.new
          migration.basename = File.basename(file)
          migration.name     = name.camelize
          migration.version  = version
          migration.filename = file
          migration.scope    = scope unless scope.blank?
          klasses << migration
        end

        migrations = migrations.sort_by { |m| m.version }
        down? ? migrations.reverse : migrations
      end
    end

    def pending_migrations
      already_migrated = migrated
      migrations.reject { |m| already_migrated.include?(m.version.to_i) }
    end

    def migrated
      @migrated_versions ||= self.class.get_all_versions
    end

    private
      def record_version_state_after_migrating(version)
        @migrated_versions ||= []
        if down?
          @migrated_versions.delete(version)
          Migration.where(version: version.to_s).delete
        else
          @migrated_versions.push(version).sort!
          Migration.create "version" => version.to_s
        end
      end

      def up?
        @direction == :up
      end

      def down?
        @direction == :down
      end

  end
end
