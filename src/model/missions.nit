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

module missions

import model::players

redef class DBContext

	fun mission_worker: MissionWorker do return once new MissionWorker

	fun mission_status_worker: MissionStatusWorker do return once new MissionStatusWorker

	fun mission_by_id(id: Int): nullable Mission do return mission_worker.fetch_one(self, "* FROM missions WHERE id = {id};")

	fun mission_by_slug(slug: String): nullable Mission do return mission_worker.fetch_one(self, "* FROM missions WHERE slug = {slug.to_sql_string};")

	fun all_missions: Array[Mission] do return mission_worker.fetch_multiple(self, "* FROM missions;")

	## Mission status codes

	fun mission_locked: Int do return 1
	fun mission_open: Int do return 2
	fun mission_success: Int do return 3

	var mission_status: Array[String] = ["locked", "open", "success"]

	##
end

class MissionWorker
	super EntityWorker

	redef type ENTITY: Mission

	redef fun entity_type do return "Mission"

	redef fun expected_data do return once ["id", "slug", "title", "track_id", "description", "reward", "path"]

	redef fun make_entity_from_row(ctx, row) do
		var map = row.map
		var id = map["id"].as(Int)
		var slug = map["slug"].as(String)
		var title = map["title"].as(String)
		var tid = map["track_id"].as(Int)
		var desc = map["description"].as(String)
		var rew = map["reward"].as(Int)
		var ret = new Mission(ctx, slug, title, tid, desc)
		if map["path"] != null then ret.path = map["path"].as(String)
		ret.id = id
		ret.solve_reward = rew
		ret.load_languages
		return ret
	end
end

class MissionStatusWorker
	super EntityWorker

	redef type ENTITY: MissionStatus

	redef fun entity_type do return "MissionStatus"

	redef fun expected_data do return ["mission_id", "player_id", "status"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var mid = m["mission_id"].as(Int)
		var pid = m["player_id"].as(Int)
		var status = m["status"].as(Int)
		var res = new MissionStatus(ctx, mid, pid, status)
		res.persisted = true
		return res
	end
end

redef class Statement
	# Gets all the Mission items from `self`
	#
	# Returns an empty array if none were found or if a row
	# was non-compliant with the construction of a Mission
	fun to_missions(ctx: DBContext): Array[Mission] do
		return ctx.mission_worker.
			fetch_multiple_from_statement(ctx, self)
	end

	fun to_mission_statuses(ctx: DBContext): Array[MissionStatus] do
		return ctx.mission_status_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

class Mission
	super UniqueEntity
	serialize

	var slug: String
	var title: String
	var track_id: Int
	var desc: String
	# Reward for solving the mission (excluding stars)
	var solve_reward: Int = 0 is writable, serialize_as("reward")
	var path: nullable String is writable

	var languages = new Array[String]

	fun load_languages do
		var db = context.connection
		var query = "languages.name FROM mission_languages, languages WHERE mission_languages.mission_id = {id} AND languages.id = mission_languages.language_id;"
		var res = db.select(query)
		if res == null then
			context.log_sql_error(context, query)
			return
		end
		for i in res do languages.add(i[0].to_s)
	end

	redef fun to_s do return title

	var parents: Array[Mission] is lazy, writable do return context.mission_worker.fetch_multiple(context, "missions.* FROM missions, mission_dependencies WHERE mission_dependencies.mission_id = {id} AND missions.id = mission_dependencies.parent_id;")

	var children: Array[Mission] is lazy, noserialize do return context.mission_worker.fetch_multiple(context, "missions.* FROM missions, mission_dependencies WHERE mission_dependencies.parent_id = {id} AND mission_dependencies.mission_id = missions.id;")

	# Sets the dependencies for a Mission within database
	#
	# REQUIRE: `self.id` != -1
	# NOTE: No cycle detection is performed here, careful when setting
	# dependencies
	fun set_dependencies: Bool do
		var db = context.connection
		var clean_query = "DELETE FROM mission_dependencies WHERE mission_id = {id};"
		var insert_query = "INSERT INTO mission_dependencies(mission_id, parent_id) VALUES "
		var values = new Array[String]
		for i in parents do values.add("({id}, {i.id})")
		insert_query += values.join(", ")
		if not db.execute(clean_query) then
			print "Error when setting dependencies: {db.error or else "Unknown Error"}"
			return false
		end
		if parents.length == 0 then return true
		if not db.execute(insert_query) then
			print "Error when setting dependencies: {db.error or else "Unknown Error"}"
			return false
		end
		return true
	end

	# How much can `self` reward for full completion? (Including stars)
	fun total_reward: Int do
		var db = context.connection
		var rows = db.select("score FROM stars WHERE mission_id = {id};")
		var score = solve_reward
		if rows != null then for i in rows do score += i.map["score"].as(Int)
		db.close
		return score
	end

	# Which missions do `self`  depend on?
	fun dependencies: Array[Mission] do return context.mission_worker.fetch_multiple(context, "missions.* FROM missions, mission_dependencies WHERE mission_id = {id};")

	# Is `self` unlocked for `player` ?
	fun is_unlocked_for_player(player_id: Int): Bool do
		var ret = context.try_select("COUNT(*) FROM mission_status WHERE player_id = {player_id} AND mission_id = {id} AND (status = {context.mission_open} OR status = {context.mission_success});")
		return ret != null and ret.get_count != 0
	end

	redef fun insert do
		var p = path
		if p != null then p = p.to_sql_string
		return basic_insert("INSERT INTO missions(slug, title, track_id, description, reward, path) VALUES({slug.to_sql_string}, {title.to_sql_string}, {track_id}, {desc.to_sql_string}, {solve_reward}, {p or else "NULL"});") and set_dependencies
	end

	redef fun update do
		var p = path
		if p != null then p = p.to_sql_string
		return basic_update("UPDATE missions SET slug = {slug.to_sql_string}, title = {title.to_sql_string}, track_id = {track_id}, description = {desc.to_sql_string}, reward = {solve_reward}, path = {p or else "NULL"} WHERE id = {id};") and set_dependencies
	end

	fun status_for(player_id: Int): nullable MissionStatus do
		var ret = context.mission_status_worker.fetch_one(context, "* FROM mission_status WHERE mission_id = {id} AND player_id = {player_id};")
		if ret != null then return ret
		var deps = parents
		var mstat = context.mission_locked
		var unlocked = true
		for i in deps do
			var istat = i.status_for(player_id)
			# Should never happen, if it does, we have a serious problem which needs a quick fix.
			if istat == null then return null
			if not istat.status == context.mission_success then
				unlocked = false
				break
			end
		end
		if unlocked then mstat = context.mission_open
		var status = new MissionStatus(context, id, player_id, mstat)
		status.commit
		return status
	end
end

class MissionStatus
	super BridgeEntity
	serialize

	var mission_id: Int
	var player_id: Int
	var status_code: Int is writable
	var status: String is lazy do
		if status_code < 1 or status_code > 3 then return "locked"
		return context.mission_status[status_code - 1]
	end

	redef fun insert do return basic_insert("INSERT INTO mission_status(mission_id, player_id, status) VALUES ({mission_id}, {player_id}, {status_code})")

	redef fun update do return basic_update("UPDATE mission_status SET status = {status_code} WHERE player_id = {player_id} AND mission_id = {mission_id}")
end

redef class Player

	fun open_missions_count: Int do
		var res = context.try_select("COUNT(*) FROM mission_status WHERE mission_status.player_id = {id} AND mission_status.status = {context.mission_open} OR mission_status.status = {context.mission_success};")
		if res == null then return 0
		return res.get_count
	end

	fun open_missions: Array[Mission] do return context.mission_worker.fetch_multiple(context, "missions.* FROM missions, mission_status WHERE mission_status.player_id = {id} AND mission_status.status = {context.mission_open} AND mission_status.mission_id = missions.id;")

	fun successful_missions_count: Int do
		var res = context.try_select("COUNT(*) FROM mission_status WHERE mission_status.player_id = {id} AND mission_status.status = {context.mission_success}")
		if res == null then return 0
		return res.get_count
	end

	fun successful_missions: Array[Mission] do return context.mission_worker.fetch_multiple(context, "missions.* FROM missions, mission_status WHERE mission_status.player_id = {id} AND mission_status.status = {context.mission_success} AND mission_status.mission_id = missions.id")

end

# A single unit test on a mission
#
# They are provided by the author of the mission.
class TestCase
	serialize

	# The input that is feed to the tested program.
	var provided_input: String

	# The expected response from the program for `provided_input`.
	var expected_output: String

	# The number of the test in the test-suite (starting with 1)
	var number: Int
end
