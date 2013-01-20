$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "mongoid_migration/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "mongoid_migration"
  s.version     = MongoidMigration::VERSION
  s.authors     = ["Mark Ronai"]
  s.email       = ["computadude@me.com"]
  s.homepage    = ""
  s.summary     = "ActiveRecord::Migration ported to Mongoid"
  s.description = "ActiveRecord::Migration ported to Mongoid"

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", ">= 3.0.1"
  s.add_dependency "mongoid", ">= 2.0.1"

  s.add_development_dependency "rails", '3.1.1'
  s.add_development_dependency "bson_ext"
end
