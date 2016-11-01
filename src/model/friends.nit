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

module friends

import model::notifications
import model::achievements

redef class DBContext

	fun friend_request_worker: FriendRequestWorker do return once new FriendRequestWorker
	fun friend_request_by_id(id: Int): nullable FriendRequest do return friend_request_worker.fetch_one(self, "ev.id AS id, ev.datetime AS datetime, frd.player_id1 AS from, frd.player_id2 AS to, frd.status AS status FROM events AS ev, friend_events AS frd WHERE ev.id = {id} AND frd.event_id = ev.id;")

	# 0 - Unanswered
	fun friend_request_unanswered: Int do return 0
	# 1 - Accepted
	fun friend_request_accepted: Int do return 1
	# 2 - Rejected
	fun friend_request_rejected: Int do return 2
end

redef class Statement
	fun to_friend_requests(ctx: DBContext): Array[FriendRequest] do
		return ctx.friend_request_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

class FriendRequestWorker
	super EntityWorker

	redef type ENTITY: FriendRequest

	redef fun entity_type do return "FriendRequest"

	redef fun expected_data do return once ["id", "datetime", "from_id", "to_id", "status"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var id = m["id"].as(Int)
		var date = m["datetime"].as(Int)
		var from = m["from_id"].as(Int)
		var to = m["to_id"].as(Int)
		var status = m["status"].as(Int)
		var ret = new FriendRequest(ctx, from, to)
		ret.status = status
		ret.id = id
		ret.timestamp = date
		return ret
	end
end

redef class Player
	serialize

	fun unlock_first_friend_achievement do
		if friend_count == 1 then
			var achievement = context.achievement_by_slug("alone_no_more")
			if achievement == null then
				achievement = new FirstFriendAchievement(context)
				achievement.commit
			end
			add_achievement(achievement)
		end
	end

	fun friend_count: Int do
		var res = context.try_select("COUNT(*) FROM friends WHERE player_id1 = {id};")
		if res == null then return 0
		return res.get_count
	end

	fun remove_friend(player: Player): Bool do
		var db = context.connection
		var query = "DELETE FROM friends WHERE (player_id1 = {id} AND player_id2 = {player.id}) OR (player_id1 = {player.id} AND player_id2 = {id});"
		if not db.execute(query) then
			print "Unable to remove friend '{player.name}' from database due to error '{db.error or else "Unknown error"}'"
			return false
		end
		return true
	end

	# Is `player_id` an accepted friend of `self`?
	fun has_friend(player_id: Int): Bool do
		var res = context.try_select("COUNT(*) FROM friends WHERE player_id2 = {player_id};")
		return res != null and res.get_count != 0
	end

	fun friends: Array[Player] do return context.player_worker.fetch_multiple(context, "players.* FROM players, friends WHERE friends.player_id1 = {id} AND players.id = friends.player_id2;")

	# Does `self` already have a friend request from `player`?
	fun has_friend_request_from(player_id: Int): Bool do
		var res = context.try_select("COUNT(*) FROM events AS ev, friend_events AS frd WHERE frd.player_id1 = {player_id} AND frd.status = {context.friend_request_unanswered} AND frd.event_id = ev.id;")
		return res != null and res.get_count != 0
	end

	# Create a friend request from `self` to `player`
	#
	# Returns the friend request if the request was created.
	# `null` means the player is already a friend or already has a friend request.
	fun ask_friend(player: Player): nullable FriendRequest do
		if self == player then return null
		if player.has_friend(id) then return null
		if player.has_friend_request_from(id) then return null
		var fr = new FriendRequest(context, id, player.id)
		fr.commit
		return fr
	end

	# Get all open friend requests
	fun open_friend_requests: Array[FriendRequest] do return context.friend_request_worker.fetch_multiple(context, "ev.id AS id, ev.datetime AS datetime, frd.player_id1 AS from_id, frd.player_id2 AS to_id, frd.status AS status FROM events AS ev, friend_events AS frd WHERE (frd.player_id2 = {id} OR frd.player_id1 = {id}) AND frd.status = {context.friend_request_unanswered} AND frd.event_id = ev.id;")

	# All the requests received by `self`
	fun received_friend_requests: Array[FriendRequest] do return context.friend_request_worker.fetch_multiple(context, "ev.id AS id, ev.datetime AS datetime, frd.player_id1 AS from_id, frd.player_id2 AS to_id, frd.status AS status FROM events AS ev, friend_events AS frd WHERE frd.player_id2 = {id} AND frd.event_id = ev.id;")

	# All the requests sent by `self`
	fun sent_friend_requests: Array[FriendRequest] do return context.friend_request_worker.fetch_multiple(context, "ev.id AS id, ev.datetime AS datetime, frd.player_id1 AS from_id, frd.player_id2 AS to_id, frd.status AS status FROM events AS ev, friend_events AS frd WHERE frd.player_id1 = {id} AND frd.event_id = ev.id;")
end

class FriendRequest
	super Event
	serialize

	# Who asked to be friend
	var from_id: Int

	# Player object for from
	var from: nullable Player is lazy do return context.player_by_id(from_id)

	# To whom is the request targeted?
	var to_id: Int

	# Player object for to
	var to: nullable Player is lazy do return context.player_by_id(to_id)

	# Status of the request
	#
	# 0 - Unanswered
	# 1 - Accepted
	# 2 - Rejected
	var status = 0

	fun accept: Bool do
		status = context.friend_request_accepted
		var from = from
		var to = to
		if from == null or to == null then
			print "Error: FriendRequest {id} concerns at least one non existing player, {from or else from_id} or {to or else to_id}"
			return false
		end
		var ret = commit
		var notif_from = new FriendRequestAcceptNotification(context, id, from_id, to_id)
		var notif_to = new FriendRequestAcceptNotification(context, id, to_id, from_id)
		notif_from.commit
		notif_to.commit
		from.unlock_first_friend_achievement
		to.unlock_first_friend_achievement
		return ret
	end

	fun decline: Bool do
		status = context.friend_request_rejected
		var ret = commit
		return ret
	end

	redef fun ==(o) do return o isa SELF and o.id == id

	redef fun insert do
		var from = from
		var to = to
		if from == null or to == null then
			print "Cannot insert friend request to database due to either player not existing"
			return false
		end
		if not (super and basic_insert("INSERT INTO friend_events(event_id, player_id1, player_id2, status) VALUES({id}, {from}, {to}, {status});")) then return false
		if status == context.friend_request_accepted then return make_friend
		var notif = new FriendRequestNotification(context, id, to_id, from_id)
		notif.commit
		return true
	end

	redef fun update do
		if not (super and basic_update("UPDATE friend_events SET status = {status} WHERE event_id = {id};")) then return false
		if status == context.friend_request_accepted then return make_friend
		return true
	end

	fun make_friend: Bool do
		var db = context.connection
		var query = "INSERT INTO friends(player_id1, player_id2) VALUES ({from_id}, {to_id}), ({to_id}, {from_id});"
		if not db.execute(query) then
			context.log_sql_error(self, query)
			return false
		end
		return true
	end
end

class FriendRequestNotification
	super PlayerNotification
	serialize

	# Who sent the friend request
	var from_id: Int

	redef var object = "New friend request"
	redef var body is lazy do
		var p = context.player_by_id(from_id)
		if p != null then return "{p.name} wants to be your friend."
		return "Error: No player could be found"
	end
end

class FriendRequestAcceptNotification
	super PlayerNotification
	serialize

	# Player receiving the request
	var to_id: Int

	redef var object = "Accepted friend request"
	redef var body is lazy do
		var p = context.player_by_id(to_id)
		if p != null then return "You and {p.name} are now friends."
		return "Error: No player could be found"
	end
end

# First friend achievement
#
# Unlocked when the player add its first friend.
class FirstFriendAchievement
	super Achievement
	serialize
	autoinit(context)

	redef var title = "Alone no more"
	redef var desc = "Get your first friend."
	redef var reward = 30
end
