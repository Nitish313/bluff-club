class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms do |t|
      t.string :code, null: false
      t.string :status, null: false, default: "lobby"
      t.bigint :host_player_id
      t.string :pack, null: false, default: "general"
      t.integer :question_count, null: false, default: 6
      t.integer :current_round_index, null: false, default: 0
      t.datetime :phase_ends_at
      t.string :phase_token
      t.text :custom_questions
      t.datetime :last_activity_at
      t.timestamps
    end
    add_index :rooms, :code, unique: true
  end
end
