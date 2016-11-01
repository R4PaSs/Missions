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

import missions

redef class DBContext

	fun track_worker: TrackWorker do return once new TrackWorker

	fun track_status_worker: TrackStatusWorker do return once new TrackStatusWorker

	fun track_by_id(id: Int): nullable Track do return track_worker.fetch_one(self, "* FROM tracks WHERE id = {id};")

	fun track_by_slug(slug: String): nullable Track do return track_worker.fetch_one(self, "* FROM tracks WHERE slug = {slug.to_sql_string};")

	fun all_tracks: Array[Track] do return track_worker.fetch_multiple(self, "* FROM tracks;")

	## Track status codes

	fun track_open: Int do return 1
	fun track_success: Int do return 2

	##
end

redef class Statement

	# Gets all the Track items from `self`
	#
	# Returns an empty array if none were found or if a row
	# was non-compliant with the construction of a Track
	fun to_tracks(ctx: DBContext): Array[Track] do
		return ctx.track_worker.
			fetch_multiple_from_statement(ctx, self)
	end

	fun to_track_statuses(ctx: DBContext): Array[TrackStatus] do
		return ctx.track_status_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

class TrackWorker
	super EntityWorker

	redef type ENTITY: Track

	redef fun entity_type do return "Track"

	redef fun expected_data do return once ["id", "slug", "title", "description", "path"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var id = m["id"].as(Int)
		var slug = m["slug"].as(String)
		var title = m["title"].as(String)
		var desc = m["description"].as(String)
		var ret = new Track(ctx, title, desc, slug)
		if m["path"] != null then ret.path = m["path"].as(String)
		ret.id = id
		ret.load_languages
		return ret
	end
end

class TrackStatusWorker
	super EntityWorker

	redef type ENTITY: TrackStatus

	redef fun entity_type do return "TrackStatus"

	redef fun expected_data do return once ["track_id", "player_id", "status"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var tid = m["track_id"].as(Int)
		var pid = m["player_id"].as(Int)
		var status = m["status"].as(Int)
		var res = new TrackStatus(ctx, tid, pid, status)
		res.persisted = true
		return res
	end
end

class Track
	super UniqueEntity
	serialize

	var title: String
	var desc: String
	var slug: String

	# List of allowed languages
	var languages = new Array[String]

	var path: nullable String is writable

	fun load_languages do
		var res = context.try_select("languages.name FROM track_languages, languages WHERE track_languages.track_id = {id} AND languages.id = track_languages.language_id;")
		if res == null then return
		for i in res do languages.add(i[0].to_s)
	end

	redef fun to_s do return title

	fun missions: Array[Mission] do
		var db = context.connection
		var res = db.select("* FROM missions WHERE track_id = {id};")
		if res == null then return new Array[Mission]
		return res.to_missions(context)
	end

	fun status_for(player_id: Int): nullable TrackStatus do
		var st = context.track_status_worker.fetch_one(context, "* FROM track_statuses WHERE track_id = {id} AND player_id = {player_id};")
		if st == null then st = new TrackStatus(context, id, player_id, context.track_open)
		return st
	end

	fun mission_statuses_for(player_id: Int): Array[MissionStatus] do
		var mstats = context.mission_status_worker.fetch_multiple(context, "stat.* FROM mission_status AS stat, missions AS m WHERE stat.player_id = {player_id} AND m.track_id = {id} AND stat.mission_id = m.id;")
		var missions = missions
		for i in missions do
			var has_status = false
			for j in mstats do
				if i.id == j.mission_id then
					has_status = true
					break
				end
			end
			if not has_status then
				var s = i.status_for(player_id)
				if s != null then mstats.add s
			end
		end
		return mstats
	end

	fun mission_count: Int do
		var res = context.try_select("COUNT(*) FROM missions WHERE missions.track_id = {id}")
		if res == null then return 0
		return res.get_count
	end

	redef fun insert do
		var p = path
		if p != null then p = p.to_sql_string
		return basic_insert("INSERT INTO tracks(slug, title, description, path) VALUES ({slug.to_sql_string}, {title.to_sql_string}, {desc.to_sql_string}, {p or else "NULL"});")
	end

	redef fun update do
		var p = path
		if p != null then p = p.to_sql_string
		return basic_update("UPDATE tracks SET slug = {slug.to_sql_string}, title = {title.to_sql_string}, description = {desc.to_sql_string}, path = {p or else "NULL"} WHERE id = {id}")
	end
end

class TrackStatus
	super BridgeEntity
	serialize

	# The concerned track's id
	var track_id: Int
	# The player's id
	var player_id: Int
	# Track status
	#
	# Can be either:
	# 1 - Open
	# 2 - Success
	var status: Int
	# Number of missions in track `track_id`
	var missions_count: Int is lazy do
		var res = context.try_select("COUNT(*) FROM missions WHERE track_id = {track_id};")
		if res == null then return 0
		return res.get_count
	end
	# Number of missions completed for `player_id` in track `track_id`
	var missions_success: Int is lazy do
		var res = context.try_select("COUNT(*) FROM mission_status, missions WHERE mission_status.player_id = {player_id} AND mission_status.status = {context.mission_success} AND missions.track_id = {track_id} AND mission_status.mission_id = missions.id;")
		if res == null then return 0
		return res.get_count
	end
	# Mission statuses for track `track_id` and player `player_id
	var missions_status: Array[MissionStatus] is lazy do
		var track = context.track_by_id(track_id)
		if track == null then return new Array[MissionStatus]
		return track.mission_statuses_for(player_id)
	end

	redef fun insert do return basic_insert("INSERT INTO track_statuses(track_id, player_id, status) VALUES ({track_id}, {player_id}, {status});")

	redef fun update do return basic_update("UPDATE track_statuses SET status = {status} WHERE player_id = {player_id} AND track_id = {track_id}")

end

redef class Mission
	var track: nullable Track is lazy do return context.track_by_id(track_id)
end

redef class Player

	fun track_statuses: Array[TrackStatus] do
		var tracks = context.all_tracks
		var track_statuses = context.track_status_worker.fetch_multiple(context, "* FROM track_statuses WHERE player_id = {id};")
		var tmap = new HashMap[Int, TrackStatus]
		for i in track_statuses do tmap[i.track_id] = i
		for i in tracks do
			if tmap.has_key(id) then continue
			var stat = i.status_for(id)
			if stat == null then
				print "Error getting track status for track {i.id} and player {id}"
				return new Array[TrackStatus]
			end
			track_statuses.add stat
		end
		return track_statuses
	end
end
