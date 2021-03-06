class Sidebar extends Class
	constructor: ->
		@tag = null
		@container = null
		@opened = false
		@width = 410
		@fixbutton = $(".fixbutton")
		@fixbutton_addx = 0
		@fixbutton_initx = 0
		@fixbutton_targetx = 0
		@frame = $("#inner-iframe")
		@initFixbutton()
		@dragStarted = 0
		@globe = null

		@original_set_site_info = wrapper.setSiteInfo  # We going to override this, save the original

		# Start in opened state for debugging
		if false
			@startDrag()
			@moved()
			@fixbutton_targetx = @fixbutton_initx - @width
			@stopDrag()


	initFixbutton: ->
		# Detect dragging
		@fixbutton.on "mousedown", (e) =>
			e.preventDefault()

			# Disable previous listeners
			@fixbutton.off "click"
			@fixbutton.off "mousemove"

			# Make sure its not a click
			@dragStarted = (+ new Date)
			@fixbutton.one "mousemove", (e) =>
				@fixbutton_addx = @fixbutton.offset().left-e.pageX
				@startDrag()
		@fixbutton.parent().on "click", (e) =>
			@stopDrag()
		@fixbutton_initx = @fixbutton.offset().left  # Initial x position


	# Start dragging the fixbutton
	startDrag: ->
		@log "startDrag"
		@fixbutton_targetx = @fixbutton_initx  # Fallback x position

		@fixbutton.addClass("dragging")

		# Fullscreen drag bg to capture mouse events over iframe
		$("<div class='drag-bg'></div>").appendTo(document.body)

		# IE position wrap fix
		if navigator.userAgent.indexOf('MSIE') != -1 or navigator.appVersion.indexOf('Trident/') > 0
			@fixbutton.css("pointer-events", "none")

		# Don't go to homepage
		@fixbutton.one "click", (e) =>
			@stopDrag()
			@fixbutton.removeClass("dragging")
			if Math.abs(@fixbutton.offset().left - @fixbutton_initx) > 5
				# If moved more than some pixel the button then don't go to homepage
				e.preventDefault()

		# Animate drag
		@fixbutton.parents().on "mousemove", @animDrag
		@fixbutton.parents().on "mousemove" ,@waitMove

		# Stop dragging listener
		@fixbutton.parents().on "mouseup", (e) =>
			e.preventDefault()
			@stopDrag()


	# Wait for moving the fixbutton
	waitMove: (e) =>
		if Math.abs(@fixbutton.offset().left - @fixbutton_targetx) > 10 and (+ new Date)-@dragStarted > 100
			@moved()
			@fixbutton.parents().off "mousemove" ,@waitMove

	moved: ->
		@log "Moved"
		@createHtmltag()
		$(document.body).css("perspective", "1000px").addClass("body-sidebar")
		$(window).off "resize"
		$(window).on "resize", =>
			$(document.body).css "height", $(window).height()
			@scrollable()
		$(window).trigger "resize"

		# Override setsiteinfo to catch changes
		wrapper.setSiteInfo = (site_info) =>
			@setSiteInfo(site_info)
			@original_set_site_info.apply(wrapper, arguments)

	setSiteInfo: (site_info) ->
		@updateHtmlTag()
		@displayGlobe()


	# Create the sidebar html tag
	createHtmltag: ->
		if not @container
			@container = $("""
			<div class="sidebar-container"><div class="sidebar scrollable"><div class="content-wrapper"><div class="content">
			</div></div></div></div>
			""")
			@container.appendTo(document.body)
			@tag = @container.find(".sidebar")
			@updateHtmlTag()
			@scrollable = window.initScrollable()


	updateHtmlTag: ->
		wrapper.ws.cmd "sidebarGetHtmlTag", {}, (res) =>
			if @tag.find(".content").children().length == 0 # First update
				@log "Creating content"
				morphdom(@tag.find(".content")[0], '<div class="content">'+res+'</div>')
				@scrollable()

			else  # Not first update, patch the html to keep unchanged dom elements
				@log "Patching content"
				morphdom @tag.find(".content")[0], '<div class="content">'+res+'</div>', {
					onBeforeMorphEl: (from_el, to_el) ->  # Ignore globe loaded state
						if from_el.className == "globe"
							return false
						else
							return true
				}


	animDrag: (e) =>
		mousex = e.pageX

		overdrag = @fixbutton_initx-@width-mousex
		if overdrag > 0  # Overdragged
			overdrag_percent = 1+overdrag/300
			mousex = (e.pageX + (@fixbutton_initx-@width)*overdrag_percent)/(1+overdrag_percent)
		targetx = @fixbutton_initx-mousex-@fixbutton_addx

		@fixbutton.offset
			left: mousex+@fixbutton_addx

		if @tag
			@tag.css("transform", "translateX(#{0-targetx}px)")

		# Check if opened
		if (not @opened and targetx > @width/3) or (@opened and targetx > @width*0.9)
			@fixbutton_targetx = @fixbutton_initx - @width  # Make it opened
		else
			@fixbutton_targetx = @fixbutton_initx


	# Stop dragging the fixbutton
	stopDrag: ->
		@fixbutton.parents().off "mousemove"
		@fixbutton.off "mousemove"
		@fixbutton.css("pointer-events", "")
		$(".drag-bg").remove()
		if not @fixbutton.hasClass("dragging")
			return
		@fixbutton.removeClass("dragging")

		# Move back to initial position
		if @fixbutton_targetx != @fixbutton.offset().left
			# Animate fixbutton
			@fixbutton.stop().animate {"left": @fixbutton_targetx}, 500, "easeOutBack", =>
				# Switch back to auto align
				if @fixbutton_targetx == @fixbutton_initx  # Closed
					@fixbutton.css("left", "auto")
				else  # Opened
					@fixbutton.css("left", @fixbutton_targetx)

				$(".fixbutton-bg").trigger "mouseout"  # Switch fixbutton back to normal status

			# Animate sidebar and iframe
			if @fixbutton_targetx == @fixbutton_initx
				# Closed
				targetx = 0
				@opened = false
			else
				# Opened
				targetx = @width
				if not @opened
					@onOpened()
				@opened = true

			# Revent sidebar transitions
			@tag.css("transition", "0.4s ease-out")
			@tag.css("transform", "translateX(-#{targetx}px)").one transitionEnd, =>
				@tag.css("transition", "")
				if not @opened
					@container.remove()
					@container = null
					@tag.remove()
					@tag = null

			# Revert body transformations
			@log "stopdrag", "opened:", @opened
			if not @opened
				@onClosed()


	onOpened: ->
		@log "Opened"
		@scrollable()

		# Re-calculate height when site admin opened or closed
		@tag.find("#checkbox-owned").off("click").on "click", =>
			setTimeout (=>
				@scrollable()
			), 300

		# Site limit button
		@tag.find("#button-sitelimit").on "click", =>
			wrapper.ws.cmd "siteSetLimit", $("#input-sitelimit").val(), =>
				wrapper.notifications.add "done-sitelimit", "done", "Site storage limit modified!", 5000
				@updateHtmlTag()
			return false

		# Change identity button
		@tag.find("#button-identity").on "click", =>
			wrapper.ws.cmd "certSelect"
			return false

		# Owned checkbox
		@tag.find("#checkbox-owned").on "click", =>
			wrapper.ws.cmd "siteSetOwned", [@tag.find("#checkbox-owned").is(":checked")]

		# Save settings
		@tag.find("#button-settings").on "click", =>
			wrapper.ws.cmd "fileGet", "content.json", (res) =>
				data = JSON.parse(res)
				data["title"] = $("#settings-title").val()
				data["description"] = $("#settings-description").val()
				json_raw = unescape(encodeURIComponent(JSON.stringify(data, undefined, '\t')))
				wrapper.ws.cmd "fileWrite", ["content.json", btoa(json_raw)], (res) =>
					if res != "ok" # fileWrite failed
						wrapper.notifications.add "file-write", "error", "File write error: #{res}"
					else
						wrapper.notifications.add "file-write", "done", "Site settings saved!", 5000
						@updateHtmlTag()
			return false

		# Sign content.json
		@tag.find("#button-sign").on "click", =>
			inner_path = @tag.find("#select-contents").val()

			if wrapper.site_info.privatekey
				# Privatekey stored in users.json
				wrapper.ws.cmd "siteSign", ["stored", inner_path], (res) =>
					wrapper.notifications.add "sign", "done", "#{inner_path} Signed!", 5000

			else
				# Ask the user for privatekey
				wrapper.displayPrompt "Enter your private key:", "password", "Sign", (privatekey) => # Prompt the private key
					wrapper.ws.cmd "siteSign", [privatekey, inner_path], (res) =>
						if res == "ok"
							wrapper.notifications.add "sign", "done", "#{inner_path} Signed!", 5000

			return false

		# Publish content.json
		@tag.find("#button-publish").on "click", =>
			inner_path = @tag.find("#select-contents").val()
			@tag.find("#button-publish").addClass "loading"
			wrapper.ws.cmd "sitePublish", {"inner_path": inner_path, "sign": false}, =>
				@tag.find("#button-publish").removeClass "loading"

		@loadGlobe()


	onClosed: ->
		$(window).off "resize"
		$(document.body).css("transition", "0.6s ease-in-out").removeClass("body-sidebar").on transitionEnd, (e) =>
			if e.target == document.body
				$(document.body).css("height", "auto").css("perspective", "").css("transition", "").off transitionEnd
				@unloadGlobe()

		# We dont need site info anymore
		wrapper.setSiteInfo = @original_set_site_info


	loadGlobe: =>
		if @tag.find(".globe").hasClass("loading")
			setTimeout (=>
				if typeof(DAT) == "undefined"  # Globe script not loaded, do it first
					$.getScript("/uimedia/globe/all.js", @displayGlobe)
				else
					@displayGlobe()
			), 600


	displayGlobe: =>
		wrapper.ws.cmd "sidebarGetPeers", [], (globe_data) =>
			if @globe
				@globe.scene.remove(@globe.points)
				@globe.addData( globe_data, {format: 'magnitude', name: "hello", animated: false} )
				@globe.createPoints()
			else
				@globe = new DAT.Globe( @tag.find(".globe")[0], {"imgDir": "/uimedia/globe/"} )
				@globe.addData( globe_data, {format: 'magnitude', name: "hello"} )
				@globe.createPoints()
				@globe.animate()
			@tag.find(".globe").removeClass("loading")


	unloadGlobe: =>
		if not @globe
			return false
		@globe.unload()
		@globe = null


window.sidebar = new Sidebar()
window.transitionEnd = 'transitionend webkitTransitionEnd oTransitionEnd otransitionend'
