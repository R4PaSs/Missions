# Test program to run some headless scenarios on the pep missions
#
# TODO: use nitunit to check the result
module test_pep

import model
import model::loader
import submissions
import api

var config = new AppConfig
config.parse_options(args)

with ctx = new DBContext do
	# Create a dummy user
	var player = new Player(ctx, "pep_doe", "Pep Doe", "john.doe@unknown.ld", "avatar.cx")
	player.commit

	# Run some submission on the missions
	var mission = ctx.mission_by_slug("pep8:addition_simple")
	if mission == null then return
	do
		print "Mission {mission} {mission.testsuite.length}"
		var i = 0
		for source in [
	"""
	""",
	"""
	DECO 10,i
	.END
	""",
	"""
	DECI n,d
	LDA n,d
	ADDA 10,i
	STA n,d
	DECO n,d
	STOP
	n: .BLOCK 3
	.END
	""",
	"""
	DECI n,d
	LDA n,d
	ADDA 10,i
	STA n,d
	DECO n,d
	STOP
	n: .BLOCK 2
	.END
	""",
	"""
	DECI 0,d
	LDA 0,d
	ADDA 10,i
	STA 0,d
	DECO 0,d
	STOP
	.END
	"""
	] do
			print "## Try source {i} ##"
			var sub = new Submission(ctx, player.id, mission.id, source)
			var runner = config.engine_map["pep8term"]
			runner.run(sub)
			print "** {sub.status} errors={sub.test_errors}/{sub.results.length} size={sub.size_score or else "-"} time={sub.time_score or else "-"}"
			var msg = sub.compilation.message
			if msg != null then print "{msg}"
			for res in sub.results do
				var msg_test = res.error
				if msg_test != null then print "test {res.testcase.number}. {msg_test}"
			end
			for e in sub.star_results do
				print e
			end
			i += 1
		end
	end
end
