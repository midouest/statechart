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

local state = machine.initialState           // state = 'initial'
state = machine:transition(state, 'FETCH')   // state = 'loading'
state = machine:transition(state, 'REJECT')  // state = 'failure'
state = machine:transition(state, 'RETRY')   // state = 'loading'
state = machine:transition(state, 'RESOLVE') // state = 'success'
```
