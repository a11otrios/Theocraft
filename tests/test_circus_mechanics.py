"""Behavioural tests for the Circus Pack's timing-critical mechanics.

Loads the real mod files through a mocked Luanti API (lupa) so the rhythm,
balancing, and music-box helpers are exercised exactly as the game runs them.
"""

from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
MOD_DIR = ROOT / "mods" / "theocraft_circus"

HARNESS = """
registered = {{nodes = {{}}, items = {{}}, crafts = {{}}, commands = {{}}, steps = {{}}, hpchange = {{}}, placenode = {{}}}}
SOUND_SEQ = 0
SOUNDS_PLAYED = {{}}
SOUNDS_STOPPED = {{}}
WORLD = {{}}
CHAT = {{}}
values = {{}}
minetest = {{
  get_current_modname = function() return "theocraft_circus" end,
  get_modpath = function() return "{mod_dir}" end,
  get_mod_storage = function()
    return {{
      get_string = function(_, k) return values[k] or "" end,
      set_string = function(_, k, v) values[k] = v end,
    }}
  end,
  settings = {{
    get = function(_, k)
      if k == "theocraft_circus_popcorn_food" then return "2" end
      if k == "theocraft_circus_area_radius" then return "14" end
      return nil
    end,
    get_bool = function(_, k, default) return true end,
  }},
  log = function() end,
  register_node = function(name, def) registered.nodes[name] = def end,
  register_craftitem = function(name, def) registered.items[name] = def end,
  register_craft = function(def) registered.crafts[#registered.crafts + 1] = def end,
  register_chatcommand = function(name, def) registered.commands[name] = def end,
  register_globalstep = function(fn) registered.steps[#registered.steps + 1] = fn end,
  register_on_player_hpchange = function(fn) registered.hpchange[#registered.hpchange + 1] = fn end,
  register_on_placenode = function(fn) registered.placenode[#registered.placenode + 1] = fn end,
  item_eat = function(n) return function() end end,
  serialize = function(v) return "data" end,
  deserialize = function(s) return nil end,
  pos_to_string = function(p) return p.x .. "," .. p.y .. "," .. p.z end,
  get_node = function(p) return WORLD[minetest.pos_to_string(p)] or {{name = "air"}} end,
  get_node_or_nil = function(p) return WORLD[minetest.pos_to_string(p)] end,
  set_node = function(p, n) WORLD[minetest.pos_to_string(p)] = n end,
  swap_node = function(p, n) WORLD[minetest.pos_to_string(p)] = n end,
  get_meta = function(p)
    return {{
      set_string = function() end,
      get_string = function() return "" end,
      get_inventory = function()
        return {{
          get_size = function() return 24 end,
          set_size = function() end,
          add_item = function() end,
          is_empty = function() return true end,
        }}
      end,
    }}
  end,
  sound_play = function(name, spec)
    SOUND_SEQ = SOUND_SEQ + 1
    SOUNDS_PLAYED[#SOUNDS_PLAYED + 1] = {{handle = SOUND_SEQ, name = name, spec = spec}}
    return SOUND_SEQ
  end,
  sound_stop = function(h) SOUNDS_STOPPED[#SOUNDS_STOPPED + 1] = h end,
  chat_send_player = function(n, msg) CHAT[#CHAT + 1] = {{to = n, msg = msg}} end,
  chat_send_all = function(msg) CHAT[#CHAT + 1] = {{to = "*", msg = msg}} end,
  add_particlespawner = function() return 1 end,
  add_particle = function() end,
  after = function(t, fn) end,
  is_protected = function() return false end,
  is_creative_enabled = function() return false end,
  find_nodes_in_area = function() return {{}} end,
  find_node_near = function() return nil end,
  get_connected_players = function() return {{}} end,
  get_player_by_name = function() return nil end,
  get_us_time = function() return 0 end,
  dir_to_facedir = function() return 0 end,
  dir_to_yaw = function() return 0 end,
}}
vector = {{ subtract = function(a, b) return {{x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}} end }}
dofile("{mod_dir}" .. "/init.lua")
"""


def circus_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS.format(mod_dir=MOD_DIR.as_posix()))
    return lua, lua.globals().theocraft_circus


def test_mod_load_order_exposes_shared_helpers() -> None:
    lua, mod = circus_runtime()
    for helper in (
        "now_us",
        "juggle_tap",
        "update_balance",
        "set_music_box",
        "stop_music_at",
    ):
        assert callable(mod[helper]), helper
    commands = lua.eval("registered.commands")
    assert commands["circus"] is not None
    assert commands["build"] is not None
    items = lua.eval("registered.items")
    assert items["theocraft_circus:juggling_balls"] is not None


def test_juggling_combo_progresses_in_rhythm_window() -> None:
    lua, mod = circus_runtime()
    result = lua.eval(
        """
        (function()
          local state = {}
          local c1 = theocraft_circus.juggle_tap(state, 1000000)
          local c2 = theocraft_circus.juggle_tap(state, 2000000)
          local c3 = theocraft_circus.juggle_tap(state, 3000000)
          return {c1, c2, c3, state.best}
        end)()
        """
    )
    assert tuple(result.values()) == (1, 2, 3, 3)


def test_juggling_resets_after_invalid_interval() -> None:
    lua, mod = circus_runtime()
    result = lua.eval(
        """
        (function()
          local out = {}
          local state = {}
          out[#out + 1] = theocraft_circus.juggle_tap(state, 1000000)
          out[#out + 1] = theocraft_circus.juggle_tap(state, 2000000)
          out[#out + 1] = theocraft_circus.juggle_tap(state, 12000000)
          out[#out + 1] = theocraft_circus.juggle_tap(state, 12100000)
          out[#out + 1] = theocraft_circus.juggle_tap(state, 13100000)
          out[#out + 1] = theocraft_circus.juggle_tap(state, 13350000)
          return out
        end)()
        """
    )
    # 1, 2, then a 10s gap restarts at 1, a 0.1s gap restarts at 1,
    # a 1s gap continues to 2, and the exact 0.25s boundary continues to 3.
    assert tuple(result.values()) == (1, 2, 1, 1, 2, 3)


def test_juggling_on_use_uses_engine_clock_and_tracks_player() -> None:
    lua, mod = circus_runtime()
    combo = lua.eval(
        """
        (function()
          NOW_US = 5000000
          theocraft_circus._now_us = function() return NOW_US end
          local user = {
            is_player = function() return true end,
            get_player_name = function() return "Theo" end,
            get_pos = function() return {x = 0, y = 0, z = 0} end,
            get_inventory = function()
              return {
                room_for_item = function() return true end,
                add_item = function() end,
              }
            end,
          }
          local def = registered.items["theocraft_circus:juggling_balls"]
          def.on_use({}, user, nil)
          NOW_US = 6000000
          def.on_use({}, user, nil)
          NOW_US = 20000000
          def.on_use({}, user, nil)
          return theocraft_circus.juggle_progress["Theo"].combo
        end)()
        """
    )
    # Two taps one second apart build a combo of 2; a 14s gap restarts at 1.
    assert combo == 1
    progress_best = lua.eval('theocraft_circus.juggle_progress["Theo"].best')
    assert progress_best == 2


def test_balance_medal_needs_sixty_seconds_of_balancing() -> None:
    lua, mod = circus_runtime()
    result = lua.eval(
        """
        (function()
          local medals_30s = 0
          local medals_60s = 0
          local medals_90s = 0
          local state = {}
          for i = 1, 60 do
            if theocraft_circus.update_balance(state, true, 0.5) == "medal" then
              medals_30s = medals_30s + 1
            end
          end
          for i = 1, 60 do
            if theocraft_circus.update_balance(state, true, 0.5) == "medal" then
              medals_60s = medals_60s + 1
            end
          end
          for i = 1, 60 do
            if theocraft_circus.update_balance(state, true, 0.5) == "medal" then
              medals_90s = medals_90s + 1
            end
          end
          return {medals_30s, medals_60s, medals_90s, state.time}
        end)()
        """
    )
    values = tuple(result.values())
    assert values[0] == 0, "no medal near 30 seconds"
    assert values[1] == 1, "exactly one medal at ~60 seconds"
    assert values[2] == 0, "no repeat medal for the same attempt"
    assert values[3] >= 60


def test_balance_resets_when_leaving_and_allows_a_new_attempt() -> None:
    lua, mod = circus_runtime()
    result = lua.eval(
        """
        (function()
          local state = {}
          for i = 1, 120 do theocraft_circus.update_balance(state, true, 0.5) end
          local reset_event = theocraft_circus.update_balance(state, false, 0)
          local cleared = (state.time == 0 and state.awarded == false)
          local second_medals = 0
          for i = 1, 120 do
            if theocraft_circus.update_balance(state, true, 0.5) == "medal" then
              second_medals = second_medals + 1
            end
          end
          return {reset_event, cleared, second_medals}
        end)()
        """
    )
    assert result[1] == "reset"
    assert result[2] is True
    assert result[3] == 1


def test_balance_cheers_periodically_without_medal() -> None:
    lua, mod = circus_runtime()
    result = lua.eval(
        """
        (function()
          local state = {}
          local events = {}
          for i = 1, 24 do
            local e = theocraft_circus.update_balance(state, true, 0.5)
            if e == "cheer" then events[#events + 1] = i end
          end
          return events
        end)()
        """
    )
    assert tuple(result.values()) == (12, 24)


def test_music_box_helper_starts_tracks_and_stops_sound() -> None:
    lua, mod = circus_runtime()
    result = lua.eval(
        """
        (function()
          local pos = {x = 0, y = 1, z = 0}
          WORLD["0,1,0"] = {name = "theocraft_circus:music_box_off", param2 = 0}
          theocraft_circus.set_music_box(pos, true)
          local node_on = WORLD["0,1,0"].name
          local handle1 = theocraft_circus.music_handles["0,1,0"]
          local looped = SOUNDS_PLAYED[#SOUNDS_PLAYED].spec.loop
          local played_after_first = #SOUNDS_PLAYED
          theocraft_circus.set_music_box(pos, true)
          local handle2 = theocraft_circus.music_handles["0,1,0"]
          local first_stopped = SOUNDS_STOPPED[1] == handle1
          theocraft_circus.set_music_box(pos, false)
          local node_off = WORLD["0,1,0"].name
          local cleared = theocraft_circus.music_handles["0,1,0"] == nil
          local second_stopped = SOUNDS_STOPPED[#SOUNDS_STOPPED] == handle2
          return {node_on, handle1 ~= nil, looped, played_after_first,
                  handle2 ~= nil, first_stopped, node_off, cleared, second_stopped}
        end)()
        """
    )
    assert result[1] == "theocraft_circus:music_box_on"
    assert result[2] is True, "handle stored on start"
    assert result[3] is True, "music sound loops"
    assert result[4] == 1, "exactly one sound for the first start"
    assert result[5] is True, "handle stored after re-activation"
    assert result[6] is True, "previous handle stopped before re-activation (no duplicates)"
    assert result[7] == "theocraft_circus:music_box_off"
    assert result[8] is True, "handle removed on switch-off"
    assert result[9] is True, "sound stopped on switch-off"


def test_manual_and_show_paths_share_the_music_helper() -> None:
    props = (ROOT / "mods" / "theocraft_circus" / "props.lua").read_text(encoding="utf-8")
    challenges = (ROOT / "mods" / "theocraft_circus" / "challenges.lua").read_text(
        encoding="utf-8"
    )
    assert "mod.set_music_box(pos, true)" in props
    assert "mod.set_music_box(pos, false)" in props
    assert "mod.set_music_box(p, true)" in challenges
    # No path may touch handles or swap music nodes directly anymore.
    assert "music_handles" not in props
    assert "music_handles" not in challenges
    assert "music_box_on" not in challenges
