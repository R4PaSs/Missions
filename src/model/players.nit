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

import config
import popcorn::pop_auth

redef class AppConfig
	var players = new PlayerRepo(db.collection("players")) is lazy
end

# Player representation
#
# Each player is linked to a Github user
class Player
	serialize
	super Jsonable

	var id: String is lazy, serialize_as "_id" do return user.login

	# github user linked to this player
	var user: User

	redef fun to_s do return id
	redef fun ==(o) do return o isa SELF and id == o.id
	redef fun hash do return id.hash
	redef fun to_json do return serialize_to_json
end

class PlayerRepo
	super MongoRepository[Player]

	fun find_by_user(user: User): nullable Player do return find_by_id(user.login)
end