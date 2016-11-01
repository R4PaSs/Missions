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

module players

import model::model_base

redef class DBContext

	fun player_worker: PlayerWorker do return once new PlayerWorker

	# Tries to find a player item from its `id`
	fun player_by_id(id: Int): nullable Player do return player_worker.fetch_one(self, "* FROM players WHERE id = {id};")

	# Gets the `limit` top players by score
	fun all_players: Array[Player] do return player_worker.fetch_multiple(self, "* FROM players;")

	# Gets a player by its slug
	fun player_by_slug(slug: String): nullable Player do return player_worker.fetch_one( self, "* FROM players WHERE slug = {slug.to_sql_string};")
end

class PlayerWorker
	super EntityWorker

	redef type ENTITY: Player

	redef fun entity_type do return "Player"

	redef fun expected_data do return once ["id", "slug", "name", "email", "avatar_url", "date_joined"]

	redef fun make_entity_from_row(ctx, row) do
		var m = row.map
		var id = m["id"].as(Int)
		var slug = m["slug"].as(String)
		var name = m["name"].as(String)
		var email = m["email"].as(String)
		var avatar_url = m["avatar_url"].as(String)
		var date = m["date_joined"].as(Int)
		var p = new Player(ctx, slug, name, email, avatar_url)
		p.id = id
		p.date_joined = date
		return p
	end
end

redef class Statement
	# Gets all the Player items from `self`
	#
	# Returns an empty array if none were found or if a row
	# was non-compliant with the construction of a Player
	fun to_players(ctx: DBContext): Array[Player] do
		return ctx.player_worker.
			fetch_multiple_from_statement(ctx, self)
	end
end

# Player representation
class Player
	super UniqueEntity
	serialize

	# The user-readable identifier
	var slug: String is writable

	# The screen name
	var name: String is writable

	# The email
	var email: String is writable

	# The image to use as avatar
	var avatar_url: String is writable

	# Date at which `self` has joined the game (UNIX Timestamp)
	var date_joined: Int = -1 is writable

	redef fun insert do
		if date_joined == -1 then date_joined = get_time
		return basic_insert("INSERT INTO players(slug, name, date_joined, email, avatar_url) VALUES({slug.to_sql_string}, {name.to_sql_string}, {date_joined}, {email.to_sql_string}, {avatar_url.to_sql_string});")
	end

	redef fun update do return basic_update("UPDATE players SET name = {name.to_sql_string}, email = {email.to_sql_string}, avatar_url = {avatar_url.to_sql_string} WHERE id = {id};")
end
