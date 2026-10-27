module Game
  module Presence
    HOST_GRACE_SECONDS = 30

    def self.connected(player)
      player.update!(connected: true)
      player.room.update!(last_activity_at: Time.current)
    end

    def self.disconnected(player)
      player.update!(connected: false)
      room = player.room
      HostMigrationJob.set(wait: HOST_GRACE_SECONDS.seconds).perform_later(room.id, player.id) if room.host?(player)
      Game::Advance.maybe_finish_phase(room) if room.in_game?
    end

    def self.migrate_host(room, old_host_id)
      room.with_lock do
        return unless room.host_player_id == old_host_id
        old = room.players.find_by(id: old_host_id)
        return if old&.connected?
        new_host = room.players.where(connected: true).order(:id).first
        return if new_host.nil?
        room.update!(host_player_id: new_host.id)
      end
    end
  end
end
