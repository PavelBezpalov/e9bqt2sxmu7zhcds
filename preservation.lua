local bxhnz7tp5bge7wvu = bxhnz7tp5bge7wvu_interface
local SB = e3y87ukfgr442ue6
bxhnz7tp5bge7wvu.environment.virtual.exclude_tanks = false

local last_empovered_spell
local last_empovered_spell_last_stage_start
local last_empovered_spell_finish_time

local function is_available(spell)
  return IsSpellKnown(spell, false) or IsPlayerSpell(spell)
end

local function healable(unit)
  return not unit.debuff(329298).any -- Gluttonous Miasma at Hungering Destroyer
end

local function in_same_phase(unit)
  return UnitInPartyShard(unit.unitID)
end

local function healable_lowest_unit(func)
  local lowest_unit_id
  local lowest_health
  local healable_lowest_unit
  for unit in bxhnz7tp5bge7wvu.environment.iterator() do
    if func(unit) then
      if not healable_lowest_unit then
        healable_lowest_unit = unit
      else
        lowest_unit_id, lowest_health = bxhnz7tp5bge7wvu.environment.virtual.resolvers.unit(unit.unitID, healable_lowest_unit.unitID)
        if lowest_unit_id == unit.unitID then
          healable_lowest_unit = unit
        end
      end
    end
  end
  return healable_lowest_unit
end

local function empower_stage()
  local stage = 0
  local name, _, _, startTime, endTime, _, _, _, _, totalStages = UnitChannelInfo('player')
  if totalStages and totalStages > 0 then
    last_empovered_spell = name
    last_empovered_spell_finish_time = (endTime + GetUnitEmpowerHoldAtMaxTime('player')) / 1000
    last_empovered_spell_last_stage_start = endTime / 1000
    stage = 0
    startTime = startTime / 1000  -- Doing this here so we don't divide by 1000 every loop index
    local currentTime = GetTime() -- If you really want to get time each loop, go for it. But the time difference will be miniscule for a single frame loop
    local stageDuration = 0
    for i = 1, totalStages do
      stageDuration = stageDuration + GetUnitEmpowerStageDuration('player', i - 1) / 1000
      if startTime + stageDuration > currentTime then
        break -- Break early so we don't keep checking, we haven't hit this stage yet
      end
      stage = i
    end
  end
  return stage
end

local function on_last_stage()
  local action_allowed = IsUsableSpell(351239) -- Visage
  local channeling = UnitChannelInfo('player')
  return not action_allowed and not channeling and last_empovered_spell_finish_time and last_empovered_spell_last_stage_start and GetTime() > last_empovered_spell_last_stage_start and GetTime() < last_empovered_spell_finish_time
end

local function has_buff_to_steal_or_purge(unit)
  local has_buffs = false
  for i=1,40 do 
    local name,_,_,_,_,_,_,can_steal_or_purge = UnitAura(unit.unitID, i)
    if name and can_steal_or_purge then
      has_buffs = true
      break
    end
  end
  return has_buffs
end

local function gcd()
  if SpellIsTargeting() then return end
end

local function combat()
  if not player.alive then return end

  local lowest_unit = healable_lowest_unit(function(unit)
      return unit.alive and UnitInRange(unit.unitID) and in_same_phase(unit) and healable(unit) and unit.distance <= 30
    end)
  local lowest_unit_without_echo = healable_lowest_unit(function(unit)
      return unit.alive and UnitInRange(unit.unitID) and in_same_phase(unit) and healable(unit) and unit.distance <= 30 and unit.buff(SB.Echo).down
    end)
  local tank_unit = healable_lowest_unit(function(unit)
      return unit.alive and UnitInRange(unit.unitID) and in_same_phase(unit) and healable(unit) and ( UnitGroupRolesAssigned(unit.unitID) == 'TANK' or UnitExists('focus') and not UnitCanAttack('player', 'focus') and not UnitIsDeadOrGhost('focus') ) and unit.distance <= 30
    end)
  local empower_stage = empower_stage()
  local not_moving_or_hover = not player.moving or player.buff(SB.Hover).up

  if castable(SB.RenewingBlaze) and player.health.percent < 50 then
    cast_with_queue(SB.RenewingBlaze)
  end

  if GetItemCooldown(5512) == 0 and player.health.percent < 30 then
    macro('/use Healthstone')
  end

  if castable(SB.ObsidianScales) and player.buff(SB.ObsidianScales).down and player.health.percent < 30 then
    cast_with_queue(SB.ObsidianScales)
  end

  if modifier.lalt and castable(SB.EmeraldCommunion) then
    return cast_with_queue(SB.EmeraldCommunion)
  end

  if modifier.lcontrol and castable(SB.Rewind) then
    return cast_with_queue(SB.Rewind)
  end

  local function attack_target()
    if target.enemy and target.alive and not player.moving then
      auto_attack()

      if toggle('enrage', false) and castable(SB.OppressingRoar) and is_available(SB.Overawe) and has_buff_to_steal_or_purge(target) and target.distance <= 30 then
        return cast_with_queue(SB.OppressingRoar)
      end

      if toggle('interrupts', false) and target.interrupt(70) then
        if castable(SB.Quell) and target.distance <= 25 then
          return cast_with_queue(SB.Quell, target)
        end

        if toggle('racial_interrupts', false) then 
          if castable(SB.TailSwipe) and target.distance <= 8 then
            return cast_with_queue(SB.TailSwipe)
          end

          if castable(SB.WingBuffet) and target.distance <= 15 then
            return cast_with_queue(SB.WingBuffet)
          end
        end
      end

      if toggle('fb', false) and castable(SB.FireBreath) and target.distance <= 25 then
        return cast_with_queue(SB.FireBreath)
      end

      if IsInRaid() and target.castable(SB.Disintegrate) and is_available(SB.EnergyLoop) and player.buff(SB.EssenceBurst).up then
        return cast_with_queue(SB.Disintegrate, target)
      end

      if toggle('lf', false) and target.castable(SB.LivingFlame) then
        return cast_with_queue(SB.LivingFlame, target)
      end
    end
  end

  --
  -- PARTY HEALING
  --

  local function party_healing()
    local party_dreambreath = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_dreambreath', 90)
    local party_echo = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_echo', 95)
    local party_lifebind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_lifebind', 70)
    local party_living_flame = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_living_flame', 70)
    local party_rewind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_rewind', 40)
    local party_spiritbloom = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_spiritbloom', 60)

    if player.channeling() or on_last_stage() then
      if player.spell(SB.Disintegrate).current then return end

      if player.spell(SB.DreamBreath).current and empower_stage >= 1 then
        return cast_while_casting(SB.DreamBreath)
      end

      if (player.spell(SB.Spiritbloom).current or last_empovered_spell == 'Spiritbloom') and 
      ((group.under(party_spiritbloom, 30, false) <= 1 and empower_stage >= 1) or
        (group.under(party_spiritbloom, 30, false) <= 2 and empower_stage >= 2) or
        (group.under(party_spiritbloom, 30, false) > 2 and (empower_stage >= 3 or on_last_stage()))) then
        return cast_while_casting(SB.Spiritbloom)
      end

      if last_empovered_spell == 'Fire Breath' and on_last_stage() then
        return cast_while_casting(SB.FireBreath)
      end

      return
    end

    if castable(SB.Rewind) and group.under(party_rewind, 30, false) >= 4 then
      return cast_with_queue(SB.Rewind)
    end

    if modifier.lshift and not player.moving then
      if castable(SB.TemporalAnomaly) then
        return cast_with_queue(SB.TemporalAnomaly)
      end

      if castable(SB.DreamBreath) then
        if castable(SB.VerdantEmbrace) then
          return cast_with_queue(SB.VerdantEmbrace, player)
        end
        return cast_with_queue(SB.DreamBreath)
      end
    end

    if toggle('cooldowns', false) then
      if player.health.percent <= 30 
      and castable(SB.TimeDilation) then
        cast_with_queue(SB.TimeDilation, player)
      end

      if lowest_unit 
      and lowest_unit.health.percent <= 30 
      and lowest_unit.castable(SB.TimeDilation) then
        cast_with_queue(SB.TimeDilation, lowest_unit)
      end
    end

    local allies_for_lifebind = group.count(function (unit)
        return unit.alive and unit.buff(SB.Echo).up and healable(unit) and in_same_phase(unit) and unit.health.percent < party_lifebind
      end)

    if allies_for_lifebind > 3 then
      if castable(SB.VerdantEmbrace) then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end
      if castable(SB.Reversion) then
        return cast_with_queue(SB.Reversion, player)
      end
    end

    if castable(SB.Spiritbloom) and group.under(party_spiritbloom, 30, false) >= 1 then
      if group.under(party_spiritbloom, 30, false) > 2 then
        if castable(SB.TipTheScales) then
          cast_with_queue(SB.TipTheScales)
        end
        if castable(SB.Stasis) and player.buff(SB.Stasis).down and (not player.moving or player.buff(SB.TipTheScales).up) then
          cast_with_queue(SB.Stasis)
        end
      end
      if not player.moving or player.buff(SB.TipTheScales).up then
        if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.Spiritbloom, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.Spiritbloom, lowest_unit)
      end
    end

    if castable(SB.VerdantEmbrace) then
      if lowest_unit and lowest_unit.health.percent < 70 and lowest_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end

      if player.health.percent < 70 then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end

      if tank_unit and tank_unit.health.percent < 70 and tank_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end
    end

    if castable(SB.EmeraldBlossom) then
      if player.health.percent < 50 and player.buff(SB.Echo).up then
        return cast_with_queue(SB.EmeraldBlossom, player)
      end

      if tank_unit and tank_unit.health.percent < 50 and tank_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.EmeraldBlossom, tank_unit)
      end

      if lowest_unit and lowest_unit.health.percent < 50 and lowest_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.EmeraldBlossom, lowest_unit)
      end

      if group.under(90, 10, false) >= 3 then
        return cast_with_queue(SB.EmeraldBlossom, player)
      end
    end  

    if castable(SB.DreamBreath) and group.under(party_dreambreath, 30, false) >= 3 and not player.moving then
      return cast_with_queue(SB.DreamBreath)
    end

    if castable(SB.Echo) then
      if lowest_unit and lowest_unit.health.percent < 70 and lowest_unit.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, lowest_unit)
      end

      if tank_unit and tank_unit.health.percent < 70 and tank_unit.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, tank_unit)
      end

      if player.health.percent < 70 and player.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, player)
      end
    end

    if not_moving_or_hover and castable(SB.LivingFlame) then
      if player.health.percent < 70 then
        if lowest_unit_without_echo and player.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, player)
      end

      if tank_unit and tank_unit.health.percent < 70 then
        if lowest_unit_without_echo and tank_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, tank_unit)
      end

      if lowest_unit and lowest_unit.health.percent < 70 then
        if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, lowest_unit)
      end
    end

    if toggle('dispell', false) then
      if castable(SB.Naturalize) and player.dispellable(SB.Naturalize) then
        return cast_with_queue(SB.Naturalize, player)
      end

      local unit = group.dispellable(SB.Naturalize)
      if unit and unit.distance <= 30 and castable(SB.Naturalize) then
        return cast_with_queue(SB.Naturalize, unit)
      end

      if castable(SB.CauterizingFlame) and player.dispellable(SB.CauterizingFlame) then
        return cast_with_queue(SB.CauterizingFlame, player)
      end

      unit = group.dispellable(SB.CauterizingFlame)
      if unit and unit.distance <= 30 and castable(SB.CauterizingFlame) then
        return cast_with_queue(SB.CauterizingFlame, unit)
      end
    end

    if target.enemy and target.alive and not player.moving then
      auto_attack()

      if toggle('enrage', false) and castable(SB.OppressingRoar) and is_available(SB.Overawe) and has_buff_to_steal_or_purge(target) and target.distance <= 30 then
        return cast_with_queue(SB.OppressingRoar)
      end

      if toggle('interrupts', false) and target.interrupt(70) then
        if castable(SB.Quell) and target.distance <= 25 then
          return cast_with_queue(SB.Quell, target)
        end

        if toggle('racial_interrupts', false) then 
          if castable(SB.TailSwipe) and target.distance <= 8 then
            return cast_with_queue(SB.TailSwipe)
          end

          if castable(SB.WingBuffet) and target.distance <= 15 then
            return cast_with_queue(SB.WingBuffet)
          end
        end
      end

      if toggle('fb', false) and castable(SB.FireBreath) and target.distance <= 25 then
        return cast_with_queue(SB.FireBreath)
      end
    end

    if castable(SB.Echo) then
      if lowest_unit and lowest_unit.health.percent < party_echo and lowest_unit.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, lowest_unit)
      end

      if tank_unit and tank_unit.health.percent < party_echo and tank_unit.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, tank_unit)
      end

      if player.health.percent < party_echo and player.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, player)
      end
    end

    if not_moving_or_hover and castable(SB.LivingFlame) then
      if player.health.percent < party_living_flame then
        if lowest_unit_without_echo and player.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, player)
      end

      if tank_unit and tank_unit.health.percent < party_living_flame then
        if lowest_unit_without_echo and tank_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, tank_unit)
      end

      if lowest_unit and lowest_unit.health.percent < party_living_flame then
        if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, lowest_unit)
      end
    end

    if tank_unit and tank_unit.castable(SB.Reversion) 
    and tank_unit.buff(SB.Reversion).down then
      return cast_with_queue(SB.Reversion, tank_unit)
    end

    if castable(SB.Reversion) and ( tank_unit and tank_unit.buff(SB.Reversion).up or not tank_unit ) and spell(SB.Reversion).charges == 2 then
      return cast_with_queue(SB.Reversion, player)
    end

    if castable(SB.Echo) and ( player.buff(SB.EssenceBurst).count > 1 or player.power.essence.actual == player.power.essence.max ) and lowest_unit_without_echo then
      return cast_with_queue(SB.Echo, lowest_unit_without_echo)
    end

    if target.enemy and target.alive and not player.moving then
      if toggle('lf', false) and target.castable(SB.LivingFlame) then
        return cast_with_queue(SB.LivingFlame, target)
      end
    end
  end

  --
  -- Hots build
  --

  local function raid_hots_healing()
    local raid_dreambreath = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_dreambreath', 90)
    local raid_echo = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_echo', 90)
    local raid_lifebind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_lifebind', 70)
    local raid_living_flame = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_living_flame', 60)
    local raid_rewind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_rewind', 40)
    local raid_spiritbloom = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_spiritbloom', 60)

    if player.channeling() or on_last_stage() then
      if player.spell(SB.Disintegrate).current then return end

      if player.spell(SB.DreamBreath).current and empower_stage >= 1 then
        return cast_while_casting(SB.DreamBreath)
      end

      if last_empovered_spell == 'Spiritbloom' and on_last_stage() then
        return cast_while_casting(SB.Spiritbloom)
      end

      if last_empovered_spell == 'Fire Breath' and on_last_stage() then
        return cast_while_casting(SB.FireBreath)
      end

      return
    end

    if modifier.lshift and castable(SB.TemporalAnomaly) and not player.moving then
      return cast_with_queue(SB.TemporalAnomaly)
    end

    if castable(SB.Rewind) and group.under(raid_rewind, 40, true) >= 5 then
      return cast_with_queue(SB.Rewind)
    end

    if toggle('cooldowns', false) then
      if player.health.effective <= 30 
      and castable(SB.TimeDilation) then
        cast_with_queue(SB.TimeDilation, player)
      end

      if lowest_unit 
      and lowest_unit.health.effective <= 30 
      and lowest_unit.castable(SB.TimeDilation) then
        cast_with_queue(SB.TimeDilation, lowest_unit)
      end
    end

    local allies_for_lifebind = group.count(function (unit)
        return unit.alive and unit.buff(SB.Echo).up and unit.health.effective < raid_lifebind and healable(unit) and in_same_phase(unit)
      end)

    if castable(SB.VerdantEmbrace) and allies_for_lifebind > 3 then
      return cast_with_queue(SB.VerdantEmbrace, player)
    end

    local allies_with_echo = group.count(function (unit)
        return unit.alive and unit.buff(SB.Echo).up and healable(unit) and in_same_phase(unit)
      end)

    local unit_without_hots = group.match(function (unit)
        return unit.alive and unit.castable(SB.Echo) and healable(unit) and in_same_phase(unit) and unit.buff(SB.Echo).down and unit.buff(SB.Reversion).down and unit.buff(SB.ReversionEchoed).down
      end)

    local unit_without_echo = group.match(function (unit)
        return unit.alive and unit.castable(SB.Echo) and healable(unit) and in_same_phase(unit) and unit.buff(SB.Echo).down
      end)

    if castable(SB.Reversion) and (
      (allies_with_echo > 2 and allies_with_echo < 5 and spell(SB.Reversion).charges == 2) or
      allies_with_echo >= 5) then
      if unit_without_hots then
        return cast_with_queue(SB.Reversion, unit_without_hots)
      else
        return cast_with_queue(SB.Reversion, player)
      end
    end

    if castable(SB.Spiritbloom) and group.under(raid_spiritbloom, 30, true) >= 1 and not player.moving then
      if group.under(raid_spiritbloom, 30, true) > 2 and castable(SB.TipTheScales) then
        cast_with_queue(SB.TipTheScales)
      end
      return cast_with_queue(SB.Spiritbloom, lowest_unit)
    end

    if castable(SB.DreamBreath) and group.under(raid_dreambreath, 30, true) >= 5 and not player.moving then
      if castable(SB.VerdantEmbrace) then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end
      return cast_with_queue(SB.DreamBreath)
    end

    if castable(SB.Echo) then
      if lowest_unit and lowest_unit.health.percent < 70 and lowest_unit.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, lowest_unit)
      end

      if tank_unit and tank_unit.health.percent < 70 and tank_unit.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, tank_unit)
      end

      if player.health.percent < 70 and player.buff(SB.Echo).down then
        return cast_with_queue(SB.Echo, player)
      end
    end

    if not_moving_or_hover and castable(SB.LivingFlame) then
      if player.health.percent < 70 then
        if lowest_unit_without_echo and player.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, player)
      end

      if tank_unit and tank_unit.health.percent < 70 then
        if lowest_unit_without_echo and tank_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, tank_unit)
      end

      if lowest_unit and lowest_unit.health.percent < 70 then
        if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, lowest_unit)
      end
    end

    if toggle('dispell', false) then
      if castable(SB.Naturalize) and player.dispellable(SB.Naturalize) then
        return cast_with_queue(SB.Naturalize, player)
      end

      local unit = group.dispellable(SB.Naturalize)
      if unit and unit.distance <= 30 and castable(SB.Naturalize) then
        return cast_with_queue(SB.Naturalize, unit)
      end

      if castable(SB.CauterizingFlame) and player.dispellable(SB.CauterizingFlame) then
        return cast_with_queue(SB.CauterizingFlame, player)
      end

      unit = group.dispellable(SB.CauterizingFlame)
      if unit and unit.distance <= 30 and castable(SB.CauterizingFlame) then
        return cast_with_queue(SB.CauterizingFlame, unit)
      end
    end

    if target.enemy and target.alive and not player.moving then
      auto_attack()

      if toggle('enrage', false) and castable(SB.OppressingRoar) and is_available(SB.Overawe) and has_buff_to_steal_or_purge(target) and target.distance <= 30 then
        return cast_with_queue(SB.OppressingRoar)
      end

      if toggle('interrupts', false) and target.interrupt(70) then
        if castable(SB.Quell) and target.distance <= 25 then
          return cast_with_queue(SB.Quell, target)
        end

        if toggle('racial_interrupts', false) then 
          if castable(SB.TailSwipe) and target.distance <= 8 then
            return cast_with_queue(SB.TailSwipe)
          end

          if castable(SB.WingBuffet) and target.distance <= 15 then
            return cast_with_queue(SB.WingBuffet)
          end
        end
      end

      if toggle('fb', false) and castable(SB.FireBreath) and target.distance <= 25 then
        return cast_with_queue(SB.FireBreath)
      end
    end

    if castable(SB.Echo) and player.buff(SB.Echo).down and player.buff(SB.Reversion).down and player.buff(SB.ReversionEchoed).down and player.health.effective < raid_echo then
      return cast_with_queue(SB.Echo, player)
    end

    if tank_unit and tank_unit.castable(SB.Echo) and tank_unit.buff(SB.Echo).down and tank_unit.buff(SB.Reversion).down and tank_unit.buff(SB.ReversionEchoed).down and tank_unit.health.effective < raid_echo then
      return cast_with_queue(SB.Echo, tank_unit)
    end

    if lowest_unit and lowest_unit.castable(SB.Echo) and lowest_unit.buff(SB.Echo).down and lowest_unit.buff(SB.Reversion).down and lowest_unit.buff(SB.ReversionEchoed).down and lowest_unit.health.effective < raid_echo then
      return cast_with_queue(SB.Echo, lowest_unit)
    end

    if unit_without_hots and unit_without_hots.health.effective < raid_echo then
      return cast_with_queue(SB.Echo, unit_without_hots)
    end

    if unit_without_echo and unit_without_echo.health.effective < raid_echo then
      return cast_with_queue(SB.Echo, unit_without_echo)
    end

    if not_moving_or_hover and castable(SB.LivingFlame) then
      if player.health.percent < raid_living_flame then
        if lowest_unit_without_echo and player.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, player)
      end

      if tank_unit and tank_unit.health.percent < raid_living_flame then
        if lowest_unit_without_echo and tank_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, tank_unit)
      end

      if lowest_unit and lowest_unit.health.percent < raid_living_flame then
        if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
          return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
        end
        return cast_with_queue(SB.LivingFlame, lowest_unit)
      end
    end

    if tank_unit and tank_unit.castable(SB.Reversion) 
    and tank_unit.buff(SB.Reversion).down then
      return cast_with_queue(SB.Reversion, tank_unit)
    end

    if castable(SB.Reversion) and ( tank_unit and tank_unit.buff(SB.Reversion).up or not tank_unit ) and spell(SB.Reversion).charges == 2 then
      return cast_with_queue(SB.Reversion, player)
    end

    if castable(SB.Echo) and ( player.buff(SB.EssenceBurst).count > 1 or player.power.essence.actual == player.power.essence.max ) and lowest_unit_without_echo then
      return cast_with_queue(SB.Echo, lowest_unit_without_echo)
    end

    if target.enemy and target.alive and not player.moving then
      if toggle('lf', false) and target.castable(SB.LivingFlame) then
        return cast_with_queue(SB.LivingFlame, target)
      end
    end
  end

  --
  -- Blossom build
  --

  local function raid_blossom_healing()
    local raid_dreambreath = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_dreambreath', 90)
    local raid_echo = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_echo', 90)
    local raid_lifebind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_lifebind', 70)
    local raid_living_flame = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_living_flame', 60)
    local raid_rewind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_rewind', 40)
    local raid_spiritbloom = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_raid_spiritbloom', 60)

    if player.channeling() or on_last_stage() then
      if player.spell(SB.Disintegrate).current then return end

      if player.spell(SB.DreamBreath).current and empower_stage >= 1 then
        return cast_while_casting(SB.DreamBreath)
      end

      if last_empovered_spell == 'Spiritbloom' and on_last_stage() then
        return cast_while_casting(SB.Spiritbloom)
      end

      if last_empovered_spell == 'Fire Breath' and on_last_stage() then
        return cast_while_casting(SB.FireBreath)
      end

      return
    end

    if modifier.lshift and castable(SB.TemporalAnomaly) and not player.moving then
      return cast_with_queue(SB.TemporalAnomaly)
    end

    if castable(SB.Rewind) and group.under(raid_rewind, 40, true) >= 5 then
      return cast_with_queue(SB.Rewind)
    end

    if toggle('cooldowns', false) then
      if player.health.effective <= 30 
      and castable(SB.TimeDilation) then
        cast_with_queue(SB.TimeDilation, player)
      end

      if lowest_unit 
      and lowest_unit.health.effective <= 30 
      and lowest_unit.castable(SB.TimeDilation) then
        cast_with_queue(SB.TimeDilation, lowest_unit)
      end
    end

    local allies_for_lifebind = group.count(function (unit)
        return unit.alive and unit.buff(SB.Echo).up and healable(unit) and in_same_phase(unit)
      end)

    if allies_for_lifebind > 3 then
      if castable(SB.VerdantEmbrace) then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end
      if castable(SB.Reversion) then
        return cast_with_queue(SB.Reversion, player)
      end
    end

    if castable(SB.EmeraldBlossom) and (group.under(90, 10, true) >= 5 or player.buff(SB.EssenceBurst).up and group.under(90, 10, true) >= 3) then
      return cast_with_queue(SB.EmeraldBlossom, player)
    end

    if castable(SB.Spiritbloom) and group.under(raid_spiritbloom, 30, true) >= 1 and not player.moving then
      if group.under(raid_spiritbloom, 30, true) > 2 and castable(SB.TipTheScales) then
        cast_with_queue(SB.TipTheScales)
      end
      return cast_with_queue(SB.Spiritbloom, lowest_unit)
    end

    if castable(SB.DreamBreath) and group.under(raid_dreambreath, 30, true) >= 5 and not player.moving then
      if castable(SB.VerdantEmbrace) then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end
      return cast_with_queue(SB.DreamBreath)
    end

    if toggle('dispell', false) then
      if castable(SB.Naturalize) and player.dispellable(SB.Naturalize) then
        return cast_with_queue(SB.Naturalize, player)
      end

      local unit = group.dispellable(SB.Naturalize)
      if unit and unit.distance <= 30 and castable(SB.Naturalize) then
        return cast_with_queue(SB.Naturalize, unit)
      end

      if castable(SB.CauterizingFlame) and player.dispellable(SB.CauterizingFlame) then
        return cast_with_queue(SB.CauterizingFlame, player)
      end

      unit = group.dispellable(SB.CauterizingFlame)
      if unit and unit.distance <= 30 and castable(SB.CauterizingFlame) then
        return cast_with_queue(SB.CauterizingFlame, unit)
      end
    end

    --if tank_unit and tank_unit.castable(SB.Reversion) 
    --  and tank_unit.buff(SB.Reversion).down then
    --  return cast_with_queue(SB.Reversion, tank_unit)
    --end

    if not player.moving then
      if player.health.effective < raid_living_flame and castable(SB.LivingFlame) then
        return cast_with_queue(SB.LivingFlame, player)
      end

      if tank_unit and tank_unit.health.effective < raid_living_flame and tank_unit.castable(SB.LivingFlame) then
        return cast_with_queue(SB.LivingFlame, tank_unit)
      end

      if lowest_unit and lowest_unit.health.effective < raid_living_flame and lowest_unit.castable(SB.LivingFlame) then
        return cast_with_queue(SB.LivingFlame, lowest_unit)
      end
    end

    return attack_target()
  end

  --
  -- SWITCH
  --

  if IsInRaid() then
    if toggle('blossom', false) then
      return raid_blossom_healing()
    else
      return raid_hots_healing()
    end
  else
    return party_healing()
  end
end

function resting()
  if not player.alive then return end

  if not toggle('rest', false) then return end

  local lowest_unit = healable_lowest_unit(function(unit)
      return unit.alive and UnitInRange(unit.unitID) and in_same_phase(unit) and healable(unit) and unit.distance <= 30
    end)
  local lowest_unit_without_echo = healable_lowest_unit(function(unit)
      return unit.alive and UnitInRange(unit.unitID) and in_same_phase(unit) and healable(unit) and unit.distance <= 30 and unit.buff(SB.Echo).down
    end)
  local tank_unit = healable_lowest_unit(function(unit)
      return unit.alive and UnitInRange(unit.unitID) and in_same_phase(unit) and healable(unit) and ( UnitGroupRolesAssigned(unit.unitID) == 'TANK' or UnitExists('focus') and not UnitCanAttack('player', 'focus') and not UnitIsDeadOrGhost('focus') ) and unit.distance <= 30
    end)
  local empower_stage = empower_stage()
  local not_moving_or_hover = not player.moving or player.buff(SB.Hover).up

  if castable(SB.RenewingBlaze) and player.health.percent < 50 then
    cast_with_queue(SB.RenewingBlaze)
  end

  if GetItemCooldown(5512) == 0 and player.health.percent < 30 then
    macro('/use Healthstone')
  end

  if castable(SB.ObsidianScales) and player.buff(SB.ObsidianScales).down and player.health.percent < 30 then
    cast_with_queue(SB.ObsidianScales)
  end

  local party_dreambreath = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_dreambreath', 90)
  local party_echo = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_echo', 95)
  local party_lifebind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_lifebind', 70)
  local party_living_flame = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_living_flame', 70)
  local party_rewind = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_rewind', 40)
  local party_spiritbloom = bxhnz7tp5bge7wvu.settings.fetch('pre_nikopol_party_spiritbloom', 60)

  if player.channeling() or on_last_stage() then
    if player.spell(SB.Disintegrate).current then return end

    if player.spell(SB.DreamBreath).current and empower_stage >= 1 then
      return cast_while_casting(SB.DreamBreath)
    end

    if (player.spell(SB.Spiritbloom).current or last_empovered_spell == 'Spiritbloom') and 
    ((group.under(party_spiritbloom, 30, false) <= 1 and empower_stage >= 1) or
      (group.under(party_spiritbloom, 30, false) <= 2 and empower_stage >= 2) or
      (group.under(party_spiritbloom, 30, false) > 2 and (empower_stage >= 3 or on_last_stage()))) then
      return cast_while_casting(SB.Spiritbloom)
    end

    if last_empovered_spell == 'Fire Breath' and on_last_stage() then
      return cast_while_casting(SB.FireBreath)
    end

    return
  end

  if castable(SB.Rewind) and group.under(party_rewind, 30, false) >= 4 then
    return cast_with_queue(SB.Rewind)
  end

  if modifier.lshift and not player.moving then
    if castable(SB.TemporalAnomaly) then
      return cast_with_queue(SB.TemporalAnomaly)
    end

    if castable(SB.DreamBreath) then
      if castable(SB.VerdantEmbrace) then
        return cast_with_queue(SB.VerdantEmbrace, player)
      end
      return cast_with_queue(SB.DreamBreath)
    end
  end

  if toggle('cooldowns', false) then
    if player.health.percent <= 30 
    and castable(SB.TimeDilation) then
      cast_with_queue(SB.TimeDilation, player)
    end

    if lowest_unit 
    and lowest_unit.health.percent <= 30 
    and lowest_unit.castable(SB.TimeDilation) then
      cast_with_queue(SB.TimeDilation, lowest_unit)
    end
  end

  local allies_for_lifebind = group.count(function (unit)
      return unit.alive and unit.buff(SB.Echo).up and healable(unit) and in_same_phase(unit) and unit.health.percent < party_lifebind
    end)

  if allies_for_lifebind > 3 then
    if castable(SB.VerdantEmbrace) then
      return cast_with_queue(SB.VerdantEmbrace, player)
    end
    if castable(SB.Reversion) then
      return cast_with_queue(SB.Reversion, player)
    end
  end

  if castable(SB.Spiritbloom) and group.under(party_spiritbloom, 30, false) >= 1 then
    if group.under(party_spiritbloom, 30, false) > 2 then
      if castable(SB.TipTheScales) then
        cast_with_queue(SB.TipTheScales)
      end
      if castable(SB.Stasis) and player.buff(SB.Stasis).down and (not player.moving or player.buff(SB.TipTheScales).up) then
        cast_with_queue(SB.Stasis)
      end
    end
    if not player.moving or player.buff(SB.TipTheScales).up then
      if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.Spiritbloom, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.Spiritbloom, lowest_unit)
    end
  end

  if castable(SB.VerdantEmbrace) then
    if lowest_unit and lowest_unit.health.percent < 70 and lowest_unit.buff(SB.Echo).up then
      return cast_with_queue(SB.VerdantEmbrace, player)
    end

    if player.health.percent < 70 then
      return cast_with_queue(SB.VerdantEmbrace, player)
    end

    if tank_unit and tank_unit.health.percent < 70 and tank_unit.buff(SB.Echo).up then
      return cast_with_queue(SB.VerdantEmbrace, player)
    end
  end

  if castable(SB.EmeraldBlossom) then
    if player.health.percent < 50 and player.buff(SB.Echo).up then
      return cast_with_queue(SB.EmeraldBlossom, player)
    end

    if tank_unit and tank_unit.health.percent < 50 and tank_unit.buff(SB.Echo).up then
      return cast_with_queue(SB.EmeraldBlossom, tank_unit)
    end

    if lowest_unit and lowest_unit.health.percent < 50 and lowest_unit.buff(SB.Echo).up then
      return cast_with_queue(SB.EmeraldBlossom, lowest_unit)
    end

    if group.under(90, 10, false) >= 3 then
      return cast_with_queue(SB.EmeraldBlossom, player)
    end
  end  

  if castable(SB.DreamBreath) and group.under(party_dreambreath, 30, false) >= 3 and not player.moving then
    return cast_with_queue(SB.DreamBreath)
  end

  if castable(SB.Echo) then
    if lowest_unit and lowest_unit.health.percent < 70 and lowest_unit.buff(SB.Echo).down then
      return cast_with_queue(SB.Echo, lowest_unit)
    end

    if tank_unit and tank_unit.health.percent < 70 and tank_unit.buff(SB.Echo).down then
      return cast_with_queue(SB.Echo, tank_unit)
    end

    if player.health.percent < 70 and player.buff(SB.Echo).down then
      return cast_with_queue(SB.Echo, player)
    end
  end

  if not_moving_or_hover and castable(SB.LivingFlame) then
    if player.health.percent < 70 then
      if lowest_unit_without_echo and player.buff(SB.Echo).up then
        return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.LivingFlame, player)
    end

    if tank_unit and tank_unit.health.percent < 70 then
      if lowest_unit_without_echo and tank_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.LivingFlame, tank_unit)
    end

    if lowest_unit and lowest_unit.health.percent < 70 then
      if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.LivingFlame, lowest_unit)
    end
  end

  if toggle('dispell', false) then
    if castable(SB.Naturalize) and player.dispellable(SB.Naturalize) then
      return cast_with_queue(SB.Naturalize, player)
    end

    local unit = group.dispellable(SB.Naturalize)
    if unit and unit.distance <= 30 and castable(SB.Naturalize) then
      return cast_with_queue(SB.Naturalize, unit)
    end

    if castable(SB.CauterizingFlame) and player.dispellable(SB.CauterizingFlame) then
      return cast_with_queue(SB.CauterizingFlame, player)
    end

    unit = group.dispellable(SB.CauterizingFlame)
    if unit and unit.distance <= 30 and castable(SB.CauterizingFlame) then
      return cast_with_queue(SB.CauterizingFlame, unit)
    end
  end

  if castable(SB.Echo) then
    if lowest_unit and lowest_unit.health.percent < party_echo and lowest_unit.buff(SB.Echo).down then
      return cast_with_queue(SB.Echo, lowest_unit)
    end

    if tank_unit and tank_unit.health.percent < party_echo and tank_unit.buff(SB.Echo).down then
      return cast_with_queue(SB.Echo, tank_unit)
    end

    if player.health.percent < party_echo and player.buff(SB.Echo).down then
      return cast_with_queue(SB.Echo, player)
    end
  end

  if not_moving_or_hover and castable(SB.LivingFlame) then
    if player.health.percent < party_living_flame then
      if lowest_unit_without_echo and player.buff(SB.Echo).up then
        return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.LivingFlame, player)
    end

    if tank_unit and tank_unit.health.percent < party_living_flame then
      if lowest_unit_without_echo and tank_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.LivingFlame, tank_unit)
    end

    if lowest_unit and lowest_unit.health.percent < party_living_flame then
      if lowest_unit_without_echo and lowest_unit.buff(SB.Echo).up then
        return cast_with_queue(SB.LivingFlame, lowest_unit_without_echo)
      end
      return cast_with_queue(SB.LivingFlame, lowest_unit)
    end
  end

  if tank_unit and tank_unit.castable(SB.Reversion) 
  and tank_unit.buff(SB.Reversion).down then
    return cast_with_queue(SB.Reversion, tank_unit)
  end

  if castable(SB.Reversion) and ( tank_unit and tank_unit.buff(SB.Reversion).up or not tank_unit ) and spell(SB.Reversion).charges == 2 then
    return cast_with_queue(SB.Reversion, player)
  end

  if castable(SB.Echo) and ( player.buff(SB.EssenceBurst).count > 1 or player.power.essence.actual == player.power.essence.max ) and lowest_unit_without_echo then
    return cast_with_queue(SB.Echo, lowest_unit_without_echo)
  end
end

local function interface()
  local preservation_gui = {
    key = 'pre_nikopol',
    title = 'Preservation',
    width = 250,
    height = 320,
    resize = true,
    show = false,
    template = {
      { type = 'header', text = 'preservation Settings' },
      { type = 'rule' },   
      { type = 'text', text = 'Healing Settings' },
      { key = 'cosmic_healing_potion', type = 'checkbox', text = 'Cosmic Healing Potion', desc = 'Use Cosmic Healing Potion when below 10% health', default = false },
      { type = 'header', text = 'Trinkets' },
      { key = 'trinket_13', type = 'checkbox', text = '13', desc = 'use first trinket', default = false },
      { key = 'trinket_14', type = 'checkbox', text = '14', desc = 'use second trinket', default = false },
      { type = 'header', text = 'Party' },
      { key = 'party_dreambreath', type = 'spinner', text = 'DreamBreath', desc = 'Cast DreamBreath on target below % health', min = 50, max = 100, step = 1, default = 90 },
      { key = 'party_echo', type = 'spinner', text = 'Echo', desc = 'Cast Echo on target below % health', min = 50, max = 100, step = 1, default = 95 },
      { key = 'party_lifebind', type = 'spinner', text = 'Lifebind', desc = 'Cast Lifebind on target below % health', min = 50, max = 100, step = 1, default = 70 },
      { key = 'party_living_flame', type = 'spinner', text = 'Living Flame', desc = 'Cast Living Flame on target below % health', min = 50, max = 100, step = 1, default = 60 },
      { key = 'party_rewind', type = 'spinner', text = 'Rewind', desc = 'Cast Rewind on target below % health', min = 20, max = 100, step = 1, default = 40 },
      { key = 'party_spiritbloom', type = 'spinner', text = 'Spiritbloom', desc = 'Cast Spiritbloom on target below % health', min = 40, max = 100, step = 1, default = 60 },
      { type = 'header', text = 'Raid' },
      { key = 'raid_dreambreath', type = 'spinner', text = 'DreamBreath', desc = 'Cast DreamBreath on target below % health', min = 50, max = 100, step = 1, default = 90 },
      { key = 'raid_echo', type = 'spinner', text = 'Echo', desc = 'Cast Echo on target below % health', min = 50, max = 100, step = 1, default = 90 },
      { key = 'raid_lifebind', type = 'spinner', text = 'Lifebind', desc = 'Cast Lifebind on target below % health', min = 50, max = 100, step = 1, default = 70 },
      { key = 'raid_living_flame', type = 'spinner', text = 'Living Flame', desc = 'Cast Living Flame on target below % health', min = 50, max = 100, step = 1, default = 60 },
      { key = 'raid_rewind', type = 'spinner', text = 'Rewind', desc = 'Cast Rewind on target below % health', min = 20, max = 100, step = 1, default = 40 },
      { key = 'raid_spiritbloom', type = 'spinner', text = 'Spiritbloom', desc = 'Cast Spiritbloom on target below % health', min = 40, max = 100, step = 1, default = 60 },
    }
  }

  configWindow = bxhnz7tp5bge7wvu.interface.builder.buildGUI(preservation_gui)

  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'racial_interrupts',
      label = 'Racial Interrupts',
      on = {
        label = 'RI',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'ri',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'rest',
      label = 'Resting',
      on = {
        label = 'REST',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'rest',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'fb',
      label = 'FB',
      on = {
        label = 'FB',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'fb',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'lf',
      label = 'LF',
      on = {
        label = 'LF',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'lf',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'dispell',
      label = 'Auto Dispell',
      on = {
        label = 'DSP',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'dsp',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'enrage',
      label = 'Auto Remove Enrage',
      on = {
        label = 'ENRG',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'enrg',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'blossom',
      label = 'Blossom build',
      on = {
        label = 'BLSM',
        color = bxhnz7tp5bge7wvu.interface.color.green,
        color2 = bxhnz7tp5bge7wvu.interface.color.green
      },
      off = {
        label = 'blsm',
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      }
    })
  bxhnz7tp5bge7wvu.interface.buttons.add_toggle({
      name = 'settings',
      label = 'Rotation Settings',
      font = 'bxhnz7tp5bge7wvu_icon',
      on = {
        label = bxhnz7tp5bge7wvu.interface.icon('cog'),
        color = bxhnz7tp5bge7wvu.interface.color.cyan,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_cyan
      },
      off = {
        label = bxhnz7tp5bge7wvu.interface.icon('cog'),
        color = bxhnz7tp5bge7wvu.interface.color.grey,
        color2 = bxhnz7tp5bge7wvu.interface.color.dark_grey
      },
      callback = function(self)
        if configWindow.parent:IsShown() then
          configWindow.parent:Hide()
        else
          configWindow.parent:Show()
        end
      end
    })
end

bxhnz7tp5bge7wvu.rotation.register({
    spec = bxhnz7tp5bge7wvu.rotation.classes.evoker.preservation,
    name = 'pre_nikopol',
    label = 'Preservation by Nikopol',
    gcd = gcd,
    combat = combat,
    resting = resting,
    interface = interface
  })
