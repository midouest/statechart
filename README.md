# statechart
Lua statechart library inspired by XState

## Example
```lua
local StateChart = require 'statechart'

local fetchMachine = StateChart.machine {
  initial = 'idle',
  context = {
    retries = 0,
  },
  states = {
    idle = {
      events = {
        FETCH = 'loading',
      },
    },
    loading = {
      events = {
        RESOLVE = 'success',
        REJECT = 'failure',
      },
    },
    success = {},
    failure = {
      events = {
        RETRY = {
          target = 'loading',
          actions = function(context, event)
            context.retries = context.retries + 1
          end,
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
```
