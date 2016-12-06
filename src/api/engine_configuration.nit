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

# Global map of engines
module engine_configuration

import model::engines

redef class AppConfig
	# Map of all supported engines for problem solving
	var engine_map = new HashMap[String, Engine]

	redef init do
		super
		engine_map["pep8term"] = new Pep8Engine
	end
end
