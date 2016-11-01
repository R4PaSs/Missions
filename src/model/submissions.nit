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

# Player's submissions for any kind of mission
module submissions

import stars
import players
import loader
private import markdown
private import poset

redef class DBContext
	## Submission status codes

	# Submission submitted code
	fun submission_submitted: Int do return 1

	# Submission pending code
	fun submission_pending: Int do return 2

	# Submission successful code
	fun submission_success: Int do return 3

	# Submission error code
	fun submission_error: Int do return 4

	##

	# Mapping between verbatim status and database ID
	protected var submission_statuses = new HashMap[String, Int]

	init do
		submission_statuses["submitted"] = submission_submitted
		submission_statuses["pending"] = submission_pending
		submission_statuses["success"] = submission_success
		submission_statuses["error"] = submission_error
	end
end

# An entry submitted by a player for a mission.
#
# The last submitted programs and/or the ones that beat stars
# can be saved server-side so that the played can retrieve them.
#
# Other can be discarded (or archived for data analysis and/or the wall of shame)
class Submission
	super Event
	serialize

	# The submitter
	var player_id: Int

	# The attempted mission
	var mission_id: Int

	# Get the mission linked to the mission id
	var mission: nullable Mission is lazy, noserialize do return context.mission_by_id(mission_id)

	# The submitted source code
	var source: String

	# Unlocked missions if success and if any
	var next_missions: nullable Array[Mission] = null

	# All information about the compilation
	var compilation: CompilationResult is lazy do return new CompilationResult

	# Individual results for each test case
	#
	# Filled by `check`
	var results = new Array[TestResult]

	# The status of the submission
	#
	# * `submitted` initially.
	# * `pending` when `check` is called.
	# * `success` compilation and tests are fine.
	# * `error` compilation or tests have issues.
	var status: String = "submitted" is writable

	# The name of the working directory.
	# It is where the source is saved and artifacts are generated.
	var workspace: nullable String = null is writable, noserialize

	# Object file size in bytes.
	#
	# Use only if status == "success".
	var size_score: nullable Int = null is writable

	# Total execution time.
	#
	# Use only if status == "success".
	var time_score: nullable Int = null is writable

	# Number of failed test-cases
	var test_errors: Int = 0 is writable

	# Was the run successful?
	fun successful: Bool do return not compilation.is_error and test_errors == 0

	# Was the run the first solve?
	var is_first_solve = false

	# The aggregated mission status after the submission
	var mission_status: nullable MissionStatus = null

	# The results of each star
	var star_results = new Array[StarResult]

	redef fun to_json do return serialize_to_json

	redef fun insert do
		var ws = workspace or else "null"
		var stat = context.submission_statuses.get_or_null(status)
		if stat == null then
			print "Error when inserting submission: Unknown status"
			return false
		end
		if not (super and basic_insert("INSERT INTO submissions(event_id, player_id, mission_id, workspace_path, status) VALUES ({id}, {player_id}, {mission_id}, {ws.to_sql_string}, {if successful then context.submission_success else context.submission_error});")) then return false
		if successful then
			var m = mission
			if m == null then return false
			m.success_for(player_id)
		end
		return true
	end
end

# This model provides easy deserialization of posted submission forms
class SubmissionForm
	serialize

	# Source code to be run
	var source: String
	# Engine or runner to be used
	var engine: String
	# Language in which the source code is written
	var lang: String
end

redef class MissionStar

	# The current best score for the star result
	fun best_score(player_id: Int): nullable Int do
		var db = context.connection
		var res = db.select("star_results.score FROM star_results, submissions WHERE star_id = {id} AND submissions.event_id = star_results.submission_id AND submissions.player_id = {player_id} ORDER BY score DESC LIMIT 1;")
		if res == null then return null
		var cnt = res.get_count
		if cnt == 0 then return null
		return cnt
	end

	# Check if the star is unlocked for the `submission`
	# Also update `status`
	fun check(submission: Submission): Bool do
		if not submission.successful then
			print "Submission unsuccessful"
			return false
		end
		# Since we are adding data to the DB which are related
		# to a submission, its id must be set, hence the submission
		# must be commited before checking for stars
		assert submission.id != -1
		var score = self.score(submission)
		if score == null then
			print "No score registered"
			return false
		end

		# Search or create the corresponding StarStatus
		var star_status = status(submission.player_id)
		if star_status == null then star_status = new StarStatus(context, submission.player_id, id)
		var star_result = new StarResult(context, submission.id, id, score)

		var changed = false

		# Best score?
		var best = best_score(submission.player_id)
		star_result.old_score = best

		# Best score?
		if best == null or score < best then
			if best != null then
				star_result.is_highscore = true
			end
			changed = true
		end

		# Star granted?
		if not star_status.is_unlocked and score <= goal then
			star_status.is_unlocked = true
			star_result.is_unlocked = true
			changed = true
		end

		star_status.commit
		star_result.commit
		submission.star_results.add star_result
		return changed
	end

	# The specific score in submission associated to `self`
	fun score(submission: Submission): nullable Int is abstract

	# The key in the Submission object used to store the star `score`
	#
	# So we can factorize things in the HTML output.
	fun submission_key: String is abstract
end

redef class TimeStar
	serialize

	redef fun score(submission) do return submission.time_score
	redef var submission_key = "time_score"
end

redef class SizeStar
	serialize

	redef fun score(submission) do return submission.size_score
	redef var submission_key = "size_score"
end

# The specific information about compilation (or any internal affair)
class CompilationResult
	serialize

	# The title of the box
	var title = "Compilation" is writable

	# The compilation message, if any
	var message: nullable String = null is writable

	# The compilation failed, for some reason
	var is_error = false is writable
end

# A specific execution of a test case by a submission
class TestResult
	serialize

	# The test case considered
	var testcase: TestCase

	# The output of the `submission` when fed by `testcase.provided_input`.
	var produced_output: nullable String = null is writable

	# Error message
	# Is `null` if success
	var error: nullable String = null is writable

	# Result diff (if any)
	var diff: nullable String = null is writable

	# Execution time
	var time_score: Int = 0 is writable
end

# The specific submission result on a star
# Unlike the star status, this shows what is *new*
class StarResult
	super UniqueEntity
	serialize

	# The associated submission id
	var submission_id: Int

	# The associated star id
	var star_id: Int

	# The star associated to result
	var star: nullable MissionStar is lazy do return context.star_by_id(star_id)

	# The new score
	var score: Int

	# Is the star unlocked?
	var is_unlocked = false

	# Is the new_score higher than then old_score?
	var is_highscore = false

	# Old best score, if exists
	var old_score: nullable Int

	redef fun to_s do
		var st = star
		var title = "Unknown star"
		if st != null then title = st.title
		var res = "STAR {title}"
		if is_unlocked then
			res += " UNLOCKED!"
		else if is_highscore then
			res += " NEW BEST SCORE!"
		end

		if st != null then
			res += " goal: {st.goal}"
		end
		res += " score: {score}"

		var old_score = self.old_score
		if old_score != null then
			res += " (was {old_score})"
		end
		return res
	end

	redef fun insert do return basic_insert("INSERT INTO star_results(submission_id, star_id, score) VALUES ({submission_id}, {star_id}, {score});")
end
