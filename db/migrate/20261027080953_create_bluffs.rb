class CreateBluffs < ActiveRecord::Migration[8.1]
  def change
    create_table :bluffs do |t|
      t.references :round, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.string :text, null: false
      t.string :normalized, null: false
      t.timestamps
    end
    add_index :bluffs, [:round_id, :player_id], unique: true
  end
end
