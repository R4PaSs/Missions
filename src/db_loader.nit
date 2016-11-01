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

import model
import model::loader
import api

redef class DBContext
	fun player_count: Int do
		var db = connection
		var res = db.select("COUNT(*) FROM players;")
		if res == null then
			log_sql_error
			return 0
		end
		return res.get_count
	end

	fun track_count: Int do
		var db = connection
		var res = db.select("COUNT(*) FROM tracks;")
		if res == null then
			log_sql_error
			return 0
		end
		return res.get_count
	end
end

#var opts = new AppOptions.from_args(args)
#var config = new AppConfig.from_options(opts)

var level = 1
if args.length >= 1 then level = args[0].to_i

with ctx = new DBContext do
	# load some tracks and missions
	var track_count = 5 * level
	for i in [1..track_count] do
		var track = new Track(ctx, "Track {i}", "desc {i}", "track{i}")
		track.commit
		var last_missions = new Array[Mission]
		var mission_count = (10 * level).rand + 1
		for j in [1..mission_count] do
			var mission = new Mission(ctx, "track{i}:mission{j}", "Mission {i}-{j}", track.id, "desc {j}")
			print "Added mission {mission}"
			if last_missions.not_empty then
				var parents = new Array[Mission]
				if 100.rand > 75 then
					parents.add last_missions.last
				else
					parents.add last_missions.rand
				end
				if 100.rand > 50 then
					var rand = last_missions.rand
					if not parents.has(rand) then parents.add rand
				end
				mission.parents = parents
			end
			mission.commit
			var star_count = (4 * level).rand
			for s in [1..star_count] do
				var star = new MissionStar(ctx, "star{s} explanation", 100.rand, mission.id, 1)
				star.commit
			end
			last_missions.add mission
		end
	end

	ctx.load_tracks "tracks"

	# load some players
	var morriar = new Player(ctx, "Morriar", "Morriar", "morriar@dummy.cx", "https://avatars.githubusercontent.com/u/583144?v=3")
	morriar.commit
	var privat = new Player(ctx, "privat", "privat", "privat@dummy.cx", "https://avatars2.githubusercontent.com/u/135828?v=3")
	privat.commit

	# privat.ask_friend(config, morriar)
	var first_login = new FirstLoginAchievement(ctx)
	first_login.commit

	privat.add_achievement(first_login)
	print "privat got achievement"
	morriar.add_achievement(first_login)
	print "morriar got achievement"

	var request = new FriendRequest(ctx, privat.id, morriar.id)
	request.commit
	print "Friend request created"
	request.accept
	print "Friend request accepted"

	var aurl = "https://avatars.githubusercontent.com/u/2577044?v=3"
	var players = new Array[Player]
	players.push morriar
	players.push privat

	var player_count = 30 * level
	for i in [0..player_count] do
		var p = new Player(ctx, "P{i}", "Player{i}", "dummy@dummy.cx", aurl)
		players.push p
		p.commit
	end

	for player in players do
		# Spread some love (or friendships =( )
		for other_player in players do
			if other_player != player and not player.has_friend(other_player.id) then
				var love = 10.rand
				if love == 1 then
					print "Making {player.id} friend with {other_player.id}"
					var rq = new FriendRequest(ctx, player.id, other_player.id)
					rq.commit
					print "Request commited"
					rq.accept
					print "Request accepted"
				end
			end
		end
	end

	print "Loaded {ctx.track_count} tracks"
	print "Loaded {ctx.mission_count} missions"
	print "Loaded {ctx.player_count} players"
	#print "Loaded {} missions status"
end
