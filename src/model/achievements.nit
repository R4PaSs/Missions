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

module achievements

import model::notifications

redef class DBContext
	fun achievement_worker: AchievementWorker do return once new AchievementWorker

	# Gets an `Achievement` by its `id`
	fun achievement_by_id(id: Int): nullable Achievement do return achievement_worker.fetch_one(self, "* FROM achievements WHERE id = {id};")

	fun achievement_by_slug(slug: String): nullable Achievement do return achievement_worker.fetch_one(self, "* FROM achievements WHERE slug = {slug.to_sql_string};")

	fun all_achievements: Array[Achievement] do return achievement_worker.fetch_multiple(self, "* FROM achievements;")
end

redef class Statement
	# Gets all the Achievement items from `self`
	#
	# Returns an empty array if none were found or if a row
	# was non-compliant with the construction of an Achievement
	fun to_achievements(ctx: DBContext): Array[Achievement] do
		return ctx.achievement_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

class AchievementWorker
	super EntityWorker

	redef type ENTITY: Achievement

	redef fun entity_type do return "Achievement"

	redef fun expected_data do return once ["id", "slug", "title", "description", "reward"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var id = m["id"].as(Int)
		var slug = m["slug"].as(String)
		var title = m["title"].as(String)
		var desc = m["description"].as(String)
		var reward = m["reward"].as(Int)
		var ach = new Achievement(ctx, title, desc, reward)
		ach.slug = slug
		ach.id = id
		return ach
	end
end

# Notable acts performed by players.
class Achievement
	super UniqueEntity
	serialize

	# Key name for `self`
	var slug: String is lazy do return title.strip_id

	# Achievement title (should be short and punchy)
	var title: String is writable(set_title)

	# Achievement description (explains how to get this achievement)
	var desc: String

	# Reward for unlocking the achievement
	var reward: Int

	fun title=(title: String) do
		set_title title
		slug = title.strip_id
	end

	# List players who unlocked `self`
	fun players: Array[Player] do
		if id == -1 then return new Array[Player]
		return context.player_worker.fetch_multiple(context, "players.* FROM achievement_unlocks AS unlocks, players WHERE unlocks.achievement = {id} AND unlocks.player_id = players.id;")
	end

	redef fun insert do return basic_insert("INSERT INTO achievements(slug, title, description, reward) VALUES ({slug.to_sql_string}, {title.to_sql_string}, {desc.to_sql_string}, {reward});")

	redef fun update do return basic_update("UPDATE achievements SET title = {title.to_sql_string}, slug = {slug.to_sql_string}, description = {desc.to_sql_string}, WHERE id = {id};")
end

redef class Player
	serialize

	# Does `self` already unlocked `achievement`?
	fun has_achievement(achievement: Achievement): Bool do
		var res = context.try_select("COUNT(*) FROM achievement_unlocks WHERE player_id = {id} AND achievement_id = {achievement.id};")
		return res != null and res.get_count == 1
	end

	# Lists all achievements unlocked by `self`
	fun achievements: Array[Achievement] do return context.achievement_worker.fetch_multiple(context, "a.* FROM achievements AS a, achievement_unlocks AS unlocks WHERE unlocks.player_id = {id} AND a.id = unlocks.achievement_id;")

	# Unlocks `achievement` for `self`
	#
	# Return false if `self` already unlocked `achievement`
	fun add_achievement(achievement: Achievement): Bool do
		if has_achievement(achievement) then return false
		var unlock = new AchievementUnlock(context, achievement.id, id)
		if not unlock.commit then return false
		var notif = new AchievementUnlocked(context, unlock.id, id, achievement)
		return notif.commit
	end

	# How many achievements have been unlocked?
	fun achievement_count: Int do
		var res = context.try_select("COUNT(*) FROM achievement_unlocks WHERE player_id = {id};")
		if res == null then return 0
		return res.get_count
	end
end

class AchievementUnlock
	super Event

	var achievement_id: Int
	var player_id: Int

	redef fun insert do return super and basic_insert("INSERT INTO achievement_unlocks(event_id, achievement_id, player_id) VALUES ({id}, {achievement_id}, {player_id})")
end

class AchievementUnlocked
	super PlayerNotification
	serialize

	redef var object = "Achievement unlocked"
	redef var body is lazy do return "You unlocked a new achievement: {achievement.title}"
	redef var icon = "check"

	# The achievement unlocked
	var achievement: Achievement
end
