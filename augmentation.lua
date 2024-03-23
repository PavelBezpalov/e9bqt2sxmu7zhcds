local bxhnz7tp5bge7wvu = bxhnz7tp5bge7wvu_interface
local SB = e3y87ukfgr442ue6

local last_empovered_spell
local last_empovered_spell_last_stage_start
local last_empovered_spell_finish_time
local empower_to_stage = 0

local function is_available(spell)
  return IsSpellKnown(spell, false) or IsPlayerSpell(spell)
end

local function in_same_phase(unit)
  return UnitInPartyShard(unit.unitID)
end

local function isDamager(unit)
  return UnitGroupRolesAssigned(unit.unitID) == 'DAMAGER'
end

local function isTank(unit)
  return UnitGroupRolesAssigned(unit.unitID) == 'TANK'
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

local function equipted_item(item_id, slot_id)
  local equipted_item_id = GetInventoryItemID("player", slot_id)
  return equipted_item_id == item_id
end

local function equipted_item_ready(item_id, slot_id)
  local start, duration, enable = GetInventoryItemCooldown("player", slot_id)
  return enable == 1 and start == 0 and equipted_item(item_id, slot_id)
end

local function combat()
  if not player.alive then return end
   
  local empower_stage = empower_stage()
  local not_moving_or_hover = not player.moving or player.buff(SB.Hover).up
  local trinket_13 = bxhnz7tp5bge7wvu.settings.fetch('aug_nikopol_trinket_13', false)
  local trinket_14 = bxhnz7tp5bge7wvu.settings.fetch('aug_nikopol_trinket_14', false)
  local main_hand = bxhnz7tp5bge7wvu.settings.fetch('aug_nikopol_main_hand', false)
  local healing_potion = bxhnz7tp5bge7wvu.settings.fetch('aug_nikopol_healing_potion', false)
   
  -- iridal cast
  if player.spell(419278).current then return end
  -- Nymue's Unraveling Spindle
  if player.spell(422956).current then return end
   
  local emenies_around_target = enemies.count(function (unit)
    return unit.alive and unit.distance >= target.distance - 5 and unit.distance <= target.distance + 5
  end)

  local tank_unit = group.match(function (unit)
    return unit.alive and unit.castable(SB.BlisteringScales) and in_same_phase(unit) and isTank(unit) and unit.buff(SB.BlisteringScalesBuff).refreshable
  end)

  local dps_for_prescience = group.match(function (unit)
    return unit.alive and unit.castable(SB.Prescience) and in_same_phase(unit) and isDamager(unit) and unit.buff(SB.PrescienceBuff).refreshable and unit.name ~= player.name
  end)

  if player.channeling() or on_last_stage() then
    if last_empovered_spell == 'Fire Breath' and on_last_stage() then
      return cast_while_casting(SB.FireBreath)
    end
    
    if last_empovered_spell == 'Upheaval' and ( empower_stage == empower_to_stage or on_last_stage() ) then
      return cast_while_casting(SB.Upheaval)
    end

    return
  end
  
  if castable(SB.ObsidianScales) and player.buff(SB.ObsidianScales).down and player.health.percent < 50 then
    cast_with_queue(SB.ObsidianScales)
  end
  
  if castable(SB.VerdantEmbrace) and player.health.effective < 40 then
    return cast_with_queue(SB.VerdantEmbrace, player)
  end
    
  if castable(SB.EmeraldBlossom) and player.health.effective < 40 then
    return cast_with_queue(SB.EmeraldBlossom, player)
  end
  
  if healing_potion and GetItemCooldown(191380) == 0 and player.health.effective < 10 then
    macro('/use Refreshing Healing Potion')
  end
  
  if GetCVar("nameplateShowEnemies") == '0' then
    SetCVar("nameplateShowEnemies", 1)
  end
  
  if GetItemCooldown(5512) == 0 and player.health.percent < 30 then
    macro('/use Healthstone')
  end

  if castable(SB.RenewingBlaze) and player.health.percent < 50 then
    cast_with_queue(SB.RenewingBlaze)
  end
  
  if modifier.lcontrol and castable(SB.TailSwipe) then
    return cast_with_queue(SB.TailSwipe)
  end

  if castable(SB.Prescience) then
    if dps_for_prescience then
      return cast_with_queue(SB.Prescience, dps_for_prescience)
    end
    
    if player.buff(SB.PrescienceBuff).refreshable then
      return cast_with_queue(SB.Prescience, player)
    end
  end
  
  if castable(SB.BlisteringScales) and tank_unit then
    return cast_with_queue(SB.BlisteringScales, tank_unit)
  end
  
  if not_moving_or_hover and castable(SB.EbonMight) and buff(SB.EbonMightSelfBuff).down then
    return cast_with_queue(SB.EbonMight)
  end
  
  if toggle('dispell', false) then
    if castable(SB.Expunge) and player.dispellable(SB.Expunge) then
      return cast_with_queue(SB.Expunge, player)
    end

    local unit = group.dispellable(SB.Expunge)
    if unit and unit.distance <= 25 and castable(SB.Expunge) then
      return cast_with_queue(SB.Expunge, unit)
    end

    if castable(SB.CauterizingFlame) and player.dispellable(SB.CauterizingFlame) then
      return cast_with_queue(SB.CauterizingFlame, player)
    end

    unit = group.dispellable(SB.CauterizingFlame)
    if unit and unit.distance <= 25 and castable(SB.CauterizingFlame) then
      return cast_with_queue(SB.CauterizingFlame, unit)
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

        if castable(SB.WingBuffet) and target.distance <= 15 then
          return cast_with_queue(SB.WingBuffet)
        end
      end
    end
    
    if main_hand and equipted_item_ready(208321, 16) and target.health.percent < 35 then
      return macro('/use 16')
    end
    
    local start, duration, enable = GetInventoryItemCooldown("player", 13)
    local trinket_id = GetInventoryItemID("player", 13)
    if trinket_13 and enable == 1 and start == 0 then
      macro('/use 13')
    end
    
    start, duration, enable = GetInventoryItemCooldown("player", 14)
    trinket_id = GetInventoryItemID("player", 14)
    if trinket_14 and enable == 1 and start == 0 then
      macro('/use 14')
    end
    
    if ( not player.moving or spell(SB.TipTheScales).ready ) and castable(SB.FireBreath) and target.distance <= 25 then
      if castable(SB.TipTheScales) then
        cast_with_queue(SB.TipTheScales)
      end
      return cast_with_queue(SB.FireBreath)
    end
    
    if not player.moving and target.castable(SB.Upheaval) then
      if emenies_around_target > 1 then
        empower_to_stage = 4
      else
        empower_to_stage = 1
      end
      return cast_with_queue(SB.Upheaval, target)
    end
    
    if not_moving_or_hover and castable(SB.Eruption) and target.distance <= 25 and ( player.buff(SB.EbonMightSelfBuff).up or player.buff(SB.TremblingEarthBuff).count == 5 or player.power.essence.actual == player.power.essence.max ) then
      return cast_with_queue(SB.Eruption, target)
    end
    
    if target.castable(SB.Unravel) then
      return cast_with_queue(SB.Unravel, target)
    end
  
    if not_moving_or_hover and target.castable(SB.LivingFlame) then
      return cast_with_queue(SB.LivingFlame, target)
    end
        
    if target.castable(SB.AzureStrike) then
      return cast_with_queue(SB.AzureStrike, target)
    end
  end
end

function resting()
  if not player.alive then return end

  if not toggle('rest', false) then return end
  
  local tank_unit = group.match(function (unit)
    return unit.alive and unit.castable(SB.BlisteringScales) and in_same_phase(unit) and isTank(unit) and unit.buff(SB.BlisteringScalesBuff).down
  end)

  local dps_for_prescience = group.match(function (unit)
    return unit.alive and unit.castable(SB.Prescience) and in_same_phase(unit) and isDamager(unit) and unit.buff(SB.PrescienceBuff).down and unit.name ~= player.name
  end)

  if castable(SB.Prescience) then
    if dps_for_prescience then
      return cast_with_queue(SB.Prescience, dps_for_prescience)
    end
    
    if player.buff(SB.PrescienceBuff).down then
      return cast_with_queue(SB.Prescience, player)
    end
  end
  
  if castable(SB.BlisteringScales) and tank_unit then
    return cast_with_queue(SB.BlisteringScales, tank_unit)
  end
end

local function interface()
  local augmentation_gui = {
    key = 'aug_nikopol',
    title = 'Augmentation',
    width = 250,
    height = 320,
    resize = true,
    show = false,
    template = {
      { type = 'header', text = 'Augmentation Settings' },
      { type = 'rule' },   
      { type = 'text', text = 'Healing Settings' },
      { key = 'healing_potion', type = 'checkbox', text = 'Healing Potion', desc = 'Use Healing Potion when below 10% health', default = false },
      { type = 'header', text = 'Trinkets' },
      { key = 'trinket_13', type = 'checkbox', text = '13', desc = 'use first trinket', default = false },
      { key = 'trinket_14', type = 'checkbox', text = '14', desc = 'use second trinket', default = false },
      { key = 'main_hand', type = 'checkbox', text = '16', desc = 'use main_hand', default = false },
    }
  }

  configWindow = bxhnz7tp5bge7wvu.interface.builder.buildGUI(augmentation_gui)

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
    spec = bxhnz7tp5bge7wvu.rotation.classes.evoker.augmentation,
    name = 'aug_nikopol',
    label = 'Augmentation by Nikopol',
    combat = combat,
    resting = resting,
    interface = interface
  })
