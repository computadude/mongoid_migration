class Foo < MongoidMigration::Migration
  def self.up
    Product.create name: 'foo'
  end

  def self.down
    Product.where(name: 'foo').delete
  end
end