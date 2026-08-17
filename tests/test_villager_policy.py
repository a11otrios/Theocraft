from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "mods" / "theocraft_villagers" / "policy.lua"
LLM = ROOT / "mods" / "theocraft_villagers" / "llm.lua"


def policy_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("theocraft_villagers = {}")
    lua.execute(POLICY.read_text(encoding="utf-8"))
    return lua, lua.globals().theocraft_villagers


def test_offline_interpreter_handles_basic_instructions() -> None:
    lua, mod = policy_runtime()
    identity = lua.table_from({"name": "Ada"})

    assert mod.offline_response("Please follow me", identity).action.type == "follow"
    assert mod.offline_response("Wait here", identity).action.type == "stay"
    assert mod.offline_response("Come over here", identity).action.type == "come"

    gather = mod.offline_response("Gather 99 logs", identity).action
    assert gather.type == "gather"
    assert gather.resource == "wood"
    assert gather.count == 8


def test_action_policy_rejects_arbitrary_world_actions() -> None:
    lua, mod = policy_runtime()
    malicious = lua.table_from(
        {"type": "run_server_command", "args": lua.table_from({"command": "/grantme all"})}
    )
    assert mod.normalise_action(malicious).type == "none"

    unknown_resource = lua.table_from({"type": "gather", "resource": "diamond"})
    assert mod.normalise_action(unknown_resource).type == "none"


def test_history_is_separate_per_villager_and_restored_from_world_storage() -> None:
    lua, mod = policy_runtime()
    lua.execute(
        """
        local values = {}
        minetest = {
          request_http_api = function() return nil end,
          settings = {
            get = function() return nil end,
            get_bool = function() return false end,
          },
          sha1 = function(value) return value end,
          get_mod_storage = function()
            return {
              get_string = function(_, key) return values[key] or "" end,
              set_string = function(_, key, value) values[key] = value end,
            }
          end,
          write_json = function(value) return value end,
          parse_json = function(value) return value end,
        }
        theocraft_villagers.storage = minetest.get_mod_storage()
        theocraft_villagers.histories = {}
        theocraft_villagers.identity_snapshot = function(self)
          return {id = self._id, name = self._theocraft_name, bio = "bio"}
        end
        """
    )
    lua.execute(LLM.read_text(encoding="utf-8"))

    player = lua.eval(
        "{get_player_name=function() return 'player' end, get_pos=function() return {x=0,y=0,z=0} end}"
    )
    ada = lua.table_from({"_id": "villager-a", "_theocraft_name": "Ada"})
    bram = lua.table_from({"_id": "villager-b", "_theocraft_name": "Bram"})
    callback = lua.eval("function() end")

    mod.ask_villager(ada, player, "Follow me", callback)
    assert len(mod.get_history(ada, "player")) == 2
    assert len(mod.get_history(bram, "player")) == 0

    mod.histories = lua.table()
    restored = mod.get_history(ada, "player")
    assert len(restored) == 2
    assert restored[1].content == "Follow me"
    assert restored[2].role == "villager"
