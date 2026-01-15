define [
  'underscore',
  'backbone-validation',
  'models/base',
], (_, BackboneValidation, base) ->
  # there's no server-side storage or validation of the CLEAR doc.
  # We use a backbone model as just data encapsulation, and some validation.
  # That's it.
  #_.extend(Backbone.Model.prototype, Backbone.Validation.mixin)
  class Clear extends base 'Clear'
    @BENEFITS = [
      "health",
      "dental",
      "vision",
    ]
    @LOADING = ['none', 'front-loaded', 'back-loaded']
    @ACCELERATION = ['none', 'single-trigger', 'double-trigger']
    @CAN_BUY = {
      1: { text: 'nothing', emoji: '🤷'}
      10: { text: 'meal', emoji: '🍽'  }
      100: { text: 'nice dinner', emoji: '🍽🍷'}
      1000: { text: 'tv', emoji: '📺'}
      10000: { text: 'used car', emoji: '🚗'}
      100000: { text: 'luxury car', emoji: '🏎' }
      1000000: { text: 'house', emoji: '🏠'}
      10000000: { text: 'luxury house', emoji: '🏡'}
      100000000: { text: 'financial freedom', emoji: '🏡 🏎 ⛷ ✈ 🏄🏼' }
    }
    @PRESETS = ['clear1', 'clear2', 'unclear']
    @SERIES: ['seed', 'A', 'B', 'C+']
    # source: https://www.quora.com/Venture-Capital-Funding-What-is-the-usual-percentage-of-shares-that-go-to-seed-Series-A-and-Series-B-rounds
    @AVG_INVESTOR_EQUITY_PERCENT: {
      seed: 20
      A: 20
      B: 25
      'C+': 25
    }
    # source: https://www.fenwick.com/FenwickDocuments/Silicon-Valley-Venture-Capital-Survey-Third-Quarter-2016.pdf
    @AVG_ROUND_MARKUP_PERCENT: {
      seed: 56
      A: 50
      B: 116
      'C+': 84
    }

    defaults: {
      # base_comp
      salary: null,
      health: null,
      dental: null,
      vision: null,
      retirement: null,
      vacation_days: null,

      # shared ownership
      number_of_options: null,
      outstanding_shares: null,
      equity_percent: null
      latest_valuation_per_share: null,
      latest_valuation: null, # for some in-money floor calcs. not source of truth.
      latest_series: 'A'
      liquidation_preference: 1
      vesting_years: 4,
      vesting_cliff_years: 1
      loading: null,
      early_exercise: 'yes',
      preference_floor: null,

      # exercising
      strike_price: null,
      exercise_window_years: null,
      exercise_window_days: null,
      net_exercise: null,

      company_representation: null,

      # help in giving comparisons
      # tag names from cached data also used in /salaries
      location: 'San Francisco'
      role: 'Developer'

      # help w/ navigating the tool
      preset: 'clear1'
      purpose: 'offer'
      user_role: 'company'

    }

    @PURPOSES: ['offer', 'amendment', 'evaluate']
    @USER_ROLES: ['company', 'employee']

    # separate from validation b.c. there are two
    # cases: offer and amendment
    @REQUIRED: {
      offer: [
        'salary'
        'number_of_options'
        'outstanding_shares'
        'equity_percent'
        'vesting_years'
        'vesting_cliff_years'
        'loading'
        'early_exercise'
        'strike_price'
        'exercise_window_years'
        'exercise_window_days'
        'net_exercise'
      ]
      amendment: {
        'loading'
        'early_exercise'
        'exercise_window_years'
        'exercise_window_days'
        'net_exercise'
      }
    }

    validation: {
      salary: {
        min: 1,
        msg: "must be a positive number"
      },
      health: {
        fn: '_boolean'
      },
      dental: {
        fn: '_boolean'
      },
      vision: {
        fn: '_boolean'
      },
      vacation_days: {
        min: 0,
        msg: 'cannot be negative. leave blank for unlimited.'
      },
      number_of_options: [
        {
          min: 0,
          msg: 'cannot be negative'
        },
        {
          fn: 'validateEquity'
        }
      ],
      outstanding_shares: [
        {
          min: 0,
          msg: "must be a positive number"
        },
        {
          fn: 'validateEquity'
        }
      ],
      equity_percent: {
        min: 0,
        msg: 'cannot be negative',
      },
      latest_valuation_per_share: {
        min: 0,
        msg: 'cannot be negative',
      },
      latest_valuation: {
        min: 0
        msg: 'cannot be negative'
      }
      liquidation_preference: {
        min: 0
        msg: 'cannot be negative'
      }
      latest_series: {
        oneOf: this.SERIES,
      }
      vesting_years: {
        min: 0,
        msg: 'cannot be negative'
      },
      vesting_cliff_years: {
        min: 0,
        msg: 'cannot be negative'
      },
      loading: {
        oneOf: this.LOADING
      },
      acceleration: {
        oneOf: this.ACCELERATION
      },
      acceleration_years: {
        min: 0,
        msg: 'cannot be negative'
      },
      preference_floor: {
        min: 1
        msg: 'must be positive'
      },
      strike_price: {
        min: 0,
        msg: 'cannot be negative'
      },
      exercise_window_years: [
        {
          range: [0, 10]
          msg: 'max 10 years, by law'
        },
        {
          fn: 'validateTotalExerciseWindow'
          msg: 'max 10 years, by law'
        },
      ],
      exercise_window_days: [
        {
          range: [0, 365]
          msg: 'must be positive, less than a year (365 days)'
        },
        {
          fn: 'validateTotalExerciseWindow'
          msg: 'max 10 years, by law'
        },
      ],
      net_exercise: {
        oneOf: ["yes", "no"]
      }
      preset: {
        oneOf: this.PRESETS
      }
      company_representation: {
        fn: '_boolean'
      }
    }

    _boolean: (val) ->
      return 'must be yes/no' unless (val in [null, true, false])

    benefits: () ->
      benefits = []
      for benefit in @constructor.BENEFITS
        benefits.push(benefit.charAt(0).toUpperCase() + benefit.slice(1)) if this.get(benefit)
      return benefits.join(', ')

    oldTranslations: {
      # if we ever change an attribute name, old links that referenced it will break
      # and we'll need to have a translation step from old_name to new_name
      # old_attribute_name: (oldVal) -> setNewAttrs()
    }

    initialize: (options) ->
      super(options)
      this.setRequiredValidations()
      this.on('change', this.updateTerms, this)

    setRequiredValidations: () ->
      for attr in @constructor.REQUIRED[this.get('purpose')]
        if Object.prototype.toString.call(this.validation[attr]) is '[object Array]'
          this.validation[attr].concat({ required: true})
        else if typeof(this.validation[attr]) is 'object'
          this.validation[attr].required = true


    validateEquity: (val, attrName, attributes) ->
      numOptions = parseInt(attributes.number_of_options, 10)
      outstandingShares = parseInt(attributes.outstanding_shares, 10)
      if numOptions >= outstandingShares
        return "# of options must be less than # of outstanding shares"

    validateTotalExerciseWindow: (val, attrName, attributes) ->
      years = parseInt(attributes.exercise_window_years, 10)
      days = parseInt(attributes.exercise_window_days, 10)
      if years*365 + days > 10*365
        return "max 10 years, by law"

    exerciseWindowYears: () ->
      years = parseInt(this.get('exercise_window_years', 10))
      days = parseInt(this.get('exercise_window_days', 10))
      if isNaN(years) and isNaN(days)
        return NaN
      else
        (365*(years || 0) + (days || 0)) / 365


    companyValuation: () ->
      parseInt(this.get('outstanding_shares'), 10) * parseFloat(this.get('latest_valuation_per_share'), 10)

    equityPercent: () ->
      100 * this.equityRatio()

    equityRatio: () ->
      fromNumShares = parseInt(this.get('number_of_options'), 10) / parseInt(this.get('outstanding_shares'), 10)
      fromDirectInput = parseFloat(this.get('equity_percent')) / 100
      return fromNumShares || fromDirectInput

    latestValuation: (options) ->
      options = _.extend({}, options)
      fromSharesAndPerShare = (parseFloat(this.get('outstanding_shares')) * parseFloat(this.get('latest_valuation_per_share'), 10))
      entered = parseInt(this.get('latest_valuation'))
      if options.useEnteredValuation
        return fromSharesAndPerShare || entered
      else
        return fromSharesAndPerShare

    costToExercise: () ->
      parseFloat(this.get('strike_price'), 10) * parseInt(this.get('number_of_options'))

    commonOptionsInMoneyFloor: () ->
      costToExercise = this.costToExercise()
      preferenceFloor = parseFloat(this.get('preference_floor'), 10) || this.ballparkPreferenceFloor()
      if costToExercise and preferenceFloor
        return preferenceFloor + costToExercise
      else
        return undefined


    valueOfOptions: (exitValue) ->
      preferenceFloor = parseInt(this.get('preference_floor', 10)) || this.ballparkPreferenceFloor()
      # if we know the series, ballpark future dilution.
      series = this.get('latest_series') || this.defaults.latest_series
      i = @constructor.SERIES.indexOf(series)
      equityRatio = this.equityRatio()
      while i < @constructor.SERIES.length
        dilutionNextRoundRatio = @constructor.AVG_INVESTOR_EQUITY_PERCENT[@constructor.SERIES[i]] / 100
        equityRatio = equityRatio / (( 1 - equityRatio) + dilutionNextRoundRatio)
        i++
      value = ((exitValue - preferenceFloor) * equityRatio) - this.costToExercise()
      if value? and !isNaN(value) then value else undefined


    ballparkPreferenceFloor: () ->
      series = this.get('latest_series')
      liqpref = parseFloat(this.get('liquidation_preference'), 10)
      latestValuation = this.latestValuation() || parseInt(this.get('latest_valuation'), 10)
      if latestValuation and series and liqpref
        floor = 0
        i = @constructor.SERIES.indexOf(series)
        thisRoundValuation = latestValuation
        while i >= 0
          thisRoundInvestorEquity = @constructor.AVG_INVESTOR_EQUITY_PERCENT[@constructor.SERIES[i]] / 100
          floor += Math.floor((thisRoundValuation * thisRoundInvestorEquity) * liqpref)
          # iteration step goes back one series
          i--
          thisRoundValuation = Math.floor((thisRoundValuation / (1 + @constructor.AVG_ROUND_MARKUP_PERCENT[@constructor.SERIES[i]])))
      return floor

    onlySetAttributes: (options) ->
      options ?= {}
      onlySetAttributes = {}
      _.each(this.attributes, (value, key) ->
        if value? and value != ""
          onlySetAttributes[key] = if options.private then "private" else value
      )
      return onlySetAttributes

    numSetAttributes: () ->
      count = 0
      _.each(this.attributes, (value, key) ->
        count += 1 if value? and value != ""
      )
      return count
