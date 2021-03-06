isLoading = new ReactiveVar

Template.firstLogin.helpers

	user: ->
		token = FlowRouter.getQueryParam('token')
		Meteor.users.findOne 'services.password.reset.token': token

	getErrorMessage: -> Session.get('errorMessage')

	isLoading: -> isLoading.get()

Template.firstLogin.onCreated ->

	isLoading.set true

	@autorun ->
		token = FlowRouter.getQueryParam('token')

		if token? && token != ''
			handle = Meteor.subscribe 'userByToken', token
			isLoading.set(handle.ready())

Template.firstLogin.events

	'change #username': (e) ->
		$('#username').val(Validations.cleanedUsername(e.target.value))

	'submit form': (event) ->
		event.preventDefault()

		username = Validations.cleanedUsername($('#username').val())
		password1 = $('#password1').val()
		password2 = $('#password2').val()
		agreeTerms = $('#agreeTerms').prop('checked')
		token = FlowRouter.getQueryParam('token')

		if token
			if agreeTerms
				if username
					if Meteor.areValidPasswords password1, password2
						Meteor.call 'usernameAvailable', username, (err, res) ->
							if res
								Meteor.call 'userFirstLogin', token, username, password1, (err, res) ->
									if typeof res == 'object' && res.done
										Meteor.loginWithPassword username, password1, -> FlowRouter.go 'home'
									else
										Session.set 'errorMessage', TAPi18n.__('firstLogin.tokenError')
							else
								Session.set 'errorMessage', TAPi18n.__('firstLogin.usernameExists')
				else
					Session.set 'errorMessage', TAPi18n.__('firstLogin.usernameMissing')
			else
				Session.set 'errorMessage', TAPi18n.__('firstLogin.agreeTermsMissing')
		else
			Session.set 'errorMessage', TAPi18n.__('firstLogin.tokenMissing')
