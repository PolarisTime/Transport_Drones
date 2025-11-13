
-- Transport Drones 模组的主控制文件 (Main control file for Transport Drones mod)
-- 此文件在运行时阶段加载，处理游戏事件和逻辑 (This file loads in runtime stage, handles game events and logic)

-- 加载共享配置和工具模块 (Load shared configuration and utility modules)
shared = require("shared") -- 共享常量和配置 (Shared constants and configuration)
util = require("script/script_util") -- 脚本工具函数 (Script utility functions)

-- 加载事件处理器 - Factorio模组的标准事件管理系统 (Load event handler - standard event management system for Factorio mods)
local handler = require("event_handler")

-- 注册各个功能模块到事件处理器 (Register functional modules to event handler)
-- 每个模块都导出一个events表，定义它们处理的事件 (Each module exports an events table defining the events they handle)
handler.add_lib(require("script/road_network")) -- 道路网络逻辑 (Road network logic)
handler.add_lib(require("script/depot_common")) -- 仓库通用逻辑 (Common depot logic)
handler.add_lib(require("script/transport_drone")) -- 无人机核心逻辑 (Core drone logic)
handler.add_lib(require("script/proxy_tile")) -- 代理图块处理 (Proxy tile handling)
handler.add_lib(require("script/transport_technologies")) -- 运输科技效果 (Transport technology effects)
handler.add_lib(require("script/gui")) -- 图形用户界面 (Graphical user interface)

--require("script/remote_interface") -- 远程接口（已注释） (Remote interface, commented out)
