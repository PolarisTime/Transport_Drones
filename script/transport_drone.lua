-- 加载共享模块和运输科技模块 (Load shared modules and transport technologies)
local shared = require("shared")
local transport_technologies = require("script/transport_technologies")

-- 从共享模块获取无人机配置参数 (Get drone configuration parameters from shared module)
local fuel_amount_per_drone = shared.fuel_amount_per_drone -- 每架无人机的燃料量 (Fuel amount per drone)
local fuel_consumption_per_meter = shared.fuel_consumption_per_meter -- 每米燃料消耗 (Fuel consumption per meter)
local drone_pollution_per_second = shared.drone_pollution_per_second -- 每秒污染排放 (Pollution emissions per second)

-- 脚本数据存储全局无人机状态 (Script data stores global drone state)
local script_data =
{
  drones = {}, -- 存储所有活动无人机的字典，键为unit_number (Dictionary storing all active drones, keyed by unit_number)
  riding_players = {}, -- 存储正在骑乘无人机的玩家 (Players currently riding drones)
  reset_to_be_taken_again = true, -- 重置标志：重新计算待取物品 (Reset flag: recalculate items to be taken)
  reset_fuel_on_the_way = true -- 重置标志：重新计算运输中的燃料 (Reset flag: recalculate fuel on the way)
}

-- 燃料流体缓存和获取函数 (Fuel fluid cache and getter function)
local fuel_fluid
local get_fuel_fluid = function()
  if fuel_fluid then
    return fuel_fluid -- 返回缓存的燃料流体名称 (Return cached fuel fluid name)
  end
  -- 从燃料仓库配方中获取燃料流体名称 (Get fuel fluid name from fuel depot recipe)
  fuel_fluid = prototypes.recipe["fuel-depots"].products[1].name
  return fuel_fluid
end

-- 传输无人机类和元表定义 (Transport drone class and metatable definition)
local transport_drone = {}

-- 设置元表以启用面向对象方法调用 (Set metatable to enable object-oriented method calls)
transport_drone.metatable = {__index = transport_drone}

-- 将无人机添加到全局跟踪字典中 (Add drone to global tracking dictionary)
local add_drone = function(drone)
  script_data.drones[drone.index] = drone
end

-- 从全局跟踪字典中移除无人机 (Remove drone from global tracking dictionary)
local remove_drone = function(drone)
  script_data.drones[drone.index] = nil
end

local get_drone = function(index)

  local drone = script_data.drones[index]

  if not drone then
    return
  end

  if not drone.entity.valid then
    drone:clear_drone_data()
    return
  end

  return drone

end


-- 无人机状态枚举 (Drone state enumeration)
local states =
{
  going_to_supply = 1, -- 前往供应仓库 (Going to supply depot)
  return_to_requester = 2, -- 返回请求仓库 (Returning to request depot)
  waiting_for_reorder = 3, -- 等待重新分配任务 (Waiting for reorder)
  delivering_fuel = 4 -- 运送燃料 (Delivering fuel)
}

local get_drone_speed = function(force_index)
  return (0.066 * (1 + transport_technologies.get_transport_speed_bonus(force_index))) --+ (math.random() / 32)
end

local variation_count = shared.variation_count
local special_variation_count = shared.special_variation_count
local random = math.random

local is_drone_cache = {}
local is_special_drone = function(name)
  local bool = is_drone_cache[name]
  if bool ~= nil then
    return bool
  end
  bool = prototypes.entity["transport-drone-"..name.."-1"] ~= nil
  is_drone_cache[name] = bool
  return bool
end

local get_drone_name = function(item_name)
  if item_name then
    if is_special_drone(item_name) then
      return "transport-drone-"..item_name.."-"..random(special_variation_count)
    end
  end
  return "transport-drone-"..random(variation_count)
end


local player_leave_drone = function(player)

  local drone = script_data.riding_players[player.index]
  if not drone then return end

  script_data.riding_players[player.index] = nil
  drone.riding_player = nil
  drone:update_speed()

end

local player_enter_drone = function(player, drone)

  script_data.riding_players[player.index] = drone
  drone.riding_player = player.index
  drone:update_speed()

end


-- 创建新的传输无人机实例 (Create new transport drone instance)
-- @param request_depot: 请求仓库对象 (Request depot object)
-- @param drone_name: 无人机名称（可选，用于特殊外观） (Drone name, optional for special appearance)
transport_drone.new = function(request_depot, drone_name)

  -- 获取仓库的尸体位置用于无人机生成 (Get depot corpse position for drone spawning)
  local corpse = request_depot.corpse
  if not (corpse and corpse.valid) then
    if request_depot.get_corpse then
      corpse = request_depot:get_corpse()
    end
  end
  if not (corpse and corpse.valid) then
    error("No corpse found") -- 如果找不到尸体位置，抛出错误 (Throw error if corpse position not found)
  end

  -- 使用surface.create_entity创建无人机实体 (Create drone entity using surface.create_entity)
  local entity = request_depot.entity.surface.create_entity{
    name = get_drone_name(drone_name), -- 获取无人机实体名称 (Get drone entity name)
    position = corpse.position, -- 在尸体位置生成 (Spawn at corpse position)
    force = request_depot.entity.force -- 设置为与仓库相同的势力 (Set to same force as depot)
  }
  if not (entity and entity.valid) then return end

  -- 创建无人机对象并设置初始属性 (Create drone object and set initial properties)
  local drone =
  {
    entity = entity, -- 游戏中的实体引用 (Game entity reference)
    request_depot = request_depot, -- 归属的请求仓库 (Owning request depot)
    index = tostring(entity.unit_number), -- 唯一标识符 (Unique identifier)
    state = 0, -- 当前状态（初始为0） (Current state, initially 0)
    requested_count = 0, -- 请求的物品数量 (Requested item count)
    tick_created = game.tick -- 创建时的游戏刻度 (Game tick when created)
  }
  setmetatable(drone, transport_drone.metatable) -- 设置元表以启用方法调用 (Set metatable to enable method calls)
  add_drone(drone) -- 将无人机添加到全局跟踪 (Add drone to global tracking)

  --entity.ai_settings.path_resolution_modifier = 0 -- AI设置，已注释 (AI settings, commented out)

  return drone
end

function transport_drone:update_speed()
  local speed = get_drone_speed(self.entity.force.index)
  if self.riding_player then
    speed = speed * 1.5
  elseif self.fuel_amount then
    speed = speed * 0.6
  elseif self.held_item then
    speed = speed * 0.75
  end
  self.entity.speed = speed
end

function transport_drone:add_slow_sticker()
  self.entity.surface.create_entity{name = "drone-slowdown-sticker", position = self.entity.position, target = self.entity, force = "neutral"}
end

function transport_drone:pickup_from_supply(supply, item,quality, count)

  if not supply.entity.valid then
    self:return_to_requester()
    return
  end

  self.supply_depot = supply
  self.requested_count = count
  self.requested_item = item
  self.requested_quality = quality
  self.supply_depot:add_to_be_taken(item,quality, count)

  self:add_slow_sticker()
  self:update_speed()
  self.state = states.going_to_supply

  self:go_to_depot(self.supply_depot)

end

function transport_drone:deliver_fuel(depot, amount)

  if not depot.entity.valid then
    self:return_to_requester()
  end

  self.target_depot = depot
  self.fuel_amount = amount
  self.state = states.delivering_fuel
  self.target_depot.fuel_on_the_way = (self.target_depot.fuel_on_the_way or 0) + amount

  self:add_slow_sticker()
  self:update_speed()
  self:update_sticker()

  self:go_to_depot(self.target_depot)

end

function transport_drone:retry_command()

  local distance = 1.5

  local surface = self.entity.surface
  if not surface.can_place_entity
  {
    name = self.entity.name,
    position = self.entity.position,
    build_check_type=defines.build_check_type.manual
  } then
    local position = self.entity.surface.find_non_colliding_position(self.entity.name, self.entity.position, 5, 0.25, false)
    if position then
      self.entity.teleport(position)
    end
  end

  if self.state == states.going_to_supply then
    if self.supply_depot.entity.valid then
      self:go_to_depot(self.supply_depot, distance)
    else
      self:return_to_requester()
    end
    return
  end

  if self.state == states.delivering_fuel then
    if self.target_depot.entity.valid then
      self:go_to_depot(self.target_depot, distance)
    else
      self:return_to_requester()
    end
    return
  end

  if self.state == states.waiting_for_reorder then
    self:say("Forgive me master")
    self:suicide()
    return
  end

  if self.state == states.return_to_requester then
    if self.request_depot.entity.valid then
      self:go_to_depot(self.request_depot, distance)
    else
      self:suicide()
    end
    return
  end

end

function transport_drone:process_failed_command()

  if (self.failed_command_count or 0) < 2 then
    self.failed_command_count = (self.failed_command_count or 0) + 1
    self:say("R")
    self:retry_command()
    return
  end

  self:say("F")

  if self.state == states.going_to_supply then
    self:return_to_requester()
    return
  end

  if self.state == states.delivering_fuel then
    self:return_to_requester()
    return
  end

  if self.state == states.waiting_for_reorder then
    self:say("Forgive me master")
    self:suicide()
    return
  end

  if self.state == states.return_to_requester then
    self:suicide()
    return
  end

end

local distance = util.distance
function transport_drone:distance(position)
  return distance(self.entity.position, position)
end

local min = math.min
function transport_drone:process_pickup()

  if not self.request_depot.item then
    self:return_to_requester()
    return
  end

  if self.requested_item ~= self.request_depot.item then
    self:return_to_requester()
    return
  end

  if not self.supply_depot.entity.valid then
    self:return_to_requester()
    return
  end

  local available_count = self.requested_count + self.supply_depot:get_available_item_count(self.request_depot.item,self.request_depot.quality)

  local to_take
  if not self.request_depot.circuit_limit then
    -- No circuit limit, pickup as much as we can
    to_take = min(available_count, self.request_depot:get_request_size())
  else
    -- We want to only take what we requested.
    to_take = self.requested_count
  end

  local sprite_switch = false

  if to_take > 0 then
    local temperature = self.supply_depot.get_temperature and self.supply_depot:get_temperature()
    local given_count = self.supply_depot:give_item(self.requested_item,self.requested_quality, to_take)

    if given_count > 0 then
      self.held_item = self.requested_item
      self.held_quality = self.requested_quality
      self.held_count = given_count
      self.held_temperature = temperature
      self:update_sticker()
      sprite_switch = true
    end

  end

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester(sprite_switch)

end

function transport_drone:process_deliver_fuel()

  local delivered = false

  if self.target_depot.entity.valid then
    self.target_depot.entity.insert_fluid({name = get_fuel_fluid(), amount = self.fuel_amount})
    self:clear_reservations()
    self.fuel_amount = nil
    delivered = true
  end

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester(delivered)

end

function transport_drone:clear_reservations()

  if self.state == states.going_to_supply then
    if self.supply_depot and self.supply_depot.entity.valid and self.requested_item then
      self.supply_depot:add_to_be_taken(self.requested_item,self.requested_quality, -self.requested_count)
      self.requested_item = nil
      self.requested_count = nil
    end
  end

  if self.state == states.delivering_fuel then
    if self.target_depot and self.target_depot.entity.valid and self.fuel_amount then
      self.target_depot.fuel_on_the_way = self.target_depot.fuel_on_the_way - self.fuel_amount
    end
  end

end

function transport_drone:return_to_requester(sprite_switch)

  self:clear_reservations()

  if not self.request_depot.entity.valid then
    self:suicide()
    return
  end

  self:update_sticker()

  self.state = states.return_to_requester


  self:go_to_depot(self.request_depot, nil, sprite_switch)

end

local valid_item_cache = {}
local is_valid_item = function(item_name)
  local bool = valid_item_cache[item_name]
  if bool ~= nil then
    return bool
  end
  valid_item_cache[item_name] = prototypes.item[item_name] ~= nil
  return valid_item_cache[item_name]
end

local valid_fluid_cache = {}
local is_valid_fluid = function(fluid_name)
  local bool = valid_fluid_cache[fluid_name]
  if bool ~= nil then
    return bool
  end
  valid_fluid_cache[fluid_name] = prototypes.fluid[fluid_name] ~= nil
  return valid_fluid_cache[fluid_name]
end

function transport_drone:update_sticker()


  if self.background_rendering then
    self.background_rendering.destroy()
    self.background_rendering = nil
  end

  if self.item_rendering then
    self.item_rendering.destroy()
    self.item_rendering = nil
  end

  if self.held_item then

    local sprite
    if is_valid_fluid(self.held_item) then
      sprite = "fluid/"..self.held_item
    elseif is_valid_item(self.held_item) then
      sprite = "item/"..self.held_item
    end

    local surface = self.entity.surface
    local offset = self.entity.prototype.sticker_box.left_top
    --local force = self.entity.force

    self.background_rendering = rendering.draw_sprite
    {
      sprite = "utility/entity_info_dark_background",
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

    self.item_rendering = rendering.draw_sprite
    {
      sprite = sprite,
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {self.entity.force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

  end

  if self.fuel_amount then

    local surface = self.entity.surface
    local offset = self.entity.prototype.sticker_box.left_top

    self.background_rendering = rendering.draw_sprite
    {
      sprite = "utility/entity_info_dark_background",
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {self.entity.force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

    self.item_rendering = rendering.draw_sprite
    {
      sprite = "fluid/"..get_fuel_fluid(),
      target = self.entity,
      target_offset = offset,
      surface = surface,
      --forces = {self.entity.force},
      only_in_alt_mode = true,
      --target_offset = {0, -0.5},
      x_scale = 0.6,
      y_scale = 0.6,
    }

  end

end

function transport_drone:suicide()
  self:say("S")

  self:clear_drone_data()

  if self.request_depot.entity.valid then
    self.request_depot:remove_drone(self)
  end
  self.entity.force = "neutral"
  self.entity.die()
end

function transport_drone:process_return_to_requester()

  if not self.request_depot.entity.valid then
    self:suicide()
    return
  end

  if self.held_item then
    self.request_depot:take_item(self.held_item,self.held_quality, self.held_count, self.held_temperature)
    self.held_item = nil
  end

  if self.fuel_amount then
    self.request_depot.entity.insert_fluid({name = get_fuel_fluid(), amount = self.fuel_amount})
    self.fuel_amount = nil
  end

  --self:update_sticker()
  self:refund_fuel()

  --if self.supply_depot then
  --  self:wait_for_reorder()
  --  return
  --end

  self:remove_from_depot()

end

local random = math.random
function transport_drone:wait_for_reorder()
  self.state = states.waiting_for_reorder
  self.entity.set_command
  {
    type = defines.command.stop,
    ticks_to_wait = random(20, 30),
    distraction = defines.distraction.none
  }
end

function transport_drone:refund_fuel()
  local age = game.tick - (self.tick_created or game.tick - 1)
  local consumption = age * self.entity.speed * fuel_consumption_per_meter

  local pollution = (age / 60) * drone_pollution_per_second.pollution
  game.get_pollution_statistics(self.entity.surface).on_flow("transport-drone-1", pollution)

  --self:say(consumption)
  self.entity.force.get_fluid_production_statistics(self.entity.surface).on_flow(get_fuel_fluid(), -consumption)
  local fuel_refund = fuel_amount_per_drone - consumption
  --self:say(fuel_refund)

  if fuel_refund > 0 then
    self.request_depot.entity.insert_fluid({name = get_fuel_fluid(), amount = fuel_refund})
  elseif fuel_refund < 0 then
    self.request_depot.entity.remove_fluid({name = get_fuel_fluid(), amount = -fuel_refund})
  end

end

function transport_drone:remove_from_depot()

  self.request_depot:remove_drone(self)
  self:clear_drone_data()
  self.entity.destroy()

end

local min = math.min
function transport_drone:update(event)
  if not self.entity.valid then return end

  if event.result ~= defines.behavior_result.success then
    self:process_failed_command()
    return
  end

  if self.failed_command_count then
    self.failed_command_count = nil
  end

  if self.state == states.going_to_supply then
    self:process_pickup()
    return
  end

  if self.state == states.delivering_fuel then
    self:process_deliver_fuel()
    return
  end

  if self.state == states.return_to_requester then
    self:process_return_to_requester()
    return
  end

end

function transport_drone:say(text)
  -- self.entity.surface.create_entity{name = "tutorial-flying-text", position = self.entity.position, text = text}
end

-- 让无人机移动到指定位置 (Make drone move to specified position)
-- 使用Factorio的command系统控制单位移动 (Use Factorio's command system to control unit movement)
function transport_drone:go_to_position(position, radius)
  self.entity.set_command
  {
    type = defines.command.go_to_location, -- 移动到位置命令类型 (Go to location command type)
    destination = position, -- 目标位置 (Target position)
    radius = radius or 1, -- 接受半径，默认1格 (Acceptance radius, default 1 tile)
    distraction = defines.distraction.none, -- 不允许分心 (No distractions allowed)
    pathfind_flags = {prefer_straight_paths = false, use_cache = false}, -- 寻路标志 (Pathfinding flags)
  }
end

-- 让无人机移动到指定实体位置 (Make drone move to specified entity position)
function transport_drone:go_to_entity(entity, radius)
  self.entity.set_command
  {
    type = defines.command.go_to_location, -- 移动到位置命令类型 (Go to location command type)
    destination_entity = entity, -- 目标实体 (Target entity)
    radius = radius or 1, -- 接受半径，默认1格 (Acceptance radius, default 1 tile)
    distraction = defines.distraction.none, -- 不允许分心 (No distractions allowed)
    pathfind_flags = {prefer_straight_paths = false, use_cache = false} -- 寻路标志 (Pathfinding flags)
  }
end

local random = math.random
local drone_path_flags = {allow_paths_through_own_entities = true, prefer_straight_paths = true, use_cache = false, no_break = true}
local insert = table.insert

function transport_drone:go_to_depot(depot, radius, sprite_switch)
  local commands = {}
  local corpse = depot.corpse

  if not (corpse and corpse.valid) then
    if depot.get_corpse then
      corpse = depot:get_corpse()
    end
  end

  if not (corpse and corpse.valid) then
    --idk...
    self:suicide()
    return
  end
  --if sprite_switch then
  --  local proxy = self.entity.surface.create_entity
  --  {
  --    name = "sprite-switch-proxy",
  --    position = self.entity.position,
  --    force = "neutral"
  --  }
  --  insert(commands,
  --  {
  --    type = defines.command.attack,
  --    target = proxy,
  --    distraction = defines.distraction.none
  --  })
  --end

  insert(commands,
  {
    type = defines.command.go_to_location,
    destination_entity = corpse,
    distraction = defines.distraction.none,
    radius = radius or 0.5,
    pathfind_flags = drone_path_flags
  })

  insert(commands,
  {
    type = defines.command.stop,
    distraction = defines.distraction.none,
    ticks_to_wait = 15
  })

  self.entity.commandable.set_command
  {
    type = defines.command.compound,
    distraction = defines.distraction.none,
    structure_type = defines.compound_command.return_last,
    commands = commands
  }

end

function transport_drone:clear_drone_data()

  self:clear_reservations()

  if self.riding_player then
    local player = game.get_player(self.riding_player)
    if player then player_leave_drone(player) end
  end

  remove_drone(self)
end

function transport_drone:handle_drone_deletion()
  if self.entity.valid then
    self:say("D")
  end

  self:clear_drone_data()

  if self.request_depot.entity.valid then
    self.request_depot:remove_drone(self, true)
  end

end

local on_ai_command_completed = function(event)
  local drone = get_drone(tostring(event.unit_number))
  if not drone then return end
  drone:update(event)
end

local on_entity_removed = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end

  local unit_number = entity.unit_number
  if not unit_number then return end

  local drone = get_drone(tostring(unit_number))
  if not drone then return end

  if event.force then
    entity.force.get_kill_count_statistics(entity.surface).on_flow("transport-drone-1", 1)
    event.force.get_kill_count_statistics(entity.surface).on_flow("transport-drone-1", -1)    
  end

  drone:handle_drone_deletion()


end

local follow_drone_hotkey = function(event)
  local player = game.get_player(event.player_index)

  if script_data.riding_players[player.index] then
    player_leave_drone(player)
    return
  end

  if player.vehicle then
    --He is getting out of a vehicle.
    return
  end

  local radius = player.character and player.character.prototype.enter_vehicle_distance or 5

  if player.surface.count_entities_filtered{type = "car", force = player.force, position = player.position, radius = radius, limit = 1} > 0 then
    --There is a vehicle nearby, let him get into that.
    return
  end

  local units = player.surface.find_entities_filtered{type = "unit", force = player.force, position = player.position, radius = radius}

  for k, unit in pairs (units) do
    local drone = get_drone(tostring(unit.unit_number))
    if not drone then
      units[k] = nil
    elseif drone.riding_player then
      units[k] = nil
    end
  end

  if not next(units) then return end

  local closest = player.surface.get_closest(player.position, units)
  if not closest then return end

  local drone = get_drone(tostring(closest.unit_number))
  player_enter_drone(player, drone)

end

local floor = math.floor
local to_direction = function(orientation)
  local direction = floor(8 * (orientation + (1 / 16)))
  if direction >= 8 then direction = 0 end
  return direction
end


local get_orientation = function(source_position, target_position)

  -- Angle in rads
  local angle = util.angle(target_position, source_position)

  -- Convert to orientation
  local orientation =  (angle / (2 * math.pi)) - 0.25
  if orientation < 0 then orientation = orientation + 1 end

  return orientation

end

local smoothing = 0.20

local on_tick = function(event)
  if not next(script_data.riding_players) then return end
  local players = game.players
  for player_index, drone in pairs (script_data.riding_players) do
    local player = players[player_index]
    if player and player.valid then
      if drone.entity and drone.entity.valid then

        local player_position = player.position
        local position = drone.entity.position
        local shift = drone.entity.prototype.sticker_box.left_top
        local target_position = {x = position.x + shift.x, y = position.y + shift.y}
        local dx, dy = (target_position.x - player_position.x) * smoothing, (target_position.y - player_position.y) * smoothing

        local final_position = {player_position.x + dx, player_position.y + dy}
        player.teleport(final_position)
        if player.character then
          --player.character.walking_state = {walking = false, direction = to_direction(drone.entity.orientation)}
          player.character.direction = to_direction(get_orientation(player_position, final_position))
        end
      end
    end
  end
end

local set_map_settings = function()
  game.map_settings.path_finder.max_steps_worked_per_tick = 10000
  game.map_settings.path_finder.max_work_done_per_tick = 80000
  game.map_settings.path_finder.use_path_cache = false
end

-- 事件注册表 - 定义此模块监听的所有Factorio事件 (Event registration table - defines all Factorio events this module listens to)
transport_drone.events =
{
  -- 实体建造事件（已注释） (Entity construction events, commented out)
  --[defines.events.on_built_entity] = on_built_entity,
  --[defines.events.on_robot_built_entity] = on_built_entity,
  --[defines.events.script_raised_revive] = on_built_entity,
  --[defines.events.script_raised_built] = on_built_entity,

  -- 实体移除事件 - 玩家挖掘和机器人挖掘 (Entity removal events - player mining and robot mining)
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,

  -- 实体死亡事件 - 自然死亡和脚本销毁 (Entity death events - natural death and script destruction)
  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,

  -- AI命令完成事件 - 当无人机完成移动命令时触发 (AI command completed event - triggered when drone finishes movement command)
  [defines.events.on_ai_command_completed] = on_ai_command_completed,

  -- 自定义热键事件 - 跟随无人机 (Custom hotkey event - follow drone)
  ["follow-drone"] = follow_drone_hotkey,
  -- 每游戏刻事件 - 用于玩家骑乘无人机时的位置同步 (Per-game-tick event - for position sync when players ride drones)
  [defines.events.on_tick] = on_tick,
}

transport_drone.on_load = function()
  script_data = storage.transport_drone or script_data
  for unit_number, drone in pairs (script_data.drones) do
    setmetatable(drone, transport_drone.metatable)
  end
end

transport_drone.on_init = function()
  storage.transport_drone = storage.transport_drone or script_data
  set_map_settings()
end

transport_drone.on_configuration_changed = function()
  script_data.riding_players = script_data.riding_players or {}

  for k, drone in pairs (script_data.drones) do
    if drone.entity.valid then
      if drone.state == states.going_to_supply then
        local count = drone.requested_count or 0
        local item = drone.requested_item or drone.request_depot.item
        local quality = drone.requested_quality or drone.request_depot.quality
        drone:pickup_from_supply(drone.supply_depot, item,quality, count)
      end
      if drone.state == states.deliver_fuel then
        drone.target_depot.fuel_on_the_way = drone.target_depot.fuel_on_the_way + (drone.fuel_amount or 0)
      end
    else
      script_data.drones[k] = nil
    end
  end

  set_map_settings()

end

transport_drone.get_drone = get_drone

transport_drone.get_drone_count = function()
  return table_size(script_data.drones)
end

return transport_drone
