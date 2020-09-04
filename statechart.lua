--[[ StateChart ////////////////////////////////////////////////////////////////
  Statechart library inspired by XState

  Example:
  ```
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
]] local StateChart = {}

-- print a table
-- @param t the table to print
-- @param indent the number of spaces to use for indentation
function StateChart.print_table(t, indent)
  if type(t) ~= 'table' then
    print(t)
    return
  end

  indent = indent or 2

  local function print_table_inner(t, depth)
    local pad = string.rep(' ', indent * depth)
    for k, v in pairs(t) do
      if type(v) == 'table' then
        print(pad .. k .. '={')
        print_table_inner(v, depth + 1)
        print(pad .. '},')
      elseif type(v) == 'string' then
        print(pad .. k .. '="' .. v .. '",')
      else
        print(pad .. k .. '=' .. tostring(v) .. ',')
      end
    end
  end

  print('{')
  print_table_inner(t, 1)
  print('}')
end

function shallow_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in pairs(orig) do
      copy[orig_key] = orig_value
    end
  else
    copy = orig
  end
  return copy
end

function deep_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[deep_copy(orig_key)] = deep_copy(orig_value)
    end
  else
    copy = orig
  end
  return copy
end

local Object = {}

-- create a new object prototype
function Object:clone(obj)
  obj = obj or {}
  setmetatable(obj, self)
  self.__index = self
  return obj
end

--[[ Transition ////////////////////////////////////////////////////////////////
  A transition represents a state change candidate for a single event.

  Transitions may contain guard clauses that prevent the transition from
  occurring unless certain conditions are met.
]]
local Transition = Object:clone()

-- Evaluate the guard for this transition, if any, given the current context and
-- most recent event
-- @return the condition if there is no guard or the guard is met, otherwise nil
function Transition:eval(context, event)
  if not self.guard or self.guard(context, event) then
    return self
  else
    return nil
  end
end

--[[ MultiTransition ///////////////////////////////////////////////////////////
  A multi-transition represents one or more state change candidates for a single
  event.

  When evaluated, multi-transitions return the first child-transition that
  evaluates to true.
]]
local MultiTransition = Transition:clone()

-- Evaluate all child transitions until one is satisfied
function MultiTransition:eval(context, event)
  for _, transition in ipairs(self.transitions) do
    if transition:eval(context, event) then
      return transition
    end
  end
  return nil
end

-- Constructs a concrete transition from the given table
-- @param cfg A table or string representing the transition. If the table has an
--            index at 1, then it will be treated as a MultiTransition.
-- @return A Transition or MultiTransition
local function build_transition(cfg)
  if type(cfg) == 'string' then
    return Transition:clone{target = cfg}
  elseif type(cfg) == 'table' then
    if cfg[1] then
      local transitions = {}
      for _, subcfg in ipairs(cfg) do
        table.insert(transitions, Transition:clone(subcfg))
      end
      return MultiTransition:clone{transitions = transitions}
    else
      return Transition:clone(cfg)
    end
  else
    error('expected string or table transition but got ' .. type(cfg))
  end
end

--[[ AbstractConfig ////////////////////////////////////////////////////////////
  The abstract base class for all state config types.

  A state config is an immutable command object that is used to find the next
  state for a given context and current state.
]]
local AbstractConfig = Object:clone{}

-- Get the initial value for the state config
function AbstractConfig:initial_value()
  error('not implemented')
end

-- True if the given state value represents a final state, otherwise false
function AbstractConfig:is_done(value)
  error('not implemented')
end

-- Calculate the next state
-- @param context Top-level context independent of state
-- @param value Table representing the state of each node in the state hierarchy
-- @param event The most recent event
-- @return The new state
function AbstractConfig:transition(context, value, event)
  error('not implemented')
end

--[[ AtomicConfig //////////////////////////////////////////////////////////////
  An atomic state represents the smallest possible state in the state hierarchy.

  Atomic states do not have any internal state. Atomic states are used to
  represent the internal state of higher-level states such as compound or
  parallel states.

  Atomic states respond to events with transitions that cause higher-level
  states to change their internal state.
]]
local AtomicConfig = AbstractConfig:clone{type = 'atomic'}

-- An atomic state has no initial state value
function AtomicConfig:initial_value()
  return nil
end

-- An atomic state is never a final state
function AtomicConfig:is_done(value)
  return false
end

-- An atomic state can only ever return transitions that cause higher-level
-- states to change
function AtomicConfig:transition(context, value, event)
  assert(value == nil or value == self.id,
         'unexpected atomic state value ' .. tostring(value))
  local transition = nil

  if self.events then
    local candidate = self.events[event] or self.events['*']
    transition = candidate and candidate:eval(context, event) or nil
  end

  if not transition and self.always then
    transition = self.always:eval(context, event)
  end

  return {
    value = value,
    changed = false,
    transition = transition,
    actions = nil,
  }
end

--[[ FinalConfig ///////////////////////////////////////////////////////////////
  A final state is used to terminate a higher-level state, such as compound or
  parallel states.

  Final states have no internal state and never respond to events.
]]
local FinalConfig = AtomicConfig:clone{type = 'final'}

-- A final state is always done
function FinalConfig:is_done(value)
  return true
end

-- A final state does not respond to events and does not return transitions.
-- Once a higher-level state has reached its final state, it should no longer
-- transition internally. 
function FinalConfig:transition(context, value, event)
  assert(value == nil or value == self.id,
         'unexpected final state value ' .. value)
  return {value = value, changed = false, transition = nil, actions = nil}
end

--[[ CompoundConfig ////////////////////////////////////////////////////////////
  A compound state is in one internal state at a time.
]]
local CompoundConfig = AtomicConfig:clone{type = 'compound'}

local function to_value(id, obj)
  return obj and {[id] = obj} or id
end

function CompoundConfig:initial_value()
  local value = self.states[self.initial]:initial_value()
  return to_value(self.initial, value)
end

local function get_subvalue(value)
  local id, subvalue
  if type(value) == 'table' then
    id, subvalue = next(value)
  else
    id = value
  end
  return id, subvalue
end

function CompoundConfig:is_done(value)
  local id, subvalue = get_subvalue(value)
  return self.states[id]:is_done(subvalue)
end

function CompoundConfig:transition(context, value, event)
  local id, subvalue = get_subvalue(value)
  local new_state = self.states[id]:transition(context, subvalue, event)

  if new_state.transition then
    local id = new_state.transition.target
    local subvalue = self.states[id]:initial_value()
    local new_value = to_value(id, subvalue)
    -- todo: exit actions
    -- todo: transition actions
    -- todo: resolve transient states
    -- todo: entry actions
    -- todo: check for done
    -- todo: history
    return {value = new_value, changed = true, transition = nil, actions = nil}
  end

  if new_state.changed then
    return {
      value = to_value(id, new_state.value),
      changed = true,
      transition = nil,
      actions = nil,
    }
  end

  return AtomicConfig.transition(self, context, value, event)
end

--[[ ParallelConfig ////////////////////////////////////////////////////////////
  A parallel state can be in multiple internal states simulaneously. Internal
  states are isolated from one another.
]]
local ParallelConfig = AtomicConfig:clone{type = 'parallel'}

function ParallelConfig:initial_value()
  local values = {}
  for id, node in pairs(self.states) do
    local subvalue = node:initial_value()
    values[id] = subvalue and subvalue or {}
  end
  return values
end

function ParallelConfig:is_done(value)
  for id, subvalue in pairs(value) do
    if not self.states[id]:is_done(subvalue) then
      return false
    end
  end
  return true
end

function ParallelConfig:transition(context, value, event)
  local any_changed = false
  local new_value = {}

  for id, subvalue in pairs(value) do
    local new_state = self.states[id]:transition(context, subvalue, event)
    new_value[id] = new_state.value
    any_changed = any_changed or new_state.changed
  end

  if any_changed then
    -- todo: check for done
    return {value = new_value, changed = true, transitions = nil, actions = nil}
  end

  return AtomicConfig.transition(self, context, value, event)
end

--[[ HistoryConfig /////////////////////////////////////////////////////////////
  A history state is used by compound states to track state changes. When a
  history state is entered, it immediately transitions to the most recent state.

  A history state can be either shallow or deep. A shallow history will only
  track the most recent top-level state. A deep history will track the most 
  recent top-level state and all of its substates.
]]
local HistoryConfig = AtomicConfig:clone{type = 'history'}

function HistoryConfig:transition(context, value, event)
  -- TODO: get node to transition to
  return {value = value, changed = false, transitions = nil, actions = nil}
end

--[[ Config ////////////////////////////////////////////////////////////////////
  Utilities for building a concrete config hierarchy from a table
]]
CONFIG_TYPES = {
  [AtomicConfig.type] = AtomicConfig,
  [FinalConfig.type] = FinalConfig,
  [CompoundConfig.type] = CompoundConfig,
  [ParallelConfig.type] = ParallelConfig,
  [HistoryConfig.type] = HistoryConfig,
}

local function get_config_type(cfg)
  if cfg.type then
    return Config.types[cfg.type]
  else
    if cfg.states then
      if cfg.initial then
        return CompoundConfig
      else
        return ParallelConfig
      end
    elseif cfg.events then
      return AtomicConfig
    elseif cfg.history or cfg.default then
      return HistoryConfig
    else
      return FinalConfig
    end
  end
end

local function build_config(cfg)
  if cfg.states then
    local states = {}
    for id, subcfg in pairs(cfg.states) do
      subcfg.id = id
      states[id] = build_config(subcfg)
    end
    cfg.states = states
  end

  if cfg.events then
    local events = {}
    for id, transition in pairs(cfg.events) do
      events[id] = build_transition(transition)
    end
    cfg.events = events
  end

  local config_type = get_config_type(cfg)
  return config_type:clone(cfg)
end

--[[ Machine ///////////////////////////////////////////////////////////////////
  A state machine is used to evaluate events on a given state in order to
  produce the next state.
]]
local Machine = Object:clone()

function Machine:transition(state, event)
  local new_state = self.config:transition(state.context, state.value, event)
  --[[
    TODO:
    - transient states?
    - exit, transition, entry actions?
    - delayed transitions?
    - history?
  ]]
  return {context = state.context, value = new_state.value}
end

function StateChart.machine(config)
  config = build_config(config)
  local m = Machine:clone{
    config = config,
    initialState = {
      value = config:initial_value(),
      context = config.context,
      --[[
        TODO:
        - event = {type: 'init'},
        - actions =
        - activities =
        - history
        - meta
        - done
      ]]
    },
  }

  return m
end

return StateChart
