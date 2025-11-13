-- 供应仓库模块 - 处理提供物品给道路网络的仓库逻辑 (Supply depot module - handles depots that provide items to the road network)
local supply_depot = {}

-- 设置元表以启用面向对象方法调用 (Set metatable to enable object-oriented method calls)
supply_depot.metatable = {__index = supply_depot}

-- 尸体偏移量配置 - 基于仓库方向的无人机停靠位置 (Corpse offset configuration - drone docking positions based on depot direction)
-- 方向值对应Factorio的defines.direction枚举 (Direction values correspond to Factorio's defines.direction enum)
supply_depot.corpse_offsets =
{
  [0] = {0, -2}, -- 北方向 (North direction)
  [4] = {2, 0}, -- 东方向 (East direction)
  [8] = {0, 2}, -- 南方向 (South direction)
  [12] = {-2, 0}, -- 西方向 (West direction)
}

local get_corpse_position = function(entity)

  local position = entity.position
  local direction = entity.direction
  local offset = supply_depot.corpse_offsets[direction]
  return {position.x + offset[1], position.y + offset[2]}

end

-- 创建新的供应仓库实例 (Create new supply depot instance)
-- @param entity: 组装机实体（被转换为仓库） (Assembler entity to be converted into depot)
-- @param tags: 蓝图标签数据 (Blueprint tag data)
function supply_depot.new(entity, tags)
  local position = entity.position
  local force = entity.force
  local surface = entity.surface
  
  -- 设置组装机属性以防止玩家交互 (Set assembler properties to prevent player interaction)
  entity.destructible = false -- 不可被破坏 (Cannot be destroyed)
  entity.minable = false -- 不可被挖掘 (Cannot be mined)
  entity.rotatable = false -- 不可旋转 (Cannot be rotated)
  entity.active = false -- 停用（不运行配方） (Inactive - won't run recipes)
  
  -- 使用surface.create_entity创建供应仓库箱子实体 (Create supply depot chest entity using surface.create_entity)
  local chest = surface.create_entity{
    name = "supply-depot-chest", -- 实体原型名称 (Entity prototype name)
    position = position, -- 与组装机相同位置 (Same position as assembler)
    force = force, -- 相同势力 (Same force)
    player = entity.last_user -- 建造者信息 (Builder information)
  }

  -- 创建仓库对象 (Create depot object)
  local depot =
  {
    entity = chest, -- 主要实体引用（箱子） (Primary entity reference - chest)
    assembler = entity, -- 原始组装机引用 (Original assembler reference)
    to_be_taken = {}, -- 待取物品跟踪表 (Items to be taken tracking table)
    index = tostring(chest.unit_number), -- 唯一标识符 (Unique identifier)
    old_contents = {} -- 上一次的物品内容（用于增量更新） (Previous contents for incremental updates)
  }
  setmetatable(depot, supply_depot.metatable) -- 设置元表 (Set metatable)

  depot:get_corpse() -- 创建无人机停靠点 (Create drone docking point)
  depot:read_tags(tags) -- 读取蓝图数据 (Read blueprint data)

  return depot

end

function supply_depot:get_corpse()
  if self.corpse and self.corpse.valid then
    return self.corpse
  end

  local corpse_position = get_corpse_position(self.assembler)
  local corpse = self.entity.surface.create_entity{name = "transport-caution-corpse", position = corpse_position}
  corpse.corpse_expires = false
  self.corpse = corpse
  self.node_position = {math.floor(corpse_position[1]), math.floor(corpse_position[2])}
  return corpse
end

function supply_depot:read_tags(tags)
  if tags then
    if tags.transport_depot_tags then
      local bar = tags.transport_depot_tags.bar
      if bar then
        self.entity.get_output_inventory().set_bar(bar)
      end
    end
  end
end

function supply_depot:save_to_blueprint_tags()
  return
  {
    bar = self.entity.get_output_inventory().get_bar()
  }
end

function supply_depot:get_to_be_taken(name,quality)
  return self.to_be_taken[name..quality] or 0
end

function supply_depot:update_contents()
  local supply = self.road_network.get_network_item_supply(self.network_id)
  local new_contents
  if (self.circuit_writer and self.circuit_writer.valid) then
    local behavior = self.circuit_writer.get_control_behavior()
    if behavior and behavior.disabled then
      new_contents = {}
    end
  end

  if not new_contents then
    new_contents = self.entity.get_output_inventory().get_contents()
  end

  for _,content in pairs (self.old_contents) do
    if not new_contents[{name = content.name,quality = content.quality}] then
      local item_supply = supply[content.name..content.quality]
      if item_supply then
        item_supply[self.index] = nil
      end
    end
  end

  for _,content in pairs (new_contents) do
    local item_supply = supply[content.name..content.quality]
    if not item_supply then
      item_supply = {}
      supply[content.name..content.quality] = item_supply
    end
    local new_count = content.count - self:get_to_be_taken(content.name,content.quality)
    if new_count > 0 then
      item_supply[self.index] = new_count
    else
      item_supply[self.index] = nil
    end
  end

  self.old_contents = new_contents

end

--[[

had iron 10
now iron 5
]]

function supply_depot:update()
  self:update_contents()

end

function supply_depot:say(string)
  -- self.entity.surface.create_entity{name = "tutorial-flying-text", position = self.entity.position, text = string}
end

-- 从供应仓库中取出物品给无人机 (Take items from supply depot for drone)
-- @param requested_name: 物品名称 (Item name)
-- @param requested_quality: 物品质量 (Item quality)
-- @param requested_count: 请求数量 (Requested count)
-- @return: 实际取出的数量 (Actually removed count)
function supply_depot:give_item(requested_name,requested_quality, requested_count)
  local inventory = self.entity.get_output_inventory() -- 获取输出物品栏 (Get output inventory)
  -- 使用inventory.remove从物品栏中移除物品 (Use inventory.remove to remove items from inventory)
  local removed_count = inventory.remove({name = requested_name,quality = requested_quality, count = requested_count})
  return removed_count
end

-- 添加待取物品计数 - 预留将要被无人机取走的物品 (Add to-be-taken count - reserve items that will be taken by drones)
function supply_depot:add_to_be_taken(name,quality, count)
  --if not (name and count) then return end
  self.to_be_taken[name..quality] = (self.to_be_taken[name..quality] or 0) + count
  --self:say(name.." - "..self.to_be_taken[name]..": "..count)
end

-- 获取可用物品数量（总数减去已预留的） (Get available item count - total minus reserved)
function supply_depot:get_available_item_count(name, quality)
  return self.entity.get_output_inventory().get_item_count({name = name,quality = quality}) - self:get_to_be_taken(name,quality)
end

function supply_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "supply")
  self:update_contents()
end

function supply_depot:remove_from_network()
  self.road_network.remove_depot(self, "supply")
  self.network_id = nil
end

function supply_depot:on_removed(event)

  self.corpse.destroy()

  if self.assembler.valid then
    self.assembler.destructible = true
    if event.name == defines.events.on_entity_died then
      self.assembler.die()
    else
      self.assembler.destroy()
    end
  end

  if self.entity.valid then
    self.entity.destroy()
  end
end

function supply_depot:on_config_changed()
  self.old_contents = self.old_contents or {}
end

return supply_depot