from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
INTEGRATION = ROOT / "mods" / "theocraft_villagers" / "integration.lua"


def test_invincibility_guards_punch_and_other_damage_paths() -> None:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        invincible = true
        definition = {
          on_rightclick = function() end,
          on_spawn = function() end,
          do_custom = function() end,
          on_punch = function(self) self.punches = self.punches + 1 end,
          deal_damage = function(self) self.direct_damage = self.direct_damage + 1 end,
          damage_mob = function(self) self.mob_damage = self.mob_damage + 1 end,
        }
        minetest = {
          registered_entities = { ["mobs_mc:villager"] = definition },
          settings = {
            get_bool = function(_, name, default)
              if name == "theocraft_villagers_invincible" then return invincible end
              return default
            end,
          },
        }
        theocraft_villagers = {}
        """
    )
    lua.execute(INTEGRATION.read_text(encoding="utf-8"))
    lua.execute(
        """
        villager = { punches = 0, direct_damage = 0, mob_damage = 0 }
        definition.on_punch(villager)
        definition.deal_damage(villager)
        definition.damage_mob(villager)
        assert(villager.punches == 0)
        assert(villager.direct_damage == 0)
        assert(villager.mob_damage == 0)

        invincible = false
        definition.on_punch(villager)
        definition.deal_damage(villager)
        definition.damage_mob(villager)
        assert(villager.punches == 1)
        assert(villager.direct_damage == 1)
        assert(villager.mob_damage == 1)
        """
    )
