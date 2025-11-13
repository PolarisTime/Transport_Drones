-- Transport Drones 模组的数据阶段文件 (Data stage file for Transport Drones mod)
-- 此文件在数据阶段加载，定义游戏原型（实体、技术、配方等） (This file loads in data stage, defines game prototypes: entities, technologies, recipes, etc.)

-- 加载工具和共享模块 (Load utilities and shared modules)
util = require "__Transport_Drones_Meglinge_Fork__/data/tf_util/tf_util" -- 模组工具函数 (Mod utility functions)
names = require("shared") -- 共享名称常量 (Shared name constants)
shared = require("shared") -- 共享配置 (Shared configuration)

-- 加载实体定义 (Load entity definitions)
require "data/entities/entities" -- 定义所有游戏实体原型 (Define all game entity prototypes)

-- 加载科技定义 (Load technology definitions)
require "data/technologies/transport_speed" -- 运输速度科技 (Transport speed technology)
require "data/technologies/transport_capacity" -- 运输容量科技 (Transport capacity technology)
require "data/technologies/transport_system" -- 运输系统科技 (Transport system technology)

-- 加载用户界面元素 (Load user interface elements)
require "data/hotkey" -- 热键定义 (Hotkey definitions)
require "data/shortcut" -- 快捷键定义 (Shortcut definitions)

-- 加载其他游戏内容 (Load other game content)
require("data/tiles/road_tile") -- 道路图块定义 (Road tile definitions)
-- require("data/informatron/informatron") -- 信息界面（已注释） (Information interface, commented out)
require("data/tips/tips") -- 游戏提示 (Game tips)
