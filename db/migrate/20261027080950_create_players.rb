class CreatePlayers < ActiveRecord::Migration[8.1]
  def change
    create_table :players do |t|
      t.references :room, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token, null: false
      t.integer :score, null: false, default: 0
      t.boolean :connected, null: false, default: true
      t.boolean :spectator, null: false, default: false
      t.timestamps
    end
    add_index :players, :token, unique: true
  end
end
