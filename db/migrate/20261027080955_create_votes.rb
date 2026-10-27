class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :round, null: false, foreign_key: true
      t.references :player, null: false, foreign_key: true
      t.references :bluff, null: true, foreign_key: true
      t.timestamps
    end
    add_index :votes, [:round_id, :player_id], unique: true
  end
end
