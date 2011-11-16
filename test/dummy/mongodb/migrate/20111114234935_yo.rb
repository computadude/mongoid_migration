class Yo < MongoidMigration::Migration
  def self.up
    Product.create name: 'yo'
  end

  def self.down
    Product.where(name: 'yo').delete
  end
end