# Copyright 2016 Alexandre Terrasa <alexandre@moz-code.org>.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module notifications

import model::players

redef class DBContext
	fun notification_worker: NotificationWorker do return once new NotificationWorker

	fun notification_by_id(id: Int): nullable PlayerNotification do return notification_worker.fetch_one(self, "* FROM notifications WHERE id = {id};")
end

redef class Statement
	fun to_notifications(ctx: DBContext): Array[PlayerNotification] do
		return ctx.notification_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

class NotificationWorker
	super EntityWorker

	redef type ENTITY: PlayerNotification

	redef fun entity_type do return "PlayerNotification"

	redef fun expected_data do return once ["id", "event_id", "player_id", "object", "body", "read", "timestamp"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var id = m["id"].as(Int)
		var pid = m["player_id"].as(Int)
		var obj = m["object"].as(String)
		var body = m["body"].as(String)
		var eid = m["event_id"].as(Int)
		var read = m["read"].as(Int) == 1
		var timestamp = m["timestamp"].as(Int)
		var ret = new PlayerNotification(ctx, eid, pid)
		ret.object = obj
		ret.body = body
		ret.id = id
		ret.read = read
		ret.timestamp = timestamp
		return ret
	end
end

redef class Player
	fun notifications: Array[PlayerNotification] do return context.notification_worker.fetch_multiple(context, "* FROM notifications, events WHERE notifications.player_id = {id} AND events.id = notifications.event_id;")

	fun open_notifications: Array[PlayerNotification] do return context.notification_worker.fetch_multiple(context, "* FROM notifications, events WHERE notifications.player_id = {id} AND events.id = notifications.event_id AND notifications.read = 0;")

	fun clear_notifications: Bool do
		var query = "UPDATE notifications SET read = 1 WHERE notifications.read = 0 AND notifications.player_id = {id}"
		return context.connection.execute(query)
	end
end

# Notification of an event to a player
class PlayerNotification
	super UniqueEntity
	serialize

	var event_id: Int
	var player_id: Int
	var timestamp: Int is lazy do return get_time
	var object: String is noinit
	var body: String is noinit
	var read = false
	var icon = "envelope"

	fun clear: Bool do
		read = true
		return commit
	end

	redef fun insert do return basic_insert("INSERT INTO notifications(event_id, player_id, object, body, read, timestamp) VALUES({event_id}, {player_id}, {object.to_sql_string}, {body.to_sql_string}, 0, {timestamp});")

	redef fun update do return basic_update("UPDATE notifications SET read = {if read then 1 else 0} WHERE id = {id};")
end
