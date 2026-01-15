define [
  'underscore'
  'backbone'
  'mixpanel'
  'google/jsapi'
  'lib/form'
  'lib/validation_helper'
  'models/clear'
  'qtip'
  'numeral'
  'backbone.stickit'
  'jspdf'
  'clipboard'
], (_, Backbone, mixpanel, Google, form, ValidationHelper, Clear,
    qtip, Numeral, stickit, jsPDF, Clipboard) ->
  # While most model logic should live server side in most of AL,
  # CLEAR is a standalone page. There is no server-side backing except
  # for generating a PDF of the docs to sign. So you will see some code
  # practices here that might seem like they should live server-side.
  # TODO: abstract over ISOs, NQOs, RSUs.

  # WHAT YOU NEED TO KNOW:
  # 1) THE NYTIMES' LIBRARY, STICKIT.
  #    stickit binds Backbone models with views. It ties model value -> input changes,
  #    model value -> static text changes. CLEAR uses this heavily. check the 'bindings' hash
  #    for all the bindings, hooks, etc. A simple example is 'salary', a really complex one is
  #    rendering the "how much can your equity be worth?" section, which re-renders a lot of stuff
  #    when *any* of the source model values change.
  #
  # 2) THIS LIBRARY WORKS ON /clear/offer, /clear/amendment, AND /clear/how_much.
  #    If specific inputs don't exist on /clear/amendment, e.g. the salary, all the code here
  #    will still work. All of the code is encapsulated down to the level of the legal term, and
  #    what other legal terms are coupled with it. E.g. check out number_of_options and
  #    outstanding_shares: If those jquery selectors are found on the page, stickit will wire
  #    them up and all onGet and onSet hooks will fire. If number_of_options and outstanding_shares
  #    are not present, that code will silently be ignored.
  #
  # 3) PDF GENERATION IS VERY BRITTLE.
  #    I only found the jsPDF library to reliably generate PDFs from HTML if you only used
  #    a subset of HTML that's essentially markdown. You can see all the view partials in
  #    /app/views/clear/pdf/
  #
  # 4) PDF GENERATION *ALSO* USES THE NYTIMES' STICKIT
  #    The legal language in the PDF offers changes based on legal terms, e.g. if you can Early
  #    Exercise. The same onSet stickit rendering of the main page on /clear/offer and
  #    /clear/amendment is in use to pick between different versions of legal language as per
  #    the legal docs.
  #
  # 5) DO NOT CHANGE LEGAL DOC LANUGAGE WITHOUT CHECKING WITH THE LEGAL DOCS.
  #    Any copy in /app/views/clear/pdf/ is LEGAL language. That is not marketing copy
  #    we can edit at will. If you want to wordsmith, wordsmith all the human-facing, explanatory
  #    legal terms in /app/views/clear/terms/


  class ClearView extends Backbone.View
    # instead of having a sub-model and sub-view for each term, it's all in this monolith.
    # Unfortunately some legal terms are coupled, e.g. if you want to explain number of shares,
    # you also need the shares outstanding, strike price, etc.
    PDFS_ENABLED: false
    GOOGLE_VIZ_VERSION: 1.1
    GOOGLE_CHART_OPTIONS_STYLE: {
      legend: { position: 'none' }
      colors: ['#888888']
      chartArea: {
        width: '85%'
        top: 5
      }
      vAxis: {
        gridlines: { color: '#eee' }
        titleTextStyle: { color: '#757575' }
        textStyle: {
          color: '#757575'
          fontSize: 9
        }
        baselineColor: '#e6e6e6'
        textPosition: 'in'
      }
      hAxis: {
        baselineColor: '#e6e6e6'
        titleTextStyle: { color: '#757575' }
        textStyle: {
          color: '#757575'
          fontSize: 9
        }
      }
      annotations: { highContrast: true}
      backgroundColor: { fill: 'transparent' }
    }

    initialize: (options) ->
      this.model = new Clear(_.extend(this.decodeFromURL(), options.modelAttributes))
      this.updateURL()
      this.model.bind('change', this.onModelChange)
      this.model.bind('validated', this.onValidation)
      Backbone.Validation.bind(this, {
        # Backbone.Validation library limitation workaround:
        # default selector to propagate the model validation
        # is name, e.g. @$('[name=foo]'), but that clashes w/
        # our <a>nchors to specific terms, and BackboneValidation
        # needs to match on the exact model attribute, but rails
        # forms are namespaced to 'object_attribute' or '[object]attribute'
        selector: 'data-model-attribute'
      })

      # order of pre-render, stickit, and renderTerms
      # is important. preRender fills in some <selects>
      # that stickit relies on for model binding,
      # and the proper rendering of the terms relies on
      # the model binding
      this.preRender()
      this.stickit()
      this.renderTerms({changed: this.model.attributes})
      validationResult = this.model.validate(this.model.onlySetAttributes())
      this.renderValidation(this.model.onlySetAttributes(), validationResult)
      this.warnAgainstMistakes()
      mixpanel?.track("/CLEAR load", _.extend({numSetAttributes: this.model.numSetAttributes()}, this.model.onlySetAttributes(private: true)))

    events:
      'submit .js-clearForm': () ->  false

    onModelChange: (change) =>
      this.renderTerms(change)
      this.updateURL()
      this.warnAgainstMistakes()

    # this hash ties a selector to a this.model attribute.
    # And sets up one-way bindings for non-input elements,
    # two-way bindings for input elements.
    bindings: {
      '.js-salary': { observe: 'salary' }
      '.js-salaryText': {
        observe: 'salary',
        onGet: () -> this.formatLargeCurrency(this.model.get('salary') * 1000) # input is [   ],000
      }
      '.js-salaryChartObserver': {
        observe: ['salary', 'role', 'location']
        onGet: 'salaryChart'
      },
      '.js-salaryRole': 'role'
      '.js-salaryLocation': 'location'
      '.js-health': { observe: 'health', onSet: '_booleanize' }
      '.js-dental': { observe: 'dental', onSet: '_booleanize' }
      '.js-vision': { observe: 'vision', onSet: '_booleanize' }
      '.js-retirement': 'retirement'
      '.js-vacationDays': 'vacation_days'
      '.js-numberOfOptions': 'number_of_options'
      '.js-numberOfOptionsHowMuch': 'number_of_options'
      '.js-numberOfOptionsText': {
        observe: 'number_of_options'
        onGet: 'formatLarge'
      },
      '.js-numberOfOptionsObserver': {
        # careful editing the options-equity-shares links.
        # It's a graph that must be kept acyclic
        observe: ['number_of_options', 'outstanding_shares']
        update: (el, newVals, model, options) ->
          [numOptions, numOutstanding] = newVals.map((val) -> parseFloat(val, 10))
          if !isNaN(numOptions) and !isNaN(numOutstanding)
            # the parse/toFixed is to get around some JS float bugs, where
            # e.g. 100 * (7/10000) = 0.06999999999...
            newEquity = parseFloat((100 * (numOptions/numOutstanding)).toFixed(7), 10)
            oldEquity = parseFloat(this.model.get('equity_percent'), 10)
            if oldEquity isnt newEquity
              this.model.set('equity_percent', newEquity)#, {silent: true})
      }
      '.js-outstandingShares': 'outstanding_shares'
      '.js-outstandingSharesText': {
        observe: 'outstanding_shares'
        onGet: () -> this.formatLarge(this.model.get('outstanding_shares'))
      }
      '.js-equityPercent': 'equity_percent'
      '.js-equityPercentHowMuch': 'equity_percent'
      '.js-equityPercentText': {
        observe: 'equity_percent'
        onGet: () -> this.formatPercent(this.model.get('equity_percent'))
      }
      '.js-equityPercentObserver': {
        observe: ['equity_percent', 'outstanding_shares']
        # careful editing the options-equity-shares links.
        # It's a graph that must be kept acyclic
        update: (el, newVals, model, options) ->
          [equity, numOutstanding] = newVals.map((val) -> parseFloat(val, 10))
          if !isNaN(equity) and !isNaN(numOutstanding)
            newNumOptions = Math.round(numOutstanding * (equity/100))
            oldNumOptions = parseInt(this.model.get('number_of_options'), 10)
            if newNumOptions isnt oldNumOptions
              this.model.set('number_of_options', newNumOptions)#, {silent: true})
      }
      '.js-latestValuationPerShare': 'latest_valuation_per_share'
      '.js-latestValuationPerShareText': {
        observe: 'latest_valuation_per_share'
        onGet: (latestValuationPerShare) ->
          latestValuationPerShare = parseFloat(latestValuationPerShare, 10)
          if !isNaN(latestValuationPerShare)
            this.formatSmallCurrency(latestValuationPerShare)
          else
            "this much"
      }
      '.js-companyValuationText': {
        observe: ['latest_valuation_per_share', 'outstanding_shares']
        onGet: () -> this.formatLargeCurrency(this.model.companyValuation())
      }
      '.js-equityChartObserver': {
        observe: ['number_of_options', 'outstanding_shares', 'role', 'location', 'equity_percent']
        onGet: 'equityChart'
      }
      '.js-vestingYears': 'vesting_years'
      '.js-vestingYearsText': {
        observe: 'vesting_years'
        onGet: 'pluralizeYears'
      }
      '.js-vestingCliffYears': 'vesting_cliff_years'
      '.js-vestingCliffYearsText': {
        observe: 'vesting_cliff_years'
        onGet: 'pluralizeYears'
      }
      '.js-vestingChartObserver': {
        observe: ['number_of_options', 'vesting_years', 'vesting_cliff_years', 'loading']
        onGet: 'vestingChart'
      }
      '.js-loading': 'loading'
      '.js-loadingText': {
        observe: 'loading'
        onGet: (loading) ->
          if loading is "none" or !loading
            "evenly-space"
          else if loading is "front-loaded"
            "front-load"
          else if loading is "back-loaded"
            "back-load"
      }
      '.js-loadingChartObserver': {
        observe: ['loading', 'vesting_cliff_years', 'vesting_cliff']
        onGet: 'loadingChart'
      }
      '.js-earlyExercise': 'early_exercise'
      '.js-earlyExerciseText': 'early_exercise'
      '.js-preferenceFloor': 'preference_floor'
      '.js-preferenceFloorHowMuch': 'preference_floor'
      '.js-preferenceFloorText': {
        observe: 'preference_floor'
        onGet: 'formatLargeCurrency'
      }
      '.js-preferenceFloorIncreaseOptionsInMoney': {
        observe: [
          'preference_floor', 'strike_price', 'outstanding_shares', 'liquidation_preference'
          'latest_valuation', 'number_of_options', 'series', 'equity'
        ]
        onGet: () ->
          this.formatLargeCurrency(this.model.commonOptionsInMoneyFloor())
      }
      '.js-preferenceFloorIncreaseOptionsInMoneyPercent': {
        observe: ['preference_floor', 'strike_price', 'outstanding_shares', 'latest_valuation_per_share']
        onGet: () ->
          preferenceFloor = parseFloat(preferenceFloor, 10)
          latestValuation = parseFloat(this.model.latestValuation(), 10)
          optionsInMoneyPercentIncrease = this.model.commonOptionsInMoneyFloor(preferenceFloor) / latestValuation
          this.formatPercent(optionsInMoneyPercentIncrease)
      }
      '.js-optionsInMoneyChartObserver': {
        'observe': ['preference_floor', 'strike_price', 'outstanding_shares']
        onGet: 'optionsInMoneyChart'
      }
      '.js-strikePrice': 'strike_price'
      '.js-strikePriceHowMuch': 'strike_price'
      '.js-strikePriceText': {
        observe: 'strike_price'
        onGet: (strikePrice) -> if strikePrice? then this.formatSmallCurrency(strikePrice) else "this much"
      }
      '.js-costToExerciseText': {
        observe: ['strike_price', 'number_of_options']
        onGet: (args) ->
          this.formatLargeCurrency(this.model.costToExercise())
      }
      '.js-exerciseWindowDays': 'exercise_window_days'
      '.js-exerciseWindowYears': 'exercise_window_years'
      '.js-exerciseWindowText': {
        observe: ['exercise_window_years', 'exercise_window_days']
        onGet: (yearsAndDays) ->
          years = yearsAndDays[0]
          days = yearsAndDays[1]
          text = ""
          if years
            text += years + " years"
          if years and days
            text += ', '
          if days
            text += days + ' days'
          return if text.length > 0 then text else "this long"
      }
      '.js-netExercise': 'net_exercise'
      '.js-netExerciseText': {
        observe: 'net_exercise'
        onGet: () -> if this.model.get('net_exercise') then 'yes' else 'no'
      }
      # For "what you get when we exit for 1M, 10M, 100M, ..." section
      # we have to observe and update based on some model values.
      # But we have to update multiple rows. So we use stickit's great
      # observation feature, and "update" a hidden text field, and in
      # this hook we update the actual display rows of the table.
      # At heart, stickit only handles one/many model updates -> one output
      # but this case is (many model attrs) -> (many rendered divs)
      '.js-comparableExitObserver': {
        observe: ['preference_floor', 'number_of_options', 'strike_price', 'outstanding_shares',
                  'latest_valuation', 'latest_series', 'liquidation_preference', 'equity_percent']
        onGet: (changedVals) ->
          _.each(@$('.js-comparableExit'), (comparableExitRow) =>
            exitRow = $(comparableExitRow)
            approxVal = parseInt(exitRow.data('approx-val'), 10)
            if !isNaN(approxVal)
              optionsInMoney = this.model.commonOptionsInMoneyFloor()
              if !isNaN(optionsInMoney)
                if optionsInMoney >= approxVal then exitRow.hide() else exitRow.show()

              exitRow.find('.js-approxVal').text(Numeral(approxVal).format('$0,0a'))
              valueOfOptions = this.model.valueOfOptions(approxVal)
              if !isNaN(valueOfOptions)
                valueExplanation = ""
                # the 0.00...1 because float math sucks like that
                closestOrderOfMagnitude = Math.pow(10,
                  Math.round(Math.log(valueOfOptions) / Math.LN10 + 0.000000001)
                )
                whatYouCanBuy = (Clear.CAN_BUY[closestOrderOfMagnitude] || Clear.CAN_BUY[100000000])
                if whatYouCanBuy.text not in ['financial freedom', 'nothing']
                  count = Math.floor(valueOfOptions/closestOrderOfMagnitude) || 1
                  if count > 1
                    valueExplanation += '' + count + ' ' + whatYouCanBuy.text + 's'
                  else
                    valueExplanation += "a" + " " + whatYouCanBuy.text
                  valueExplanation += ' ' + Array(count+1).join(" " + whatYouCanBuy.emoji)
                else
                  valueExplanation = whatYouCanBuy.text + whatYouCanBuy.emoji

                exitRow.find('.js-withOptionsWorth').text(this.formatLargeCurrency(valueOfOptions))
                exitRow.find('.js-canBuy').text(valueExplanation)

            # latestValuation() is the source of truth, backup is shortcut for guessing how much it'll be worth
            latestValuation = this.model.latestValuation(useEnteredValuation: true)
          )
      }
      '.js-latestValuationHowMuch': 'latest_valuation'
      '.js-latestValuation': 'latest_valuation'
      '.js-latestSeries': 'latest_series'
      '.js-latestSeriesHowMuch': 'latest_series'
      '.js-liquidationPreference': 'liquidation_preference'
      '.js-liquidationPreferenceHowMuch': 'liquidation_preference'
      '.js-preset': 'preset',
      '.js-presetObserver': {
        observe: 'preset'
        onGet: (preset) -> this.selectPreset this.model.get('preset')
      }
      '.js-companyRepresentation': { observe: 'company_representation', onSet: '_booleanize' }
      '.js-acceptToS': { observe: 'accepted_tos', onSet: '_booleanize' }
    }


    _booleanize: (val) -> val in ['true', 'yes', '1'] # javascript .val() of inputs


    pluralizeYears: (years) ->
      years + (if years > 1 then " years" else " year")


    renderValidation: (toValidateAttrs, invalidAttrs) ->
      # Backbone.Validation sets an `invalid` class on the input
      # which is hardcoded. This smelly code formats the effects
      # into what AL standard sass expects: a .fieldWithErrors <input>,
      # and a %span.validation-error
      _.each(toValidateAttrs, (value, attrName) ->
        input = @$('.js-termInput[data-model-attribute="' + attrName + '"]')
        invalidMsg = (invalidAttrs || {})[attrName]
        if invalidMsg?
          form.setInputError(input, invalidMsg)
        else
          form.clearInputError(input)
      )

    setSelectOptions: (select, options) ->
      # generating HTML in JS does smell bad, but we don't use backbone templates
      # since we use HAML. Rather than keep the canonical list of series
      # both in ruby when generating HAML and in coffeescript (in the Clear backbone model),
      # we only put them in coffeescript and generate the HTML here.
      optionsAsString = "";
      _.each(options, (option) ->
        optionsAsString += "<option value='" + option + "'>" + option + "</option>"
      )
      select.append(optionsAsString)


    # there are a few coupled terms in an offer letter, e.g.
    # when you change the number of options, the equity ownership
    # changes (it's a literal mathematical function of your shares and
    # total shares). This updates the display of any coupled terms
    # as well as any updates local to a term (e.g. change the retirement
    # and the description text changes too)
    renderTerms: (change) ->
      _.each(change.changed, (newVal, term) =>
        if typeof this.onRenderTerm[term] is 'function'
          this.onRenderTerm[term].apply(this, [newVal])
      )


    # at first glance the onRenderTerm may seem to duplicate
    # the 'bindings' hash. But they are different. the bindings
    # hash renders specific text based on specific model changes,
    # onRenderTerm hooks change layout/display of entire sections, e.g.
    # show/hide different explanations for single vs double-trigger
    onRenderTerm: {
      retirement: () ->
        retirement = this.model.get('retirement')
        @$('.js-retire').addClass('u-hidden')
        @$('.js-retire.' + (if retirement == 'yes' then 'yes' else 'no')).removeClass('u-hidden')
      number_of_options: () ->
        this.renderEquity()
      outstanding_shares: () ->
        this.renderEquity()
        this.renderPreferenceFloor()
      latest_valuation_per_share: () -> this.renderPreferenceFloor()
      vesting_years: () -> this.renderVesting()
      vesting_cliff_years: () -> this.renderVesting()

      loading: () ->
        loading = this.model.get('loading')
        @$('.js-loadingExplanation').addClass('u-hidden')
        if loading is "none" or !loading
          @$('.js-loadingExplanation.js-noLoading').removeClass('u-hidden')
          @$('.js-loadingChart').addClass('u-hidden')
        else if loading is "front-loaded"
          @$('.js-loadingExplanation.js-frontLoading').removeClass('u-hidden')
          @$('.js-loadingChart').addClass('u-hidden')
        else if loading is "back-loaded"
          @$('.js-loadingChart').removeClass('u-hidden')
          @$('.js-loadingExplanation.js-backLoading').removeClass('u-hidden')

      acceleration: () ->
        acceleration = this.model.get('acceleration')
        @$('.js-accelerationExplanation').addClass('u-hidden')
        if !acceleration or acceleration is "none"
          @$(".js-accelerationYears").addClass('disabled')
          @$(".js-accelerationYears").attr('disabled', true)
        else
          @$(".js-accelerationYears").removeClass('disabled')
          @$(".js-accelerationYears").attr('disabled', false)
          if acceleration is "single-trigger"
            @$('.js-accelerationExplanation.js-singleTrigger').removeClass('u-hidden')
          else if acceleration is "double-trigger"
            @$('.js-accelerationExplanation.js-doubleTrigger').removeClass('u-hidden')

      preference_floor: () ->
        this.renderPreferenceFloor()
        this.renderHowMuchIsItWorthBallPark()

      strike_price: () ->
        this.renderPreferenceFloor()
        this.renderStrikePrice()

      net_exercise: () ->
        @$('.js-netExerciseExplanation').addClass('u-hidden')
        if (this.model.get('net_exercise') is 'yes')
          @$('.js-netExerciseExplanation.js-yes').removeClass('u-hidden')
        else
          @$('.js-netExerciseExplanation.js-no').removeClass('u-hidden')

      early_exercise: () ->
        @$('.js-earlyExerciseExplanation').addClass('u-hidden')
        if (this.model.get('early_exercise') is 'yes')
          @$('.js-earlyExerciseExplanation.js-yes').removeClass('u-hidden')
        else
          @$('.js-earlyExerciseExplanation.js-no').removeClass('u-hidden')

      preset: () ->
        @$('.js-presetText').addClass('u-hidden')
        @$('.js-presetText.js-' + this.model.get('preset')).removeClass('u-hidden')

      accepted_tos: () -> this.renderActionButtons()
      company_representation: () -> this.renderActionButtons()
    }


    renderActionButtons: () ->
      actionButtons = @$('.js-actionButton')
      if this.model.get('accepted_tos') and this.model.get('company_representation')
        actionButtons.removeClass('disabled')
      else
        actionButtons.addClass('disabled')


    preRender: () ->
      mixpanel?.track_links('.js-salaryChartLinks a', '/CLEAR salary chart links')
      @$('.js-qtip').qtip()
      this.setSelectOptions(@$('.js-loading'), Clear.LOADING)
      this.setSelectOptions(@$('.js-acceleration'), Clear.ACCELERATION)
      this.setSelectOptions(@$('.js-latestSeries'), Clear.SERIES)
      this.setSelectOptions(@$('.js-latestSeriesHowMuch'), Clear.SERIES)
      this.comparables = {
        compensations: @$('.js-compensations').data('compensations')
        valuations: @$('.js-valuations').data('valuations')
      }
      @$('.js-clearTerm :input').change((event) =>
        # naive: render validation on all set attributes
        setAttrs = this.model.onlySetAttributes()
        result = this.model.validate(setAttrs)
        this.renderValidation(setAttrs, result)
      )
      if this.comparables.compensations isnt null
        for compType in ['salary', 'equity']
          select = @$('.js-' + compType + 'Role')
          if select.length > 0
            this.setSelectOptions(select,
               ["compared to this role..."].concat(
                 _.map(
                   this.comparables.compensations.tags.roles,
                   (roleStats, roleName) -> roleName)))
          select = @$('.js-' + compType + 'Location')
          if select.length > 0
            this.setSelectOptions(select,
               ["in this location..."].concat(
                 _.map(
                   this.comparables.compensations.tags.locations,
                   (locationStats, locationName) -> locationName)))
      @$('.js-clear1').click (e) => this.selectPreset 'clear1', e.target
      @$('.js-clear2').click (e) => this.selectPreset 'clear2', e.target
      this.selectPreset(this.model.get('preset'))
      @$('.js-actionBar .c-button').qtip()
      shareURL = @$('.js-shareURL')
      shareURL.on('click', () -> $(this).select() )
      shareURL.qtip()
      clipboard = new Clipboard '.js-copyShareURLButton', target: () => @$('.js-shareURL')[0]
      clipboard.on 'success', (e) =>
        @$('.js-copyShareURLButton').qtip(content: 'copied', show: true)
        mixpanel?.track("/CLEAR send button",
          _.extend({numSetAttributes: this.model.numSetAttributes()},
                   this.model.onlySetAttributes(private: true)))

      @$('.js-downloadButton').attr('title', 'coming soon').qtip() if not @PDFS_ENABLED
      @$('.js-downloadButton').click () => this.generatePDF()
      # terms of service should be agreed to by each load
      # e.g. founder fills out form, checks agree, sends to candidate, candidate loads,
      # candidate has to agree as well
      this.model.set('accepted_tos', false)

    renderEquity: () ->
      currentEmployeeShares = parseInt(this.model.get('number_of_options'), 10)
      currentTotalShares = parseInt(this.model.get('outstanding_shares'), 10)
      investorEquity = 0.2
      newShares = Math.ceil((investorEquity * currentTotalShares) / (1.0 - investorEquity))
      newTotalShares = newShares + currentTotalShares
      equityPreDilution = (currentEmployeeShares / currentTotalShares)
      equityPostDilution = (currentEmployeeShares / newTotalShares)
      @$('.js-newInvestorShares').text(this.formatLarge(newShares))
      @$('.js-newSharesOutstanding').text(this.formatLarge(newTotalShares))
      @$('.js-equityPercentPostDilution').text(this.formatPercent(equityPostDilution))
      @$('.js-equityPercentText').text(this.formatPercent(equityPreDilution))

      @$('.js-dilutionExplanation').addClass('u-hidden')
      if !isNaN(newShares) and !isNaN(newTotalShares) and !isNaN(equityPostDilution)
        @$('.js-dilutionExplanation.js-withNumbers').removeClass('u-hidden')
      else
        @$('.js-dilutionExplanation.js-noNumbers').removeClass('u-hidden')

    renderVesting: (years, cliffYears) ->
      years = parseFloat(this.model.get('vesting_years'), 10)
      cliffYears = parseFloat(this.model.get('vesting_cliff_years'), 10)
      @$('.js-vestingExplanation').addClass('u-hidden')
      if !isNaN(years) and !isNaN(cliffYears)
        @$('.js-vestingExplanation.js-withNumbers').removeClass('u-hidden')
      else
        @$('.js-vestingExplanation.js-noNumbers').removeClass('u-hidden')
      if cliffYears <= 0 or isNaN(cliffYears)
        @$('.js-yesVestingCliff').addClass('u-hidden')
        @$('.js-noVestingCliff').removeClass('u-hidden')
      else
        @$('.js-yesVestingCliff').removeClass('u-hidden')
        @$('.js-noVestingCliff').addClass('u-hidden')


    renderPreferenceFloor: () ->
      preferenceFloor = parseFloat(this.model.get('preference_floor'), 10)
      strikePrice = parseFloat(this.model.get('strike_price'), 10)
      outstandingShares = parseFloat(this.model.get('outstanding_shares'), 10)
      latestValuation = this.model.latestValuation()
      @$('.js-preferenceFloorExplanation').addClass('u-hidden')
      if !isNaN(preferenceFloor) and !isNaN(latestValuation) and !isNaN(outstandingShares)
        @$('.js-preferenceFloorExplanation.js-aboveLatestValuation').removeClass('u-hidden')
        if !isNaN(strikePrice)
          @$('.js-preferenceFloorExplanation.js-aboveExerciseCost').removeClass('u-hidden')
      else
        @$('.js-preferenceFloorExplanation.js-noNumbers').removeClass('u-hidden')

    renderHowMuchIsItWorthBallPark: () ->
      preferenceFloor = parseInt(this.model.get('preference_floor'))
      if !isNaN(preferenceFloor)
        for section in [@$('.js-ballparkPreferenceFloor'), @$('.js-ballparkPreferenceFloorFullTerms')]
          section.find('input').prop('disabled', true)
          section.attr('title', 'No need to estimate the preference floor if we know it.')
          section.css('opacity', 0.3)
          section.qtip()
      else
        for section in [@$('.js-ballparkPreferenceFloor'), @$('.js-ballparkPreferenceFloorFullTerms')]
          section.find('input').prop('disabled', false)
          section.attr('title', '')
          section.css('opacity', 1)
          section.qtip('disable', true)

    renderStrikePrice: () ->
      strikePrice = parseFloat(this.model.get('strike_price'), 10)
      numOptions = parseInt(this.model.get('number_of_options'), 10)
      if !isNaN(strikePrice) and !isNaN(numOptions)
        @$('.js-strikePriceExplanation.js-numbers').removeClass('u-hidden')
      else
        @$('.js-strikePriceExplanation.js-numbers').addClass('u-hidden')

    equityChart: () ->
      return unless this.comparables.compensations
      roleSet = this.comparables.compensations.tags.roles[this.model.get('role')]
      locationSet = this.comparables.compensations.tags.locations[this.model.get('location')]
      return unless roleSet or locationSet
      data = this.filterCompensationData {
        compensationType: "equity",
        target: this.model.equityPercent()
      }
      Google.load 'visualization', @GOOGLE_VIZ_VERSION,
        packages: ['corechart'],
        callback: =>
          data = Google.visualization.arrayToDataTable data
          chart = new Google.visualization.ColumnChart @$('.js-equityChart')[0]
          chart.draw(data,
            _.extend(@GOOGLE_CHART_OPTIONS_STYLE, {vAxis: {title: '# of jobs'}}))
          this.equityChartFirstLoad = true if typeof(this.equityChartFirstLoad) is 'undefined'
          if this.equityChartFirstLoad and data.getNumberOfRows() > 0
            this.equityChartFirstLoad = false
            mixpanel?.track(
              "/CLEAR load equity chart ",
              this.model.onlySetAttributes(private: true))

    salaryChart: () ->
      return unless this.comparables.compensations
      roleSet = this.comparables.compensations.tags.roles[this.model.get('role')]
      locationSet = this.comparables.compensations.tags.locations[this.model.get('location')]
      return unless roleSet or locationSet
      data = this.filterCompensationData {
        compensationType: "salary",
        target: parseInt(this.model.get('salary'))
      }
      Google.load 'visualization', @GOOGLE_VIZ_VERSION,
        packages: ['corechart'],
        callback: =>
          data = Google.visualization.arrayToDataTable data
          chart = new Google.visualization.ColumnChart @$('.js-salaryChart')[0]
          chart.draw(data,
            _.extend(@GOOGLE_CHART_OPTIONS_STYLE, {vAxis: {title: '# of jobs'}}))
          this.salaryChartFirstLoad = true if typeof(this.salaryChartFirstLoad) is 'undefined'
          if data.getNumberOfRows() > 0 and this.salaryChartFirstLoad
            this.salaryChartFirstLoad = false
            mixpanel?.track("/CLEAR load salary chart ", this.model.onlySetAttributes(private: true))

    vestingChart: () ->
      vestingYears = parseFloat(this.model.get('vesting_years'), 10)
      numOptions = parseInt(this.model.get('number_of_options'), 10)
      return if isNaN(vestingYears) or isNaN(numOptions)
      vestingCliffYears = parseFloat(this.model.get('vesting_cliff_years'), 10) || 0
      loading = this.model.get('loading')
      data = this.vestingChartSeries(numOptions, vestingYears, vestingCliffYears, loading)
      # need a deep copy of the default options, otherwise
      # javascript nested-copy-by-reference will change the options
      # for ALL charts.
      options = JSON.parse(JSON.stringify(@GOOGLE_CHART_OPTIONS_STYLE))
      options.hAxis.title = 'years'
      options.hAxis.ticks = (i for i in [0..vestingYears])
      options.hAxis.viewWindow = { max: vestingYears,  min: 0 }
      options.vAxis.title = 'vested options'
      options.vAxis.viewWindow = { max: numOptions, min: 0 }
      options.vAxis.format = 'short'
      Google.load 'visualization', @GOOGLE_VIZ_VERSION,
        packages: ['corechart'],
        callback: =>
          data = Google.visualization.arrayToDataTable data
          chart = new Google.visualization.LineChart @$('.js-vestingChart')[0]
          chart.draw(data, options)
          this.vestingChartFirstLoad = true if typeof(this.vestingChartFirstLoad) is 'undefined'
          if data.getNumberOfRows() > 0 and this.vestingChartFirstLoad
            this.vestingChartFirstLoad = false
            mixpanel?.track("/CLEAR load vesting chart ", this.model.onlySetAttributes(private: true))


    loadingChart: () ->
      vestingYears = parseFloat(this.model.get('vesting_years'), 10) || 4
      numOptions = parseInt(this.model.get('number_of_options'), 10) || 1000
      vestingCliffYears = parseFloat(this.model.get('vesting_cliff_years'), 10) || 0
      # need a deep copy of the default options, otherwise
      # javascript nested-copy-by-reference will change the options
      # for ALL charts.
      options = JSON.parse(JSON.stringify(@GOOGLE_CHART_OPTIONS_STYLE))
      largerScalar = 1.75
      options.hAxis.title = 'years'
      options.hAxis.ticks = (i for i in [0..vestingYears])
      options.hAxis.viewWindow = { max: vestingYears,  min: 0 }
      options.vAxis.title = 'vested options'
      options.vAxis.viewWindow = { max: numOptions * largerScalar, min: 0 }
      options.vAxis.format = 'short'
      options.legend.position = 'bottom'

      noLoading = this.vestingChartSeries(numOptions, vestingYears, vestingCliffYears, null)
      backLoadingEqual = this.vestingChartSeries(numOptions, vestingYears, vestingCliffYears, 'back-loaded')
      backLoadingMore = this.vestingChartSeries(numOptions * largerScalar, vestingYears, vestingCliffYears, 'back-loaded')
      allLoadings = [['year', 'no loading', 'backloaded, equal', 'backloaded, larger']]
      for i in [1..(noLoading.length-1)]
        allLoadings.push [noLoading[i][0], noLoading[i][1], backLoadingEqual[i][1], backLoadingMore[i][1]]
      # in order of goodness.
      options.colors = [
        '#888', #no loading neutral
        '#C0423F', # backloading same amount red/bad
        '#007047' # backloading, more: green/good
      ]

      Google.load 'visualization', @GOOGLE_VIZ_VERSION,
        packages: ['corechart'],
        callback: =>
          data = Google.visualization.arrayToDataTable(allLoadings)
          chart = new Google.visualization.LineChart @$('.js-loadingChart')[0]
          chart.draw(data, options)
          this.loadingChartFirstLoad = true if typeof(this.loadingChartFirstLoad) is 'undefined'
          if data.getNumberOfRows() > 0 and this.loadingChartFirstLoad
            this.loadingChartFirstLoad = false
            mixpanel?.track("/CLEAR load loading chart ", this.model.onlySetAttributes(private: true))

    vestingChartSeries: (numOptions, vestingYears, vestingCliffYears, loading) ->
      data = [['year', '# vested']]
      # just using quadratic/sqrt as example model for front/back loading
      # actual loading function isn't standard and doesn't matter much
      degree = 3
      if loading is "front-loaded"
        coeffecient = numOptions / Math.pow(vestingYears, 1/degree)
        optionsAtYear = (numOptions, vestingYears, year) ->
          Math.floor( coeffecient * Math.pow(vestingYears, 1/degree) )
      else if loading is "back-loaded"
        coeffecient = numOptions / Math.pow(vestingYears, degree)
        optionsAtYear = (numOptions, vestingYears, year) ->
          Math.floor(coeffecient * Math.pow(year, degree))
      else
        coeffecient = numOptions/vestingYears
        optionsAtYear = (numOptions, vestingYears, year) ->
          Math.floor(coeffecient * year)
      # the zeroes pre-cliff (exclusive range)
      for i in [0...Math.floor(vestingCliffYears)]
        data.push [i, 0]
      # zero and cliff vesting amount at same loc.
      data.push [vestingCliffYears, 0]
      data.push [vestingCliffYears, optionsAtYear.apply(this, [numOptions, vestingYears, vestingCliffYears])]
      # vesting progressively after the cliff
      for i in [Math.ceil(vestingCliffYears)..vestingYears]
        data.push [i, optionsAtYear.apply(this, [numOptions, vestingYears, i])]
      return data


    updateURL: () =>
      encoded = document.location.pathname + '?' + this.encodeForURL() + document.location.hash
      history.replaceState({}, document.title, encoded)
      @$('.js-shareURL').val(document.location.href)


    encodeForURL: ->
      btoa(JSON.stringify(this.model.onlySetAttributes()))


    decodeFromURL: ->
      try
        return JSON.parse(atob(document.location.search.split("?")[1]))
      catch
        return {}


    formatLarge: (number, options) ->
      this.formatLocale(number, $.extend(options, {
        maximumSignificantDigits: 3
      }))


    formatLargeCurrency: (number, options) ->
      this.formatLocale(number, $.extend(options, {
        style: "currency",
        currency: "USD",
        currencyDisplay: "symbol",
        maximumSignificantDigits: 3
      }))


    formatSmall: (number, options) ->
      this.formatLocale(number, $.extend(options, {maximumSignificantDigits: 2}))


    formatPercent: (number, options) ->
      this.formatLocale(number, $.extend(options, {
        minimumSignificantDigits: 1
        maximumSignificantDigits: 3
        style: "percent"
      }))


    formatSmallCurrency: (number, options) ->
      this.formatLocale(number, $.extend(options, {
        style: "currency"
        currency: "USD"
        currencyDisplay: "symbol"
      }))


    formatLocale: (number, options) ->
      # the "or undefined" handles NaN for when the number is empty, nonnumeric, etc.
      # which when passed to @$('someDisplayElement').text(), won't change the text
      # from the default generic text.
      float = parseFloat(number, 10)
      return if isNaN(float) then undefined else float.toLocaleString(undefined, options)


    filterCompensationData: (options) ->
      options = $.extend({
        target: null
        compensationType: null
        filters: {
          locations: this.model.get('location')
          roles: this.model.get('role')
        }
      }, options)

      # Find all of the job listings matching current filter set
      histogramIntersection = []
      for own filterType, filter of options.filters
        if filter? and filter.length > 0 and this.comparables.compensations.tags[filterType][filter]
           # Find all job listing ids that match filter
          idsInSet = this.comparables.compensations.tags[filterType][filter].list
          if(histogramIntersection.length == 0)
            histogramIntersection = idsInSet
          else
            histogramIntersection = _.intersection(histogramIntersection, idsInSet)

      # TODO: if we want to use this to drive clicks on buckets in histogram
      # into "view these hiring startups", will have to persists the buckets
      # in a scope outside this function.
      buckets = []
      # Break into salary or buckets
      for idsInRange in this.comparables.compensations[options.compensationType]
        buckets.push(_.intersection(idsInRange, histogramIntersection).length)

      yValues = buckets
      xValues = this.comparables.compensations[options.compensationType + "_ranges"]
      data = [["", "# jobs", { role: 'annotation' }]]
      # if we have a target val, add in a style
      # column and then find the right bucket and highlight it
      if options.target?
        data[0] = data[0].concat [{ role: 'style' }]
      for i in [0...xValues.length]
        # sadly google charts don't allow HTML in axis ticks.
        # (or at least I can't figure out how)
        label = xValues[i].replace('&ndash;', '–')
        row = [
          label + (if options.compensationType is 'equity' then '%' else ''),
          yValues[i],
          yValues[i]
        ]
        if options.target?
          # this is stringly-typed bucketing, and sucks,
          # but the pre-computed salary/equity data is given
          # to us by the cached calcus in strings.
          bucketDesc = label.replace(/k/g, '')
          minifiedLabel = ''
          unit = (if options.compensationType is 'equity' then '%' else 'k')
          if bucketDesc.indexOf('<') != -1 # '<59k'
            bucketDesc = bucketDesc.replace('<', '')
            bucketMin = parseFloat(bucketDesc, 10)
            thisBucket = options.target <
            minifiedLabel = '<' + bucketMin + unit
          else if bucketDesc.match(/(–|-)/) # 100k-112k
            bucketRange = bucketDesc.split(/(–|-)/)
            min = parseFloat(bucketRange[0], 10)
            max = parseFloat(bucketRange[2], 10)
            thisBucket = options.target >= min and options.target <= max
            minifiedLabel = min + unit
          else if bucketDesc.match(/(\+|\>)/) # '160k+', '>=1%'
            bucketMin = parseFloat(bucketDesc.replace(/[>=+]/g, ''), 10)
            thisBucket = options.target >= bucketMin
            minifiedLabel = '>' + bucketMin + unit
          row[0] = minifiedLabel
          row = row.concat [if thisBucket then 'color: #366ad3;' else null]

        data = data.concat [row]
      data

    optionsInMoneyChart: () ->
      inMoneyFloor = this.model.commonOptionsInMoneyFloor()
      data = [['exit value', 'value of your options'], [0,0]]
      maxValForChart = inMoneyFloor * 1.4 # visual buffer 40% beyond floor
      numPlotPointsPostInMoney = 6
      plotPointsIncrement = Math.floor((maxValForChart - inMoneyFloor) / numPlotPointsPostInMoney)
      return if isNaN(inMoneyFloor) or !inMoneyFloor
      for i in [0...numPlotPointsPostInMoney]
        increaseInCompanyValue = (i * plotPointsIncrement)
        data = data.concat [[
          inMoneyFloor + increaseInCompanyValue,
          increaseInCompanyValue
        ]]
      options  = JSON.parse(JSON.stringify(@GOOGLE_CHART_OPTIONS_STYLE))
      options.title = 'Your Payout at Exit Values'
      options.hAxis.viewWindow = { min: 0, max: maxValForChart }
      options.vAxis.viewWindow = { min: 0, max: maxValForChart }
      options.hAxis.title = 'company value'
      options.vAxis.title = 'your payout'
      options.hAxis.format = 'short'
      options.vAxis.format = 'short'
      Google.load 'visualization', @GOOGLE_VIZ_VERSION,
        packages: ['corechart'],
        callback: =>
          data = Google.visualization.arrayToDataTable data
          chart = new Google.visualization.LineChart @$('.js-optionsInMoneyChart')[0]
          chart.draw(data, options)
          this.optionsInMoneyChartFirstLoad = true if typeof(this.optionsInMoneyChartFirstLoad) is 'undefined'
          if this.optionsInMoneyChartFirstLoad and data.getNumberOfRows() > 0
            this.optionsInMoneyChartFirstLoad = false
            mixpanel?.track("/CLEAR load options-in-money chart ", this.model.onlySetAttributes(private: true))


    presets: {
      clear1: {
        exercise_window_years: {
          value: 10
          disable: true
          selector: '.js-exerciseWindowYears'
        }
        exercise_window_days: {
          value: 0
          disable: true
          selector: '.js-exerciseWindowDays'
        }
        acceleration: {
          value: "double-trigger"
          disable: false
        }
        early_exercise: {
          value: "yes"
          disable: true
          selector: '.js-earlyExercise'
        }
      }
      clear2: {
        exercise_window_years: {
          value: null
          disable: true
          selector: '.js-exerciseWindowYears'
        }
        exercise_window_days: {
          value: 90
          disable: true
          selector: '.js-exerciseWindowDays'
        }
        net_exercise: {
          value: "yes"
          disable: true
          selector: '.js-netExercise'
        }
        early_exercise: {
          value: "yes"
          disable: true
          selector: '.js-earlyExercise'
        }
      }
      unclear: {}
    }


    selectPreset: (preset, button) ->
      return if preset not in Clear.PRESETS
      this.model.set('preset', preset)
      # reset any other preset locking/highlighting etc.
      @$('.js-clearPreset').removeClass('u-bgWhite')
      @$('.js-clearPreset').removeClass('u-bgGray')
      @$('.js-clearPreset').addClass('u-bgGray')
      @$('.js-clearPreset .c-button').text('use')
      @$('.js-disabledFromClear').each () ->
        $(this).prop('disabled', false)
        $(this).removeClass('js-disabledFromClear')
        $(this).removeClass('js-disabledFromClear')
        $(this).qtip('disable', true)
      @$('.fontello-lock.gutter-icon').remove()
      # hilight the used preset at header
      @$('.js-clearPreset.js-' + preset).removeClass('u-bgGray')
      @$('.js-clearPreset.js-' + preset).removeClass('u-bgGray')
      @$('.js-clearPreset.js-' + preset + ' .c-button').text('in use ').append($('<span class="fontello-ok">'))
      @$('.js-clearPreset.js-' + preset).addClass('u-bgWhite')
      # set preset values, lock inputs.
      for attr, toSet of this.presets[preset]
        this.model.set(attr, toSet.value)
        if toSet.disable
          this.lockTerm(@$(toSet.selector))
      mixpanel?.track("/CLEAR used a preset", _.extend(this.model.onlySetAttributes(private: true), {preset: preset}))

    lockTerm: (input) ->
      term = input.closest('.js-clearTerm')
      termTitle = term.find('.js-termTitle')
      lockedIcon = $('<span class="fontello-lock gutter-icon u-colorGray8"></span>')
      input.prop('disabled', true)
      input.addClass('js-disabledFromClear')
      term.find('.gutter-icon.fontello-lock').remove()
      lockedIcon.insertBefore(termTitle)
      termTitle.attr('title', "Part of the CLEAR protections. Altering can create painful, unfair consequences.")
      termTitle.qtip('disable', false)
      termTitle.qtip()
      term.addClass('js-disabledFromClear')

    # warning against 'business logic' errors like
    # a punitive exercise window
    warnAgainstMistakes: () ->
      this.clearWarnings()
      this.warnExerciseWindows()
      this.warnEarlyExercise()

    warnEarlyExercise: () ->
      noEarlyExercise = this.model.get('early_exercise') isnt 'yes'
      if noEarlyExercise
        this.warnTerms(
          ['.js-earlyExercise'],
          'While you have to pay and take on some risk, early-exercise can save a lot of tax.')

    warnExerciseWindows: () ->
      noNetExercise = this.model.get('net_exercise') isnt 'yes'
      shortWindow = this.model.exerciseWindowYears() < 2
      if noNetExercise and shortWindow
        this.warnTerms(
          ['.js-netExercise', '.js-exerciseWindowYears']
          'You can lose all the stock you earn with a short exercise window and no net-exercise')

    warnTerms: (termSelectors, message) ->
      for termSelector in termSelectors
        input = @$(termSelector)
        term = input.closest('.js-clearTerm')
        isNewWarning = !term.hasClass('js-termWarning')
        termTitle = term.find('.js-termTitle')
        warnIcon = $('<span class="fontello-attention-circled gutter-icon warning"></span>')
        term.addClass('js-termWarning')
        term.find('.gutter-icon.fontello-attention-circled').remove()
        warnIcon.insertBefore(termTitle)
        term.attr('title', message)
        term.qtip()
        term.qtip('disable', false)
        mixpanel?.track(
          "/CLEAR warned on a term",
          _.extend(
            {warnedTerm: termSelector},
            this.model.onlySetAttributes(private: true))) if isNewWarning

    clearWarnings: () ->
      warnings = @$('.js-termWarning')
      # we hide then disable because it's possible
      # that the warning is removed whiel the mouse is still
      # over the offending term, e.g. it was used to change
      # the offending value to an ok value
      warnings.qtip("hide")
      warnings.qtip('disable', true)
      @$('.fontello-attention-circled.gutter-icon').remove()

    generatePDF: () ->
      return if not @PDFS_ENABLED
      shadowPDF = @$('.js-shadowPDF')
      downloadButton = @$('.js-downloadButton')
      oldButtonText = downloadButton.text()
      downloadButton.width(downloadButton.outerWidth())
      downloadButton.html('<span class="fontello-spin1"></span>')
      mixpanel?.track("/CLEAR generate PDF", this.model.onlySetAttributes(private: true))

      margins = {
        top: 10
        bottom: 60
        left: 40
        width: 522
      }
      pdf = new jsPDF('p', 'pt', 'letter')
      # clone then delete hidden elements because jsPDF is dumb
      # and renders non-visible elements
      clone = shadowPDF.clone()
      clone.find('.u-hidden').remove()
      clone.insertAfter(shadowPDF)
      pdf.fromHTML(
        clone[0],
        margins.left,
        margins.top,
        { width: margins.width },
        () ->
          pdf.save('CLEAR ' + downloadButton.data('doc_title') + '.pdf')
          downloadButton.text(oldButtonText)
          clone.remove()
      )
