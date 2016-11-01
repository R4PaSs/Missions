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

module stats

import model::stars
import model::achievements

redef class DBContext
	fun players_ranking: Array[PlayerStats] do
		var pls = all_players
		var stats = new Array[PlayerStats]
		for i in pls do stats.add(i.stats)
		return stats
	end

	fun mission_count: Int do
		var res = try_select("COUNT(*) FROM missions;")
		if res == null then return 0
		return res.get_count
	end

	fun star_count: Int do
		var res = try_select("COUNT(*) FROM stars;")
		if res == null then return 0
		return res.get_count
	end
end

redef class Player

	fun achievement_score: Int do
		var res = context.try_select("SUM(a.reward) FROM achievements AS a, achievement_unlocks AS au WHERE au.player_id = {id} AND au.achievement_id = a.id;")
		if res == null then return 0
		return res.get_count
	end

	fun mission_score: Int do
		var res = context.try_select("SUM(m.reward) FROM missions AS m, mission_status AS ms WHERE ms.player_id = {id} AND ms.mission_id = m.id AND ms.status = {context.mission_success}")
		if res == null then return 0
		return res.get_count
	end

	fun star_score: Int do
		var res = context.try_select("SUM(s.reward) FROM stars AS s, star_status AS ss WHERE ss.player_id = {id} AND ss.status = 1 AND ss.star_id = s.id;")
		if res == null then return 0
		return res.get_count
	end

	fun score: Int do return achievement_score + mission_score + star_score

	fun stats: PlayerStats do
		var stats = new PlayerStats(context, self)
		stats.achievements = achievement_count
		stats.missions_count = context.mission_count
		stats.missions_open = open_missions_count
		stats.missions_success = successful_missions_count
		stats.missions_locked = stats.missions_count - (stats.missions_open + stats.missions_success)
		stats.stars_count = context.star_count
		stats.stars_unlocked = star_count
		return stats
	end
end

class PlayerStats
	super Comparable
	super Entity
	serialize

	redef type OTHER: PlayerStats

	var player: Player

	var score: Int is lazy do return player.score
	var achievements = 0
	var missions_count = 0
	var missions_locked = 0
	var missions_open = 0
	var missions_success = 0
	var stars_count = 0
	var stars_unlocked = 0

	redef fun <=>(o) do return o.score <=> score
end
