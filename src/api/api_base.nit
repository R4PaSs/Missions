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

module api_base

import model
import config
import popcorn

abstract class APIHandler
	super Handler

	var config: AppConfig
end

class APIRouter
	super Router

	var config: AppConfig
end

redef class HttpRequest
	# The datbase context to which `self` is attached
	var ctx: DBContext is lazy do return new DBContext
end

abstract class PlayerHandler
	super APIHandler

	fun get_player(req: HttpRequest, res: HttpResponse): nullable Player do
		var pid = req.param("login")
		if pid == null then
			res.api_error("Missing URI param `login`", 400)
			return null
		end
		var player = null
		player = req.ctx.player_by_slug(pid)
		if player == null then res.api_error("Player `{pid}` not found", 404)
		return player
	end
end

abstract class TrackHandler
	super APIHandler

	fun get_track(req: HttpRequest, res: HttpResponse): nullable Track do
		var tid = req.param("tid")
		if tid == null then
			res.api_error("Missing URI param `tid`", 400)
			return null
		end
		var track = null
		track = req.ctx.track_by_slug(tid)
		if track == null then res.api_error("Track `{tid}` not found", 404)
		return track
	end
end

abstract class MissionHandler
	super APIHandler

	fun get_mission(req: HttpRequest, res: HttpResponse): nullable Mission do
		var mid = req.param("mid")
		if mid == null then
			res.api_error("Missing URI param `mid`", 400)
			return null
		end
		var mission = null
		mission = req.ctx.mission_by_slug(mid)
		if mission == null then res.api_error("Mission `{mid}` not found", 404)
		return mission
	end
end

redef class HttpResponse

	# Return a JSON error
	#
	# Format:
	# ~~~json
	# { message: "Not found", status: 404 }
	# ~~~
	fun api_error(message: String, status: Int) do
		var obj = new JsonObject
		obj["status"] = status
		obj["message"] = message
		json_error(obj, status)
	end
end
