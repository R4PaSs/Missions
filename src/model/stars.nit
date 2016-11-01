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

module stars

import model::tracks

redef class DBContext
	fun star_worker: StarWorker do return once new StarWorker

	fun star_status_worker: StarStatusWorker do return once new StarStatusWorker

	# The types of stars and their related ID
	#
	# NOTE: Requires manual database synchronization
	var star_types = new HashMap[String, Int]

	init do
		star_types["Size"] = 1
		star_types["Time"] = 2
	end

	fun star_by_id(id: Int): nullable MissionStar do return star_worker.fetch_one(self, "* FROM stars WHERE id = {id};")

	## Star status codes
	fun star_locked: Int do return 1
	fun star_unlocked: Int do return 2
	#

	fun star_count_track(track_id: Int): Int do
		var res = try_select("COUNT(*) FROM stars, missions WHERE missions.track_id = {track_id} AND missions.id = stars.mission_id;")
		if res == null then return 0
		return res.get_count
	end
end

redef class Statement
	# Gets all the Star items from `self`
	#
	# Returns an empty array if none were found or if a row
	# was non-compliant with the construction of a Star
	fun to_stars(ctx: DBContext): Array[MissionStar] do
		return ctx.star_worker.
			fetch_multiple_from_statement(ctx, self)
	end

	# Gets all the StarStatus items from `self`
	#
	# Returns an empty array if none were found or if a row
	# was non-compliant with the construction of a StarStatus
	fun to_star_statuses(ctx: DBContext): Array[StarStatus] do
		return ctx.star_status_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

class StarWorker
	super EntityWorker

	redef type ENTITY: MissionStar

	redef fun entity_type do return "MissionStar"

	redef fun expected_data do return once ["id", "title", "mission_id", "score", "reward", "type_id"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var id = m["id"].as(Int)
		var title = m["title"].as(String)
		var mid = m["mission_id"].as(Int)
		var score = m["score"].as(Int)
		var reward = m["reward"].as(Int)
		var tid = m["type_id"].as(Int)
		var ret = new MissionStar(ctx, title, reward, mid, tid)
		ret.id = id
		ret.goal = score
		return ret
	end
end
class StarStatusWorker
	super EntityWorker

	redef type ENTITY: StarStatus

	redef fun entity_type do return "StarStatus"

	redef fun expected_data do return once ["star_id", "player_id", "status"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var sid = m["star_id"].as(Int)
		var pid = m["player_id"].as(Int)
		var status = m["status"].as(Int)
		var ret = new StarStatus(ctx, pid, sid)
		ret.is_unlocked = status != 0
		ret.persisted = true
		return ret
	end
end

# Mission requirements
abstract class MissionStar
	super UniqueEntity
	serialize

	# The star explanation
	var title: String

	# The reward (in points) accorded when this star is unlocked
	var reward: Int

	# The mission `self` is attached to
	var mission_id: Int

	# The value to earn the star
	var goal = 0 is writable

	new(context: DBContext, title: String, reward, mission_id, type_id: Int) do
		if type_id == 1 then return new SizeStar(context, title, reward, mission_id)
		if type_id == 2 then return new TimeStar(context, title, reward, mission_id)
		# Add more star types to `new` as they are added to model
		abort
	end

	# The name of the type
	fun type_name: String is abstract

	# Identifier for the type of star
	fun type_id: Int do return context.star_types[type_name]

	fun status(player_id: Int): nullable StarStatus do return context.star_status_worker.fetch_one(context, "* FROM star_status WHERE player_id = {player_id} AND star_id = {id}")

	redef fun insert do return basic_insert("INSERT INTO stars(title, mission_id, type_id, reward, score) VALUES({title.to_sql_string}, {mission_id}, {type_id}, {reward}, {goal});")

	redef fun update do return basic_update("UPDATE stars SET mission_id = {mission_id}, reward = {reward}, score = {goal}, title = {title.to_sql_string} WHERE id = {id};")

end

class SizeStar
	super MissionStar
	serialize

	redef fun type_name do return "Size"
end

class TimeStar
	super MissionStar
	serialize

	redef fun type_name do return "Time"
end

# The link between a Player and a Star
class StarStatus
	super BridgeEntity
	serialize

	# The player associated to the status
	var player_id: Int

	# The associated star
	var star_id: Int

	# Is the star granted?
	var is_unlocked = false is writable

	redef fun insert do return basic_insert("INSERT INTO star_status(star_id, player_id, status) VALUES({star_id}, {player_id}, {if is_unlocked then 1 else 0});")

	redef fun update do return basic_update("UPDATE star_status SET status = {if is_unlocked then 1 else 0} WHERE star_id = {star_id} AND player_id = {player_id};")

end

redef class Mission
	serialize
	var stars: Array[MissionStar] is lazy do
		var db = context.connection
		var rows = db.select("stars.* FROM stars WHERE mission_id = {id};")
		if rows == null then
			print "Error when querying for stars '{db.error or else "Unknown error"}'"
			return new Array[MissionStar]
		end
		return rows.to_stars(context)
	end

	fun star_statuses(player_id: Int): Array[StarStatus] do
		var stars = stars
		var stats = context.star_status_worker.fetch_multiple(context, "star_status.* FROM missions, star_status, stars WHERE star_status.star_id = stars.id AND stars.mission_id = missions.id AND missions.id = {id};")
		if stars.length == stats.length then return stats
		for i in stars do
			var found = false
			for j in stats do
				if j.star_id == i.id then
					found = true
					break
				end
			end
			if not found then
				var s = new StarStatus(context, player_id, i.id)
				s.commit
				stats.add s
			end
		end
		return stats
	end

	fun success_for(pid: Int) do
		var status = status_for(pid)
		if status == null then status = new MissionStatus(context, id, pid, context.mission_success)
		status.status_code = context.mission_success
		var chlds = children
		for i in chlds do
			var can_unlock = true
			var deps = i.parents
			for j in deps do
				var pstat = j.status_for(pid)
				if pstat == null or pstat.status == context.mission_locked then
					can_unlock = false
				end
			end
			if not can_unlock then continue
			var stat = i.status_for(pid)
			if stat == null or stat.status == context.mission_success then continue
			stat.status_code = context.mission_open
			stat.commit
		end
		status.commit
	end
end

redef class MissionStatus
	serialize
	var star_status: Array[StarStatus] is lazy do
		var mission = context.mission_by_id(mission_id)
		if mission == null then return new Array[StarStatus]
		return mission.star_statuses(player_id)
	end
end

redef class Track
	fun stars: Array[MissionStar] do
		var db = context.connection
		var rows = db.select("stars.* FROM stars, missions WHERE missions.track_id = {id} AND stars.mission_id = mission.id;")
		if rows == null then
			print "Error when querying for stars '{db.error or else "Unknown Error"}'"
			return new Array[MissionStar]
		end
		return rows.to_stars(context)
	end

	fun star_statuses_for(player_id: Int): Array[StarStatus] do
		var m = missions
		var stats = new Array[StarStatus]
		for i in m do stats.add_all i.star_statuses(player_id)
		return stats
	end
end

redef class Player
	fun star_count: Int do
		var res = context.try_select("COUNT(*) FROM star_status WHERE player_id = {id} AND status = 1;")
		if res == null then return 0
		return res.get_count
	end

	fun unlocked_stars: Array[MissionStar] do return context.star_worker.fetch_multiple(context, "stars.* FROM stars, star_status AS stat WHERE stat.player_id = {id} AND stat.status = {context.star_unlocked};")
end

redef class TrackStatus
	serialize
	# Star count for track `track_id`
	var stars_count: Int is lazy do return context.star_count_track(track_id)
	# Unlocked stars for `player_id` in track `track_id`
	var stars_unlocked: Int is lazy do
		var res = context.try_select("COUNT(*) FROM star_status, stars, missions WHERE missions.track_id = {track_id} AND star_status.player_id = {player_id} AND stars.mission_id = missions.id AND star_status.star_id = stars.id AND star_status.status = 1;")
		if res == null then return 0
		return res.get_count
	end
end
