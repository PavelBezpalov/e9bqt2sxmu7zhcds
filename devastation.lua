local bxhnz7tp5bge7wvu = bxhnz7tp5bge7wvu_interface
local SB = e3y87ukfgr442ue6
local IT = e3y87ukfgr442ue7
local last_empovered_spell
local last_empovered_spell_last_stage_start
local last_empovered_spell_finish_time
local kharnalex_ready = false
local empower_to_stage = 0
local spell_before_disintegrate_ready = 0
--actions.precombat+=/variable,name=dr_prep_time_aoe,default=4,op=reset
local dr_prep_time_aoe = 4
--actions.precombat+=/variable,name=dr_prep_time_st,default=13,op=reset
local dr_prep_time_st = 13

local bloodlust_buffs = {     
  2825, -- Shaman: Bloodlust (Horde)
  32182, -- Shaman: Heroism (Alliance)
  80353, -- Mage:Time Warp
  90355, -- Hunter: Ancient Hysteria
  160452, -- Hunter: Netherwinds
  264667, -- Hunter: Primal Rage
  390386, -- Evoker: Fury of the Aspects
  -- Drums
  35475, -- Drums of War (Cata)
  35476, -- Drums of Battle (Cata)
  146555, -- Drums of Rage (MoP)
  178207, -- Drums of Fury (WoD)
  230935, -- Drums of the Mountain (Legion)
  256740, -- Drums of the Maelstrom (BfA)
  309658, -- Drums of Deathly Ferocity (SL)
  381301 -- Feral Hide Drums (DF) 
}

local function has_bloodlust(unit)
  for i = 1, #bloodlust_buffs do
    if unit.buff(bloodlust_buffs[i]).up then return true end
  end
  return false
end

local function in_same_phase(unit)
  return UnitInPartyShard(unit.unitID)
end

local function disintegrate_ticks()
  local spell, _, _, startTimeMS, endTimeMS, _, _, spellId = UnitChannelInfo("player")
  if not spell or not spellId == SB.Disintegrate then
    return 0
  end
  local channel = endTimeMS/1000 - startTimeMS/1000
  local tickcount = 3
  if channel > 2.4 then
    tickcount = 4
  end
  local tick_duration = channel / tickcount
  return (GetTime() - startTimeMS/1000) / tick_duration
end

local function on_last_disintegrate_tick()
  local spell, _, _, startTimeMS, endTimeMS, _, _, spellId = UnitChannelInfo("player")
  if not spell or not spellId == SB.Disintegrate then
    return false
  end
  local channel = endTimeMS/1000 - startTimeMS/1000
  local tickcount = 3
  if channel > 2.4 then
    tickcount = 4
  end
  local tick_duration = channel / tickcount
  local current_tick = (GetTime() - startTimeMS/1000) / tick_duration
  return (tickcount - current_tick) < 1
end

local function num(val)
  if val then return 1 else return 0 end
end

local function haste_mod()
  local haste = UnitSpellHaste("player")
  return 1 + haste / 100
end

local function gcd_duration()
  return 1.5 / haste_mod()
end

local function is_available(spell)
  return IsSpellKnown(spell, false) or IsPlayerSpell(spell)
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

local function equipted_item(item_id, slot_id)
  local equipted_item_id = GetInventoryItemID("player", slot_id)
  return equipted_item_id == item_id
end

local function equipted_item_ready(item_id, slot_id)
  local start, duration, enable = GetInventoryItemCooldown("player", slot_id)
  return enable == 1 and start == 0 and equipted_item(item_id, slot_id)
end

local function kharnalex_overlay()
  if kharnalex_ready then
    SetCVar("spellActivationOverlayOpacity", 1)
    SpellActivationOverlay_ShowOverlay(SpellActivationOverlayFrame, IT.KharnalexTheFirstLight, 1028137, "TOP", 1, 255, 255, 255, false, false)
  else
    SetCVar("spellActivationOverlayOpacity", 0)
    SpellActivationOverlay_HideOverlays(SpellActivationOverlayFrame, IT.KharnalexTheFirstLight)
  end
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
  kharnalex_overlay()

  if SpellIsTargeting() then return end
end

local function combat()
  if not player.alive then return end
  if SpellIsTargeting() then return end

  kharnalex_overlay()
  kharnalex_ready = false
  local use_clipping = bxhnz7tp5bge7wvu.settings.fetch('ev_nikopol_use_clipping', true)
  local use_early_chaining = bxhnz7tp5bge7wvu.settings.fetch('ev_nikopol_use_early_chaining', true)
  local healing_potion = bxhnz7tp5bge7wvu.settings.fetch('ev_nikopol_healing_potion', false)
  local trinket_13 = bxhnz7tp5bge7wvu.settings.fetch('ev_nikopol_trinket_13', false)
  local trinket_14 = bxhnz7tp5bge7wvu.settings.fetch('ev_nikopol_trinket_14', false)
  local main_hand = bxhnz7tp5bge7wvu.settings.fetch('ev_nikopol_main_hand', false)
  local active_enemies = enemies.count(function (unit)
      return unit.alive and unit.distance >= target.distance - 5 and unit.distance <= target.distance + 5
    end)
  local gcd_max = gcd_duration()
--  actions.precombat+=/variable,name=r1_cast_time,value=1.0*spell_haste
  local r1_cast_time = 1.0 * haste_mod()
  local buff_essence_burst_max_stack = is_available(SB.EssenceAttunement) and 2 or 1
  local buff_dragonrage_up = player.buff(SB.Dragonrage).up
  local buff_essence_burst_stack = player.buff(SB.EssenceBurstBuff).count
  local buff_dragonrage_remains = player.buff(SB.Dragonrage).remains
  local cooldown_dragonrage_remains = spell(SB.Dragonrage).cooldown_without_gcd
  local empower_stage = empower_stage()
  local talent_blast_furnace_rank = 1
  local spell_haste = haste_mod()
--  actions+=/variable,name=next_dragonrage,value=cooldown.dragonrage.remains<?(cooldown.eternity_surge.remains-2*gcd.max)<?(cooldown.fire_breath.remains-gcd.max)
  local next_dragonrage = math.max(spell(SB.Dragonrage).cooldown_without_gcd, (spell(SB.FireBreath).cooldown_without_gcd - 2 * gcd_max), (spell(SB.EternitySurge).cooldown_without_gcd - gcd_max))
  local start_main_hand, _, enable_main_hand = GetInventoryItemCooldown("player", 16)
  local main_hand_ready = main_hand and enable_main_hand == 1 and start_main_hand == 0
  local not_moving_or_hover = not player.moving or player.buff(SB.Hover).up
  local not_moving_or_hover_or_burnout_up = not_moving_or_hover or player.buff(SB.BurnoutBuff).up
  local disintegrate_ticks = disintegrate_ticks()
  local channeling_disintegrate = player.spell(SB.Disintegrate).current
  local on_last_disintegrate_tick = on_last_disintegrate_tick()
  local debuff_in_firestorm_up = false

  if GetCVar("nameplateShowEnemies") == '0' then
    SetCVar("nameplateShowEnemies", 1)
  end
  
  -- iridal cast
  if player.spell(419278).current then return end
  -- Nymue's Unraveling Spindle
  if player.spell(422956).current then return end

  if castable(SB.VerdantEmbrace) and player.health.effective < 40 then
    return cast_with_queue(SB.VerdantEmbrace, player)
  end

  if castable(SB.LivingFlame) and player.buff(SB.BurnoutBuff).up and player.health.effective < 40 then
    return cast_with_queue(SB.LivingFlame, player)
  end

  if castable(SB.EmeraldBlossom) and player.health.effective < 40 then
    return cast_with_queue(SB.EmeraldBlossom, player)
  end

  if castable(SB.ObsidianScales) and player.buff(SB.ObsidianScales).down and player.health.effective < 30 then
    cast_with_queue(SB.ObsidianScales)
  end

  if GetItemCooldown(5512) == 0 and player.health.effective < 30 then
    macro('/use Healthstone')
  end

  if healing_potion and GetItemCooldown(191380) == 0 and player.health.effective < 10 then
    macro('/use Refreshing Healing Potion')
  end
  
  if modifier.lcontrol and castable(SB.WingBuffet) then
    return cast_with_queue(SB.WingBuffet)
  end
  
  if modifier.lshift and castable(SB.TailSwipe) then
    return cast_with_queue(SB.TailSwipe)
  end

  if player.channeling() or on_last_stage() then
    -- bursting affix
    if target.enemy and target.alive and target.health.percent < 50 and player.debuff(SB.Burst).count >= 2 then
      return macro('/stopcasting')
    end

    if player.spell(IT.LightofCreation).current then return end

    -- bursting affix check on stage 1
    if player.spell(SB.FireBreath).current and empower_stage > 0 and (empower_stage == empower_to_stage or player.debuff(SB.Burst).count >= 2) or last_empovered_spell == 'Fire Breath' and on_last_stage() then
      return cast_while_casting(SB.FireBreath)
    end

    -- bursting affix check on stage 1
    if player.spell(SB.EternitySurge).current and empower_stage > 0 and (empower_stage == empower_to_stage or player.debuff(SB.Burst).count >= 2) or last_empovered_spell == 'Eternity Surge' and on_last_stage() then
      return cast_while_casting(SB.EternitySurge)
    end

    if player.spell(SB.FireBreath).current then return end
    if player.spell(SB.EternitySurge).current then return end
  end
  
  empower_to_stage = 0
  
  if toggle('dispell', false) then
    if castable(SB.Expunge) and player.dispellable(SB.Expunge) then
      return cast_with_queue(SB.Expunge, player)
    end

    local unit = group.dispellable(SB.Expunge)
    if unit and in_same_phase(unit) and unit.distance < 25 and castable(SB.Expunge) then
      return cast_with_queue(SB.Expunge, unit)
    end

    if castable(SB.CauterizingFlame) and player.dispellable(SB.CauterizingFlame) then
      return cast_with_queue(SB.CauterizingFlame, player)
    end

    unit = group.dispellable(SB.CauterizingFlame)
    if unit and in_same_phase(unit) and unit.distance < 25 and castable(SB.CauterizingFlame) then
      return cast_with_queue(SB.CauterizingFlame, unit)
    end
  end

  local function fb()
--    actions.fb=fire_breath,empower_to=1,target_if=max:target.health.pct,if=(buff.dragonrage.up&active_enemies<=2)|(active_enemies=1&!talent.everburning_flame)|(buff.dragonrage.remains<1.75*spell_haste&buff.dragonrage.remains>=1*spell_haste)
    if ( buff_dragonrage_up and active_enemies <= 2 ) or ( active_enemies == 1 and not is_available(SB.EverburningFlame) ) or ( buff_dragonrage_remains < 1.75 * spell_haste and buff_dragonrage_remains >= 1 * spell_haste ) then
      empower_to_stage = 1

--      actions.fb+=/fire_breath,empower_to=2,target_if=max:target.health.pct,if=(!debuff.in_firestorm.up&talent.everburning_flame&active_enemies<=3)|(active_enemies=2&!talent.everburning_flame)|(buff.dragonrage.remains<2.5*spell_haste&buff.dragonrage.remains>=1.75*spell_haste)
    elseif ( not debuff_in_firestorm_up and is_available(SB.EverburningFlame) and active_enemies <= 3 ) or ( active_enemies == 2 and not is_available(SB.EverburningFlame) ) or ( buff_dragonrage_remains < 2.5 * spell_haste and buff_dragonrage_remains >= 1.75 * spell_haste ) then
      empower_to_stage = 2

--      actions.fb+=/fire_breath,empower_to=3,target_if=max:target.health.pct,if=(talent.everburning_flame&buff.dragonrage.up&active_enemies>=5)|!talent.font_of_magic|(debuff.in_firestorm.up&talent.everburning_flame&active_enemies<=3)|(buff.dragonrage.remains<=3.25*spell_haste&buff.dragonrage.remains>=2.5*spell_haste)
    elseif ( is_available(SB.EverburningFlame) and buff_dragonrage_up and active_enemies >= 5 ) or not is_available(SB.FontofMagic) or ( debuff_in_firestorm_up and is_available(SB.EverburningFlame) and active_enemies <= 3 ) or ( buff_dragonrage_remains <= 3.25 * spell_haste and buff_dragonrage_remains >= 2.5 * spell_haste ) then
      empower_to_stage = 3
    else
      --actions.fb+=/fire_breath,empower_to=4,target_if=max:target.health.pct
      empower_to_stage = 4
    end
    return cast_with_queue(SB.FireBreath)
  end

  local function es()
--    actions.es=eternity_surge,empower_to=1,target_if=max:target.health.pct,if=active_enemies<=1+talent.eternitys_span|buff.dragonrage.remains<1.75*spell_haste&buff.dragonrage.remains>=1*spell_haste|buff.dragonrage.up&(active_enemies==5|!talent.eternitys_span&active_enemies>=6|talent.eternitys_span&active_enemies>=8)
    -- bursting affix check on stage 1
    if active_enemies <= 1 + num(is_available(SB.EternitysSpan)) or ( buff_dragonrage_remains < 1.75 * spell_haste and buff_dragonrage_remains >= 1 * spell_haste ) or ( buff_dragonrage_up and ( active_enemies == 5 or not is_available(SB.EternitysSpan) and active_enemies >= 6 or is_available(SB.EternitysSpan) and active_enemies >= 8 ) ) or player.debuff(SB.Burst).count >= 2 then
      empower_to_stage = 1

--      actions.es+=/eternity_surge,empower_to=2,target_if=max:target.health.pct,if=active_enemies<=2+2*talent.eternitys_span|buff.dragonrage.remains<2.5*spell_haste&buff.dragonrage.remains>=1.75*spell_haste
    elseif active_enemies <= 2 + 2 * num(is_available(SB.EternitysSpan)) or buff_dragonrage_remains < 2.5 * spell_haste and buff_dragonrage_remains >= 1.75 * spell_haste then
      empower_to_stage = 2

--      actions.es+=/eternity_surge,empower_to=3,target_if=max:target.health.pct,if=active_enemies<=3+3*talent.eternitys_span|!talent.font_of_magic|buff.dragonrage.remains<=3.25*spell_haste&buff.dragonrage.remains>=2.5*spell_haste
    elseif active_enemies <= 3 + 3 * num(is_available(SB.EternitysSpan)) or (not is_available(SB.FontofMagic)) or buff_dragonrage_remains <= 3.25 * spell_haste and buff_dragonrage_remains >= 2.5 * spell_haste then
      empower_to_stage = 3

--      actions.es+=/eternity_surge,empower_to=4,target_if=max:target.health.pct
    else
      empower_to_stage = 4
    end
    return cast_with_queue(SB.EternitySurge)
  end

  local function aoe()
--    actions.aoe=shattering_star,target_if=max:target.health.pct,if=cooldown.dragonrage.up
    if target.castable(SB.ShatteringStar) and spell(SB.Dragonrage).ready then
      if channeling_disintegrate then
        spell_before_disintegrate_ready = 1
      else
        return cast_with_queue(SB.ShatteringStar, target)
      end
    end

--    actions.aoe+=/dragonrage,if=target.time_to_die>=32|fight_remains<30
    if toggle('cooldowns', false) and castable(SB.Dragonrage) and ( target.time_to_die >= 32 or target.boss and target.time_to_die < 30 ) then
      if channeling_disintegrate then
        spell_before_disintegrate_ready = 1
      else
        return cast_with_queue(SB.Dragonrage)
      end
    end

--    actions.aoe+=/tip_the_scales,if=buff.dragonrage.up&(active_enemies<=3+3*talent.eternitys_span|!cooldown.fire_breath.up)
    if toggle('cooldowns', false) and castable(SB.TipTheScales) and buff_dragonrage_up and (active_enemies <= 3 + 3 * num(is_available(SB.EternitysSpan)) or not spell(SB.FireBreath).ready) then
      if channeling_disintegrate then
        spell_before_disintegrate_ready = 1
      else
        return cast_with_queue(SB.TipTheScales)
      end
    end

--    actions.aoe+=/call_action_list,name=fb,if=(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_aoe|!talent.animosity)&((buff.power_swell.remains<variable.r1_cast_time|(!talent.volatility&active_enemies=3))&buff.blazing_shards.remains<variable.r1_cast_time|buff.dragonrage.up)&(target.time_to_die>=8|fight_remains<30)
    if not player.moving and castable(SB.FireBreath) and target.distance <= 25 and ( not is_available(SB.Dragonrage) or next_dragonrage > dr_prep_time_aoe or not is_available(SB.Animosity) ) and ( ( buff(SB.PowerSwellBuff).remains < r1_cast_time or not is_available(SB.Volatility) and active_enemies == 3 ) and buff(SB.BlazingShardsBuff).remains < r1_cast_time or buff_dragonrage_up ) and ( target.time_to_die >= 8 or target.boss and target.time_to_die < 30 ) then
      if channeling_disintegrate then
        spell_before_disintegrate_ready = 1
      else 
        return fb()
      end
    end

--actions.aoe+=/call_action_list,name=es,if=buff.dragonrage.up|!talent.dragonrage|(cooldown.dragonrage.remains>variable.dr_prep_time_aoe&(buff.power_swell.remains<variable.r1_cast_time|(!talent.volatility&active_enemies=3))&buff.blazing_shards.remains<variable.r1_cast_time)&(target.time_to_die>=8|fight_remains<30)
    if not player.moving and castable(SB.EternitySurge) and target.distance <= 25 and (buff_dragonrage_up or not is_available(SB.Dragonrage) or ( cooldown_dragonrage_remains > dr_prep_time_aoe and ( buff(SB.PowerSwellBuff).remains < r1_cast_time or ( not is_available(SB.Volatility) and active_enemies == 3 ) ) and buff(SB.BlazingShardsBuff).remains < r1_cast_time ) and ( target.time_to_die >= 8 or target.boss and target.time_to_die < 30 ) ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return es()
        end
      end

--actions.aoe+=/deep_breath,if=!buff.dragonrage.up&essence.deficit>3
      if toggle('deep_breath', false) and castable(SB.DeepBreath) and not buff_dragonrage_up and player.power.essence.deficit > 3 then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.DeepBreath)
        end
      end

--actions.aoe+=/shattering_star,target_if=max:target.health.pct,if=buff.essence_burst.stack<buff.essence_burst.max_stack|!talent.arcane_vigor
      if target.castable(SB.ShatteringStar) and ( buff_essence_burst_stack < buff_essence_burst_max_stack or not is_available(SB.ArcaneVigor) )  then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.ShatteringStar, target)
        end
      end


--    actions.aoe+=/firestorm
      if not_moving_or_hover and castable(SB.Firestorm) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.Firestorm, 'ground')
        end
      end

--    actions.aoe+=/pyre,target_if=max:target.health.pct,if=active_enemies>=4
--actions.aoe+=/pyre,target_if=max:target.health.pct,if=active_enemies>=3&talent.volatility
--actions.aoe+=/pyre,target_if=max:target.health.pct,if=buff.charged_blast.stack>=15
      if target.castable(SB.Pyre) and ( active_enemies >= 4 or active_enemies >= 3 and is_available(SB.Volatility) or player.buff(SB.ChargedBlastBuff).count >= 15 ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.Pyre, target)
        end
      end

--    actions.aoe+=/living_flame,target_if=max:target.health.pct,if=(!talent.burnout|buff.burnout.up|active_enemies>=4|buff.scarlet_adaptation.up)&buff.leaping_flames.up&!buff.essence_burst.up&essence<essence.max-1
      if not_moving_or_hover and target.castable(SB.LivingFlame) and ( not is_available(SB.Burnout) or player.buff(SB.BurnoutBuff).up or active_enemies >= 4 or buff(SB.ScarletAdaptationBuff).up ) and player.buff(SB.LeapingFlamesBuff).up and player.buff(SB.EssenceBurstBuff).down and player.power.essence.actual < player.power.essence.max - 1 then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.LivingFlame, target)
        end
      end

--    actions.aoe+=/disintegrate,target_if=max:target.health.pct,chain=1,early_chain_if=evoker.use_early_chaining&ticks>=2&essence.deficit<2&(raid_event.movement.in>2|buff.hover.up),interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(!(buff.power_infusion.up&buff.bloodlust.up)|cooldown.fire_breath.up|cooldown.eternity_surge.up)&(raid_event.movement.in>2|buff.hover.up),if=raid_event.movement.in>2|buff.hover.up
      if channeling_disintegrate then
        if use_clipping and buff_dragonrage_up and not player.moving and disintegrate_ticks >= 2 and ( not ( buff(SB.PowerInfusionBuff).up and has_bloodlust(player) ) or spell(SB.EternitySurge).ready or spell(SB.FireBreath).ready ) then
          return macro('/stopcasting')
        end
        if spell_before_disintegrate_ready == 1 then
          spell_before_disintegrate_ready = 0
          return
        end
        if use_early_chaining and not_moving_or_hover and target.castable(SB.Disintegrate) and disintegrate_ticks >= 2 and player.power.essence.deficit < 2 then
          return cast_with_queue(SB.Disintegrate, target)
        end
        if on_last_disintegrate_tick and not_moving_or_hover and target.castable(SB.Disintegrate) then
          return cast_with_queue(SB.Disintegrate, target)
        end
      else
        if not_moving_or_hover and target.castable(SB.Disintegrate) then
          return cast_with_queue(SB.Disintegrate, target)
        end
      end

      if channeling_disintegrate then return end

--    actions.aoe+=/living_flame,target_if=max:target.health.pct,if=talent.snapfire&buff.burnout.up
      if not_moving_or_hover and target.castable(SB.LivingFlame) and is_available(SB.Snapfire) and player.buff(SB.BurnoutBuff).up then
        return cast_with_queue(SB.LivingFlame, target)
      end

--    actions.aoe+=/call_action_list,name=green,if=talent.ancient_flame&!buff.ancient_flame.up&!buff.dragonrage.up
      if is_available(SB.AncientFlame) and buff(SB.AncientFlameBuff).down and not buff_dragonrage_up then
--actions.green=emerald_blossom
        if castable(SB.EmeraldBlossom) then
          return cast_with_queue(SB.EmeraldBlossom, player)
        end
--actions.green+=/verdant_embrace
        if castable(SB.VerdantEmbrace) then
          return cast_with_queue(SB.VerdantEmbrace, player)
        end
      end

--actions.aoe+=/azure_strike,target_if=max:target.health.pct
      if target.castable(SB.AzureStrike) then
        return cast_with_queue(SB.AzureStrike, target)
      end
    end

    local function st()
--actions.st=use_item,name=kharnalex_the_first_light,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down&raid_event.movement.in>6
--    if main_hand_ready and not buff_dragonrage_up and target.debuff(SB.ShatteringStar).down then
--      if channeling_disintegrate then
--        spell_before_disintegrate_ready = 1
--      else
--        if modifier.lcontrol then
--          return macro('/use 16')
--        else
--          kharnalex_ready = true
--        end
--      end
--    end

--actions.st+=/firestorm,if=buff.snapfire.up

--actions.st+=/dragonrage,if=cooldown.fire_breath.remains<4&cooldown.eternity_surge.remains<10&target.time_to_die>=32|fight_remains<30
      if toggle('cooldowns', false) and castable(SB.Dragonrage) and spell(SB.FireBreath).cooldown_without_gcd < 4 and spell(SB.EternitySurge).cooldown_without_gcd < 10 and ( target.time_to_die >= 32 or target.boss and target.time_to_die < 30 ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.Dragonrage)
        end
      end

--      actions.st+=/tip_the_scales,if=buff.dragonrage.up&(((!talent.font_of_magic|talent.everburning_flame)&cooldown.fire_breath.remains<cooldown.eternity_surge.remains&buff.dragonrage.remains<14)|(cooldown.eternity_surge.remains<cooldown.fire_breath.remains&!talent.everburning_flame&talent.font_of_magic))
      if toggle('cooldowns', false) and castable(SB.TipTheScales) and buff_dragonrage_up and ( ( ( not is_available(SB.FontofMagic) or is_available(SB.EverburningFlame) ) and spell(SB.FireBreath).cooldown_without_gcd < spell(SB.EternitySurge).cooldown_without_gcd and buff_dragonrage_remains < 14 ) or ( spell(SB.EternitySurge).cooldown_without_gcd < spell(SB.FireBreath).cooldown_without_gcd and not is_available(SB.EverburningFlame) and is_available(SB.FontofMagic) ) ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.TipTheScales)
        end
      end

--actions.st+=/call_action_list,name=fb,if=(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_st|!talent.animosity)&((buff.power_swell.remains<variable.r1_cast_time|buff.bloodlust.up|buff.power_infusion.up|buff.dragonrage.up)&(buff.blazing_shards.remains<variable.r1_cast_time|buff.dragonrage.up))&(!cooldown.eternity_surge.up|!talent.event_horizon|!buff.dragonrage.up)&(target.time_to_die>=8|fight_remains<30)
      if not player.moving and castable(SB.FireBreath) and target.distance <= 25 and ( not is_available(SB.Dragonrage) or next_dragonrage > dr_prep_time_st or not is_available(SB.Animosity) ) and ( ( buff(SB.PowerSwellBuff).remains < r1_cast_time or buff(SB.PowerInfusionBuff).up or has_bloodlust(player) or buff_dragonrage_up ) and ( buff(SB.BlazingShardsBuff).remains < r1_cast_time or buff_dragonrage_up ) ) and ( not spell(SB.EternitySurge).ready or not is_available(SB.EventHorizon) or not buff_dragonrage_up ) and ( target.time_to_die >= 8 or target.boss and target.time_to_die < 30 ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else 
          return fb()
        end
      end

--actions.st+=/disintegrate,if=buff.dragonrage.remains>19&cooldown.fire_breath.remains>28&talent.eye_of_infinity&set_bonus.tier30_2pc

--actions.st+=/shattering_star,if=(buff.essence_burst.stack<buff.essence_burst.max_stack|!talent.arcane_vigor)&(!cooldown.fire_breath.up|!talent.event_horizon)
      if target.castable(SB.ShatteringStar) and ( buff_essence_burst_stack < buff_essence_burst_max_stack or not is_available(SB.ArcaneVigor) ) and ( not spell(SB.FireBreath).ready or not is_available(SB.EventHorizon) ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.ShatteringStar, target)
        end
      end

--      actions.st+=/call_action_list,name=es,if=(!talent.dragonrage|variable.next_dragonrage>variable.dr_prep_time_st|!talent.animosity)&((buff.power_swell.remains<variable.r1_cast_time|buff.bloodlust.up|buff.power_infusion.up)&(buff.blazing_shards.remains<variable.r1_cast_time|buff.dragonrage.up))&(target.time_to_die>=8|fight_remains<30)
      if not player.moving and castable(SB.EternitySurge) and target.distance <= 25 and (not is_available(SB.Dragonrage) or next_dragonrage > dr_prep_time_st or not is_available(SB.Animosity) ) and ( ( buff(SB.PowerSwellBuff).remains < r1_cast_time or buff(SB.PowerInfusionBuff).up or has_bloodlust(player) ) and ( buff(SB.BlazingShardsBuff).remains < r1_cast_time or buff_dragonrage_up ) ) and ( target.time_to_die >= 8 or target.boss and target.time_to_die < 30 ) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return es()
        end
      end

--      actions.st+=/wait,sec=cooldown.fire_breath.remains,if=talent.animosity&buff.dragonrage.up&buff.dragonrage.remains<gcd.max+variable.r1_cast_time*buff.tip_the_scales.down&buff.dragonrage.remains-cooldown.fire_breath.remains>=variable.r1_cast_time*buff.tip_the_scales.down
      if is_available(SB.Animosity) and buff_dragonrage_up and buff_dragonrage_remains < gcd_max + r1_cast_time * num(buff(SB.TipTheScales).down) and buff_dragonrage_remains - spell(SB.FireBreath).cooldown_without_gcd >= r1_cast_time * num(buff(SB.TipTheScales).down) then
        return
      end

--      actions.st+=/wait,sec=cooldown.eternity_surge.remains,if=talent.animosity&buff.dragonrage.up&buff.dragonrage.remains<gcd.max+variable.r1_cast_time&buff.dragonrage.remains-cooldown.eternity_surge.remains>variable.r1_cast_time*buff.tip_the_scales.down
      if is_available(SB.Animosity) and buff_dragonrage_up and buff_dragonrage_remains < gcd_max + r1_cast_time and buff_dragonrage_remains - spell(SB.EternitySurge).cooldown_without_gcd > r1_cast_time * num(buff(SB.TipTheScales).down) then
        return
      end

--      actions.st+=/living_flame,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max&buff.burnout.up
      if not_moving_or_hover and target.castable(SB.LivingFlame) and buff_dragonrage_up and buff_dragonrage_remains < (buff_essence_burst_max_stack - buff_essence_burst_stack) * gcd_max and player.buff(SB.BurnoutBuff).up then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.LivingFlame, target)
        end
      end

--      actions.st+=/azure_strike,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max
      if target.castable(SB.AzureStrike) and (buff_dragonrage_up and buff_dragonrage_remains < (buff_essence_burst_max_stack - buff_essence_burst_stack) * gcd_max) then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.AzureStrike, target)
        end
      end


--      actions.st+=/living_flame,if=buff.burnout.up&(buff.leaping_flames.up&!buff.essence_burst.up|!buff.leaping_flames.up&buff.essence_burst.stack<buff.essence_burst.max_stack)&essence.deficit>=2
      if not_moving_or_hover and target.castable(SB.LivingFlame) and player.buff(SB.BurnoutBuff).up and ( buff(SB.LeapingFlamesBuff).up and buff(SB.EssenceBurstBuff).down or buff(SB.LeapingFlamesBuff).down and buff_essence_burst_stack < buff_essence_burst_max_stack ) and player.power.essence.deficit >= 2 then
        if channeling_disintegrate then
          spell_before_disintegrate_ready = 1
        else
          return cast_with_queue(SB.LivingFlame, target)
        end
      end

--      actions.st+=/pyre,if=debuff.in_firestorm.up&talent.raging_inferno&buff.charged_blast.stack==20&active_enemies>=2

--      actions.st+=/disintegrate,chain=1,early_chain_if=evoker.use_early_chaining&ticks>=2&essence.deficit<2&(raid_event.movement.in>2|buff.hover.up),interrupt_if=evoker.use_clipping&buff.dragonrage.up&ticks>=2&(!(buff.power_infusion.up&buff.bloodlust.up)|cooldown.fire_breath.up|cooldown.eternity_surge.up)&(raid_event.movement.in>2|buff.hover.up),if=raid_event.movement.in>2|buff.hover.up
      if channeling_disintegrate then
        if use_clipping and buff_dragonrage_up and not player.moving and disintegrate_ticks >= 2 and ( not ( buff(SB.PowerInfusionBuff).up and has_bloodlust(player) ) or spell(SB.EternitySurge).ready or spell(SB.FireBreath).ready ) then
          return macro('/stopcasting')
        end
        if spell_before_disintegrate_ready == 1 then
          spell_before_disintegrate_ready = 0
          return
        end
        if use_early_chaining and not_moving_or_hover and target.castable(SB.Disintegrate) and disintegrate_ticks >= 2 and player.power.essence.deficit < 2 then
          return cast_with_queue(SB.Disintegrate, target)
        end
        if on_last_disintegrate_tick and not_moving_or_hover and target.castable(SB.Disintegrate) then
          return cast_with_queue(SB.Disintegrate, target)
        end
      else
        if not_moving_or_hover and target.castable(SB.Disintegrate) then
          return cast_with_queue(SB.Disintegrate, target)
        end
      end

      if channeling_disintegrate then return end

--      actions.st+=/firestorm,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down
--      actions.st+=/deep_breath,if=!buff.dragonrage.up&active_enemies>=2&((raid_event.adds.in>=120&!talent.onyx_legacy)|(raid_event.adds.in>=60&talent.onyx_legacy))
--      actions.st+=/deep_breath,if=!buff.dragonrage.up&talent.imminent_destruction&!debuff.shattering_star_debuff.up

--      actions.st+=/call_action_list,name=green,if=talent.ancient_flame&!buff.ancient_flame.up&!buff.shattering_star_debuff.up&talent.scarlet_adaptation&!buff.dragonrage.up
      if is_available(SB.AncientFlame) and buff(SB.AncientFlameBuff).down and target.debuff(SB.ShatteringStar).down and is_available(SB.ScarletAdaptation) and not buff_dragonrage_up then
--actions.green=emerald_blossom
        if castable(SB.EmeraldBlossom) then
          return cast_with_queue(SB.EmeraldBlossom, player)
        end
--actions.green+=/verdant_embrace
        if castable(SB.VerdantEmbrace) then
          return cast_with_queue(SB.VerdantEmbrace, player)
        end
      end

--      actions.st+=/living_flame,if=!buff.dragonrage.up|(buff.iridescence_red.remains>execute_time|buff.iridescence_blue.up)&active_enemies==1
      if not_moving_or_hover_or_burnout_up and target.castable(SB.LivingFlame) and ( not buff_dragonrage_up or ( buff(SB.IridescenceRedBuff).remains > spell(SB.LivingFlame).castingtime or buff(SB.IridescenceBlueBuff).up ) and active_enemies == 1 ) then
        return cast_with_queue(SB.LivingFlame, target)
      end

--      actions.st+=/azure_strike
      if target.castable(SB.AzureStrike) then
        return cast_with_queue(SB.AzureStrike, target)
      end
    end

    local function use_items()
      if main_hand and equipted_item_ready(208321, 16) and target.health.percent < 35 then
        return macro('/use 16')
      end
      
      local start, duration, enable = GetInventoryItemCooldown("player", 13)
      if trinket_13 and enable == 1 and start == 0 then
        macro('/use 13')
      end

      start, duration, enable = GetInventoryItemCooldown("player", 14)
      if trinket_14 and enable == 1 and start == 0 then
        macro('/use 14')
      end
    end

    if target.enemy and target.alive then
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
        end
      end

      -- explosive affix
      local unit_name, unit_realm = UnitName("target")
      if unit_name == "Explosives" and not channeling_disintegrate then
        if target.castable(SB.LivingFlame) and player.buff(SB.BurnoutBuff).up then
          return cast_with_queue(SB.LivingFlame, target)
        end
        if target.castable(SB.AzureStrike) then
          return cast_with_queue(SB.AzureStrike, target)
        end
      end

      if target.castable(SB.Unravel) then
        if target.castable(SB.ShatteringStar) then
          return cast_with_queue(SB.ShatteringStar, target)
        end
        if not is_available(SB.ShatteringStar) or target.debuff(SB.ShatteringStar).up or spell(SB.ShatteringStar).cooldown > 5 then
          return cast_with_queue(SB.Unravel, target)
        end
      end

      -- bursting affix
      if player.debuff(SB.Burst).count >= 2 then
        if target.health.percent > 50 then
          return st()
        else
          return
        end
      end

      if toggle('cooldowns', false) and target.distance <= 25 and (buff_dragonrage_up or next_dragonrage > 20 or not is_available(SB.Dragonrage)) and not channeling_disintegrate then
        use_items()
      end

      if active_enemies >= 3 and toggle('multitarget', false) then
        return aoe()
      else
        return st()
      end
    end
  end

  local function resting()
    if not player.alive then return end

    local not_moving_or_hover = not player.moving or player.buff(SB.Hover).up
    local not_moving_or_hover_or_burnout_up = not_moving_or_hover or player.buff(SB.BurnoutBuff).up

    if modifier.lshift and castable(SB.EmeraldBlossom) then
      return cast_with_queue(SB.EmeraldBlossom, player)
    end
  end

  function interface()
    local devastation_gui = {
      key = 'ev_nikopol',
      title = 'Devastation',
      width = 250,
      height = 320,
      resize = true,
      show = false,
      template = {
        { type = 'header', text = 'Devastation Settings' },
        { type = 'rule' },   
        { type = 'text', text = 'Healing Settings' },
        { key = 'healing_potion', type = 'checkbox', text = 'Refreshing Healing Potion', desc = 'Use Refreshing Healing Potion when below 10% health', default = false },
        { type = 'rule' },   
        { type = 'text', text = 'Disintegrate' },
        { key = 'use_clipping', type = 'checkbox', text = 'Use clipping', desc = 'Set to let every Disintegrate in Dragonrage be clipped after the 3rd tick.', default = true },
        { key = 'use_early_chaining', type = 'checkbox', text = 'Use early chaining', desc = 'Set to chain Disintegrate in Dragonrage before the window where a tick can be carried without loss (3rd tick on 5 tick disintegrates)', default = true },
        { type = 'rule' },  
        { type = 'text', text = 'Items' },
        { key = 'trinket_13', type = 'checkbox', text = '13', desc = 'use first trinket', default = false },
        { key = 'trinket_14', type = 'checkbox', text = '14', desc = 'use second trinket', default = false },
        { key = 'main_hand', type = 'checkbox', text = '16', desc = 'use main_hand', default = false },
      }
    }

    configWindow = bxhnz7tp5bge7wvu.interface.builder.buildGUI(devastation_gui)

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
        name = 'deep_breath',
        label = 'Deep Breath',
        on = {
          label = 'DB',
          color = bxhnz7tp5bge7wvu.interface.color.green,
          color2 = bxhnz7tp5bge7wvu.interface.color.green
        },
        off = {
          label = 'db',
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
      spec = bxhnz7tp5bge7wvu.rotation.classes.evoker.devastation,
      name = 'dev_nikopol',
      label = 'Devastation by Nikopol',
      gcd = gcd,
      combat = combat,
      resting = resting,
      interface = interface
    })
