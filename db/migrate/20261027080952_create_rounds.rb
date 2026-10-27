class CreateRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :rounds do |t|
      t.references :room, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :question, null: false
      t.text :answer, null: false
      t.timestamps
    end
    add_index :rounds, [:room_id, :position], unique: true
  end
end
