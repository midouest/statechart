local StateChart = require 'statechart'

local fetchMachine = StateChart.machine {
  initial = 'idle',
  context = {
    retries = 0,
  },
  states = {
    idle = {
      events = {
        FETCH = {
          target = 'loading',
          actions = function()
            print('idle -> loading')
          end
        },
      },
    },
    loading = {
      events = {
        RESOLVE = {
          target = 'success',
          actions = function()
            print('loading -> success')
          end
        },
        REJECT = {
          target = 'failure',
          actions = function()
            print('loading -> failure')
          end
        },
      },
    },
    success = {},
    failure = {
      events = {
        RETRY = {
          target = 'loading',
          actions = function(context, event)
            print('failure -> loading')
            context.retries = context.retries + 1
          end
        },
      },
    },
  },
}

local state = fetchMachine.initial_state          -- state = 'initial'
state = fetchMachine:transition(state, 'FETCH')   -- state = 'loading'
state = fetchMachine:transition(state, 'REJECT')  -- state = 'failure'
state = fetchMachine:transition(state, 'RETRY')   -- state = 'loading'
state = fetchMachine:transition(state, 'RESOLVE') -- state = 'success'
