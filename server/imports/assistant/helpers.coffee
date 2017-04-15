import { R } from './variables.coffee'

export Helpers =

	logExplanation: ->
		console.log 'AverageRatio   +/- averageDeviationRatio [abandonedTeamsTl] (abandonedTeamsUsers)'
		true

	log: ->
		averageRatio = '' + Math.round (1000 * @getAverageRatioAll()) / 10
		averageDeviationRatio = '' + Math.round (1000 * @getAverageDeviationRatioAll()) / 10
		if averageRatio.length < 3 then averageRatio += '.0'
		if averageDeviationRatio.length < 3 then averageDeviationRatio += '.0'
		textAverageRatio = '' + averageRatio + "%"
		textAverageDeviationRatio = '   +/- ' + averageDeviationRatio + "%"
		textAbandonedTeamsTl = ' [' + @countAbandonedTeamsTl() + ']'
		textAbandonedTeamsUsers = ' (' + @countAbandonedTeamsUsers() + ')'

		console.log textAverageRatio + textAverageDeviationRatio + textAbandonedTeamsTl + textAbandonedTeamsUsers
		true

	pendingToParticipants: (shiftId, teamId, userId, teamleader) ->

		user = {}

		# User verschieben
		for team in R.teams when team.shiftId == shiftId && team._id == teamId

			# Participants prüfen
			for u in team.participants when u._id == userId
				console.log u.name + ' bereits in participants'
				return

			# Userdaten holen
			for u in team.pending when u._id == userId
				user = u
				user.thisTeamleader = teamleader
				break
			# Gefundenen user überprüfen
			if user == {}
				console.log u.name + ' nicht in pending gefunden'
				return
			else
				maxReachedDay = @getMaxReachedDay user._id, team
				maxReachedPeriod = @getMaxReachedPeriod user._id

				if maxReachedDay
					console.log u.name + ' bereits am Tages Maximum at ' + team.shiftId
					throw new Meteor.Error 'Tagesmaxium'
					return
				else if maxReachedPeriod
					console.log u.name + ' bereits am Maximum at ' + team.shiftId
					return

			R.doneWaypoints.push type: 'pendingToParticipants', waypoint:
				shiftId: shiftId
				teamId: teamId
				fromId: ''
				toId: userId
				tlChange: teamleader

			team['participants'].push user

			team.pending = team.pending.filter (u) -> u._id != userId

		# Acceptions erhöhen
		R.users[userId].acceptions += 1

		# Schicht in confirmation Arrays aufnehmen
		R.users[userId].allConfirmations.push shiftId: shiftId, teamId: teamId

		if user.thisTeamleader
			R.users[userId].tlConfirmations.push shiftId: shiftId, teamId: teamId
		else
			R.users[userId].partConfirmations.push shiftId: shiftId, teamId: teamId

		# Ratio errechnen
		R.users[userId].targetAcceptionRatio = R.users[userId].acceptions / R.users[userId].targetPeriod
		true

	participantsToPending: (shiftId, teamId, userId) ->

		user = {}

		# User verschieben
		for team in R.teams when team.shiftId == shiftId && team._id == teamId

			# Pending prüfen
			for u in team.pending when u._id == userId
				console.log u.name + ' bereits in pending'
				return

			# Userdaten holen
			for u in team.participants when u._id == userId
				user = u
				break

			teamleader = user.thisTeamleader
			user.thisTeamleader = false

			# Gefundenen user überprüfen
			if user == {}
				console.log u.name + ' nicht in participants gefunden'
				return

			team['pending'].push user

			R.doneWaypoints.push type: 'participantsToPending', waypoint:
				shiftId: shiftId
				teamId: teamId
				fromId: userId
				toId:  ''
				tlChange: teamleader

			team.participants = team.participants.filter (u) -> u._id != userId

		# Acceptions senken
		R.users[userId].acceptions -= 1

		# Schicht aus confirmation Arrays entfernen
		R.users[userId].allConfirmations = R.users[userId].allConfirmations.filter (c) -> !(c.shiftId == shiftId && c.teamId == teamId)
		R.users[userId].tlConfirmations = R.users[userId].tlConfirmations.filter (c) -> !(c.shiftId == shiftId && c.teamId == teamId)
		R.users[userId].partConfirmations = R.users[userId].partConfirmations.filter (c) -> !(c.shiftId == shiftId && c.teamId = teamId)

		# Ratio errechnen
		R.users[userId].targetAcceptionRatio = R.users[userId].acceptions / R.users[userId].targetPeriod
		true

	searchChangeables: (userId) ->

		foundUsers = []
		runCondition = true
		i = 0

		# Aktuellen User in foundUsers aufnehmen
		foundUsers.push _id: userId, way: []

		while runCondition
			if foundUsers.length <= i
				runCondition = false
			else
				foundUser = foundUsers[i]

				if foundUser._id in foundUsers.map((f, index) -> f._id if index < i && !f.maxReachedDay)
					i++
					continue

				# Alle Teams durchgehen, wo er schon als Teilnehmer angenommen ist
				for team in R.users[foundUser._id].allConfirmations
					team = (R.teams.filter (t) -> t._id == team.teamId && t.shiftId == team.shiftId)[0]
					if team.participants.filter((user) -> user._id == foundUser._id).length == 0 then console.log "FEHLER"

					# Erst ausführen, wenn foundUsers bereits wirklich gefundene Tausch-Kandidaten enthält
					if i > 0
						# foundUserTeam ist das Team, in dem der foundUser als Teilnehmer eingetragen werden soll
						foundUserTeam = (R.teams.filter (t) -> t._id == foundUser.way[foundUser.way.length - 1].teamId && t.shiftId == foundUser.way[foundUser.way.length - 1].shiftId)[0]

						# Wenn der foundUser dort, wo er als Teilnehmer eingetragen werden soll, maxReachedDay erreicht hat, muss er auch an diesem Tag eine Schicht abgeben
						continue if foundUser.maxReachedDay && team.date != foundUserTeam.date

					teamleader = team.participants.filter((user) -> user._id == foundUser._id && user.thisTeamleader).length > 0

					for rUser in team.pending
						R.count++
						# übermittelten User nicht mit siche selbst tauschen lassen
						continue if rUser._id == userId
						# User mit einer Doppelschicht an dem Tag nicht berücksichtigen
						continue if @getDoubleShiftOnDay rUser._id, team.date
						# Prüfung nach Teamleiterwechsel
						continue if teamleader && !(rUser.teamleader || rUser.substituteTeamleader)
						# Prüfung ob noch nicht in foundUsers aufgenommen
						alreadyFoundUser = foundUsers.filter (foundUser) -> foundUser._id == rUser._id
						thisTeam = teamId: team._id, shiftId: team.shiftId
						foundTeams = alreadyFoundUser.map((f) -> shiftId: f.way[f.way.length - 1].shiftId, teamId: f.way[f.way.length - 1].teamId)
						continue if thisTeam in foundTeams

						# User in foundUsers aufnehmen
						foundUsers.push
							_id: rUser._id
							maxReachedDay: @getMaxReachedDay rUser._id, team
							way: foundUser.way.concat [
								shiftId: team.shiftId
								teamId: team._id
								fromId: foundUser._id
								toId: rUser._id
								tlChange: teamleader
							]
			i++

		# Den User, von dem wir ausgegangen sind, aus den Ergebnissen entfernen
		foundUsers.splice 0, 1

		# Alle User entfernen, deren Maximum erreicht ist
		foundUsers.filter (foundUser) => !(foundUser.maxReachedDay) && !(@getMaxReachedPeriod foundUser._id)

	countAbandonedTeamsTl: ->

		count = 0

		# Teams zählen, die einen möglichen Teamleiter haben
		for team in R.teams
			hasTeamleader = false

			for user in team.participants when user.teamleader || user.substituteTeamleader
				hasTeamleader = true

			if !hasTeamleader
				count++
		count

	countAbandonedTeamsUsers: ->

		# Teams zählen, die weniger angenommene Bewerbungen haben, als notwendig
		(R.teams.filter (team) -> team.participants.length < team.min).length

	getAverageDeviationRatioTl: ->

		teamleaders = []
		sumDeviation = 0.0
		averageRatio = @getAverageRatioTl()

		for userId in Object.keys(R.users) when R.users[userId].teamleader || R.users[userId].substituteTeamleader
			sumDeviation += Math.abs R.users[userId].targetAcceptionRatio - averageRatio

			teamleaders.push R.users[userId]

		sumDeviation / Object.keys(teamleaders).length

	getAverageDeviationRatioAll: ->

		sumDeviation = 0.0
		averageRatio = @getAverageRatioAll()

		for userId in Object.keys R.users
			sumDeviation += Math.abs R.users[userId].targetAcceptionRatio - averageRatio

		(Math.round 100000 * sumDeviation / Object.keys(R.users).length) / 100000

	getAverageRatioTl: ->

		sumRatio = 0
		teamleaders = []

		for userId in Object.keys(R.users) when R.users[userId].teamleader || R.users[userId].substituteTeamleader
			teamleaders.push R.users[userId]
			sumRatio += R.users[userId].targetAcceptionRatio

		sumRatio / Object.keys(teamleaders).length

	getAverageRatioAll: ->

		sumRatio = 0

		for userId in Object.keys R.users
			sumRatio += R.users[userId].targetAcceptionRatio

		sumRatio / Object.keys(R.users).length

	wouldBeMaxReachedDay: (userId, team) ->
		# TODO: Wird die Funktion gebraucht?

		maxReachedDay = false
		confirmationsThisDay = []
		cTeams = R.users[userId].allConfirmations.map (cTeam) ->
			shiftId: cTeam.shiftId
			teamId: cTeam.teamId
			date: R.teams.filter((fTeam) -> fTeam.shiftId == cTeam.shiftId && fTeam._id == cTeam.teamId)[0].date

		cTeams.push
			shiftId: team.shiftId
			teamId: team.teamId
			date: R.teams.filter((fTeam) -> fTeam.shiftId == team.shiftId && fTeam._id == team.teamId)[0].date

		# Alle angenommenen Bewerbungen dieses Tages zusammenfassen
		for cTeam in cTeams when team.date == cTeam.date
			# Schicht in confirmationsThisDay aufnehmen, wenn noch nicht gemacht
			if confirmationsThisDay.filter((confirmation) -> confirmation.shiftId == cTeam.shiftId).length == 0
				confirmationsThisDay.push cTeam

		# TODO: parallelConfirmations auch in den Methoden der assisant prüfen, am besten seperat
		if confirmationsThisDay.length > 0
			parallelConfirmations = confirmationsThisDay.filter (t) ->
				t = R.teams.filter((fTeam) -> fTeam.shiftId == t.shiftId && fTeam._id == t.teamId)[0]

				(team.start > t.start && team.start < t.end) ||
				(team.end > t.start && team.end < t.end) ||
				(t.start > team.start && t.start < team.end) ||
				(t.end > team.start && t.end < team.end) ||
				(t.start == team.start && t.end == team.end)

			if parallelConfirmations.length > 0
				maxReachedDay = true

		# Anzahl der angenommenen Bewerbungen (und ggf. auf Doppelschicht) prüfen
		if confirmationsThisDay.length == 1
			if R.users[userId].maxDay == 1
				if !R.users[userId].doubleShiftAllowed
					maxReachedDay = true
				else
					thisShift = R.shifts.filter((shift) -> shift._id == confirmationsThisDay[0].shiftId)[0]

					if thisShift.start != team.end && thisShift.end != team.start
						maxReachedDay = true
		else if confirmationsThisDay.length > 1 && confirmationsThisDay.length >= R.users[userId].maxDay
			maxReachedDay = true

	getMaxReachedDay: (userId, team) ->

		maxReachedDay = false
		confirmationsThisDay = []
		cTeams = R.users[userId].allConfirmations.map (cTeam) ->
			shiftId: cTeam.shiftId
			teamId: cTeam.teamId
			date: R.teams.filter((fTeam) -> fTeam.shiftId == cTeam.shiftId && fTeam._id == cTeam.teamId)[0].date

		# Alle angenommenen Bewerbungen dieses Tages zusammenfassen
		for cTeam in cTeams when team.date == cTeam.date
			# Schicht in confirmationsThisDay aufnehmen, wenn noch nicht gemacht
			if confirmationsThisDay.filter((confirmation) -> confirmation.shiftId == cTeam.shiftId).length == 0
				confirmationsThisDay.push cTeam

		# TODO: parallelConfirmations auch in den Methoden der assisant prüfen, am besten seperat
		if confirmationsThisDay.length > 0
			parallelConfirmations = confirmationsThisDay.filter (t) ->
				t = R.teams.filter((fTeam) -> fTeam.shiftId == t.shiftId && fTeam._id == t.teamId)[0]

				(team.start > t.start && team.start < t.end) ||
				(team.end > t.start && team.end < t.end) ||
				(t.start > team.start && t.start < team.end) ||
				(t.end > team.start && t.end < team.end) ||
				(t.start == team.start && t.end == team.end)

			if parallelConfirmations.length > 0
				maxReachedDay = true

		# Anzahl der angenommenen Bewerbungen (und ggf. auf Doppelschicht) prüfen
		if confirmationsThisDay.length == 1
			if R.users[userId].maxDay == 1
				if !R.users[userId].doubleShiftAllowed
					maxReachedDay = true
				else
					thisShift = R.shifts.filter((shift) -> shift._id == confirmationsThisDay[0].shiftId)[0]

					if thisShift.start != team.end && thisShift.end != team.start
						maxReachedDay = true
		else if confirmationsThisDay.length > 1 && confirmationsThisDay.length >= R.users[userId].maxDay
			maxReachedDay = true

		maxReachedDay

	getDoubleShiftOnDay: (userId, date) ->
		# TODO: Mit als weiterer Rückgabewert in getMaxReachedDay?
		doubleShift = false
		confirmationsThisDay = []
		cTeams = R.users[userId].allConfirmations.map (cTeam) ->
			shiftId: cTeam.shiftId
			teamId: cTeam.teamId
			date: R.teams.filter((fTeam) -> fTeam.shiftId == cTeam.shiftId && fTeam._id == cTeam.teamId)[0].date

		# Alle angenommenen Bewerbungen dieses Tages zusammenfassen
		for cTeam in cTeams when date == cTeam.date
			# Schicht in confirmationsThisDay aufnehmen, wenn noch nicht gemacht
			if confirmationsThisDay.filter((confirmation) -> confirmation.shiftId == cTeam.shiftId).length == 0
				confirmationsThisDay.push cTeam

		# Anzahl der angenommenen Bewerbungen und auf Doppelschicht prüfen
		if confirmationsThisDay.length == 2 && R.users[userId].maxDay == 1 && R.users[userId].doubleShiftAllowed
			doubleShift = true

		doubleShift

	getMaxReachedPeriod: (userId) -> R.users[userId].acceptions >= R.users[userId].maxPeriod