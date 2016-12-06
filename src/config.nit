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

module config

import popcorn::pop_config
import popcorn::pop_repos

redef class AppConfig

	# Github client id used for Github OAuth login.
	fun gh_client_id: String do return ini["github.client.id"] or else ""

	# Github client secret used for Github OAuth login.
	fun gh_client_secret: String do return ini["github.client.secret"] or else ""

	# Site root url to use for some redirect
	# Useful if behind some reverse proxy
	var app_root_url: String is lazy do
		var host = app_host
		var port = app_port
		var url = "http://{host}"
		if port != 80 then url += ":{port}"
		return ini["app.root_url"] or else url
	end
end
