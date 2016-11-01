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

module api_players

import model
import api::api_auth

redef class APIRouter
	redef init do
		super
		use("/players", new APIPlayers(config))
		use("/players/:login", new APIPlayer(config))
		use("/players/:login/tracks/", new APIPlayerTracksStatus(config))
		use("/players/:login/tracks/:tid", new APIPlayerTrackStatus(config))
		use("/players/:login/missions/:mid", new APIPlayerMissionStatus(config))
		use("/players/:login/stats/", new APIPlayerStats(config))
		use("/players/:login/friends/", new APIPlayerFriends(config))
		use("/players/:login/achievements/", new APIPlayerAchivements(config))

		use("/player", new APIPlayerAuth(config))
		use("/player/notifications", new APIPlayerNotifications(config))
		use("/player/notifications/:nid", new APIPlayerNotification(config))

		use("/player/friends/:fid", new APIPlayerFriend(config))
		use("/player/ask_friend/:fid", new APIPlayerAskFriend(config))
		use("/player/friend_requests/", new APIPlayerFriendRequests(config))
		use("/player/friend_requests/:fid", new APIPlayerFriendRequest(config))

		use("/players/:login/track/:tid/missions_status", new APITrackMissionStatus(config))
		use("/players/:login/track/:tid/stars_status", new APITrackStarsStatus(config))
	end
end

class APIPlayers
	super APIHandler

	redef fun get(req, res) do
		var top = req.ctx.all_players
		var res_arr = new JsonArray
		for i in top do res_arr.add(i.stats)
		res.json res_arr
	end
end

class APIPlayer
	super PlayerHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		res.json player
	end
end

class APIPlayerAuth
	super AuthHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		res.json player
	end
end

class APIPlayerTracksStatus
	super PlayerHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		res.json new JsonArray.from(player.track_statuses)
	end
end

class APIPlayerTrackStatus
	super PlayerHandler
	super TrackHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var track = get_track(req, res)
		if track == null then return
		res.json track.status_for(player.id)
	end
end

class APIPlayerMissionStatus
	super PlayerHandler
	super MissionHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var mission = get_mission(req, res)
		if mission == null then return
		res.json mission.status_for(player.id)
	end
end

class APIPlayerStats
	super PlayerHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return

		unlock_morriar_achievement(req, player)

		res.json player.stats
	end

	fun unlock_morriar_achievement(req: HttpRequest, player: Player) do
		if player.id != "Morriar" then return
		var session = req.session
		if session == null then return
		var logged = session.player
		if logged == null then return
		var ach = req.ctx.achievement_by_slug("look_in_the_eyes_of_god")
		if ach == null then
			ach = new LookInTheEyesOfGodAchievement
			ach.commit
		end
		logged.add_achievement(ach)
	end
end

class APIPlayerNotifications
	super AuthHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		res.json new JsonArray.from(player.open_notifications)
	end

	redef fun delete(req, res) do
		var player = get_player(req, res)
		if player == null then return
		player.clear_notifications
		res.json new JsonArray.from(player.notifications)
	end
end

class APIPlayerNotification
	super AuthHandler

	fun get_notification(req: HttpRequest, res: HttpResponse): nullable PlayerNotification do
		var nid = req.param("nid")
		if nid == null or not nid.is_int then
			res.api_error("Missing URI param `nid`", 400)
			return null
		end
		var notif = req.ctx.notification_by_id(nid.to_i)
		if notif == null then
			res.api_error("Notification `{nid}` not found", 404)
			return null
		end
		return notif
	end

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var notif = get_notification(req, res)
		if notif == null then return
		if player.id != notif.player_id then
			res.api_error("Unauthorized", 403)
			return
		end
		res.json notif
	end

	redef fun delete(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var notif = get_notification(req, res)
		if notif == null then return
		if player.id != notif.player_id then
			res.api_error("Unauthorized", 403)
			return
		end
		res.json notif.clear
	end
end

class APIPlayerFriends
	super PlayerHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		res.json new JsonArray.from(player.friends)
	end
end

class APIPlayerFriend
	super AuthHandler

	fun get_friend(req: HttpRequest, res: HttpResponse): nullable Player do
		var fid = req.param("fid")
		if fid == null then
			res.api_error("Missing URI param `fid`", 400)
			return null
		end
		var friend = req.ctx.player_by_slug(fid)
		if friend == null then
			res.api_error("Friend `{fid}` not found", 404)
			return null
		end
		return friend
	end

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var friend = get_friend(req, res)
		if friend == null then return
		if not player.has_friend(friend.id) then
			res.api_error("Friend `{friend.id}` not found", 404)
			return
		end
		res.json new JsonArray.from(player.friends)
	end

	redef fun delete(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var friend = get_friend(req, res)
		if friend == null then return
		if not player.has_friend(friend.id) then
			res.api_error("Friend `{friend.id}` not found", 404)
			return
		end
		player.remove_friend(friend)
		friend.remove_friend(player)
		res.json new JsonObject
	end
end

class APIPlayerAskFriend
	super APIPlayerFriend

	# Create friend request
	redef fun post(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var friend = get_friend(req, res)
		if friend == null then return
		if friend == player then
			res.error 400
			return
		end
		var friend_request = player.ask_friend(friend)
		if friend_request == null then
			res.error 400
			return
		end
		res.json friend_request
	end
end

class APIPlayerFriendRequests
	super AuthHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var obj = new JsonObject
		obj["sent"] = new JsonArray.from(player.sent_friend_requests)
		obj["received"] = new JsonArray.from(player.received_friend_requests)
		res.json obj
	end
end

class APIPlayerFriendRequest
	super AuthHandler

	fun get_friend_request(req: HttpRequest, res: HttpResponse): nullable FriendRequest do
		var fid = req.param("fid")
		if fid == null or not fid.is_int then
			res.error 400
			return null
		end
		var friend_request = req.ctx.friend_request_by_id(fid.to_i)
		if friend_request == null then
			res.error 404
			return null
		end
		return friend_request
	end

	# Review friend request
	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var friend_request = get_friend_request(req, res)
		if friend_request == null then return
		if not friend_request.from == player.id or friend_request.to == player.id then
			res.error 404
			return
		end
		res.json friend_request
	end

	# Accept friend request
	redef fun post(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var friend_request = get_friend_request(req, res)
		if friend_request == null then return
		if not friend_request.to == player.id then
			res.error 404
			return
		end
		if not friend_request.accept then
			res.error 400
			return
		end
		res.json new JsonObject
	end

	# Decline friend request
	redef fun delete(req, res) do
		var player = get_player(req, res)
		if player == null then return
		var friend_request = get_friend_request(req, res)
		if friend_request == null then return
		if not friend_request.to == player.id then
			res.error 404
			return
		end
		if not friend_request.decline then
			res.error 400
			return
		end
		res.json new JsonObject
	end

	# TODO accept friend request
end

class APIPlayerAchivements
	super PlayerHandler

	redef fun get(req, res) do
		var player = get_player(req, res)
		if player == null then return
		res.json new JsonArray.from(player.achievements)
	end
end

class APITrackMissionStatus
	super TrackHandler
	super PlayerHandler

	redef fun get(req, res) do
		var track = get_track(req, res)
		var player = get_player(req, res)
		if track == null then
			print "No track found"
			return
		end
		if player == null then
			print "No player found"
			return
		end
		var mission_statuses = track.mission_statuses_for(player.id)
		res.json new JsonArray.from(mission_statuses)
	end
end

class APITrackStarsStatus
	super TrackHandler
	super PlayerHandler

	redef fun get(req, res) do
		var track = get_track(req, res)
		var player = get_player(req, res)
		if track == null or player == null then
			return
		end
		var star_statuses = track.star_statuses_for(player.id)
		res.json new JsonArray.from(star_statuses)
	end
end

# Look in the eyes of the God achievement
#
# Unlocked when the player looks at Morriar stats for the first time.
class LookInTheEyesOfGodAchievement
	super Achievement
	serialize
	noautoinit

	redef var title = "Look in the eyes of God"
	redef var desc = "Look at \"Morriar\" page."
	redef var reward = 10
end
