#!/bin/bash
lua_dir=/opt/homebrew/opt/lua@5.3
eval $(luarocks --lua-dir=$lua_dir path)
$lua_dir/bin/lua statechart_test.lua
