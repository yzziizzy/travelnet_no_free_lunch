local S = minetest.get_translator("travelnet")

return function (node_info, fields, player)

	local network = travelnet.get_network(node_info.props.owner_name, node_info.props.station_network)

	if node_info.node ~= nil and node_info.props.is_elevator then
		for k,_ in pairs(network) do
			if network[k].nr == fields.target then
				fields.target = k
				break
			end
		end
	end

	local target_station = network[fields.target]

	-- if the target station is gone
	if not target_station then
		return false, S("Station '@1' does not exist (anymore?)" ..
					" " .. "on this network.", fields.target or "?")
	end

	local player_name = player:get_player_name()
	
	-- calculate the toll
	local x1 = node_info.pos.x - target_station.pos.x
	local y1 = node_info.pos.y - target_station.pos.y
	local z1 = node_info.pos.z - target_station.pos.z
	local dist = math.sqrt(x1*x1 + y1*y1 + z1* z1)
	local cost = math.ceil(dist / 100)
	
	-- pay the toll
	local pinv = player:get_inventory()
	local taken = pinv:remove_item("main", "default:gold_ingot "..cost)
	
	if taken:get_count() == 0 then
		return false, S("Too poor: cost = @1", cost) 
	end
	
	if not travelnet.allow_travel(
		player_name,
		node_info.props.owner_name,
		node_info.props.station_network,
		node_info.props.station_name,
		fields.target
	) then
		return false, S("You are not allowed to travel to this station.")
	end
	minetest.chat_send_player(player_name, S("Initiating transfer to station '@1'.", fields.target or "?"))

	if travelnet.travelnet_sound_enabled then
		if node_info.props.is_elevator then
			minetest.sound_play("travelnet_bell", {
				pos = node_info.pos,
				gain = 0.75,
				max_hear_distance = 10
			})
		else
			minetest.sound_play("travelnet_travel", {
				pos = node_info.pos,
				gain = 0.75,
				max_hear_distance = 10
			})
		end
	end

	if travelnet.travelnet_effect_enabled then
		minetest.add_entity(vector.add(node_info.pos, { x=0, y=0.5, z=0 }), "travelnet:effect")
	end

	-- close the doors at the sending station
	travelnet.open_close_door(node_info.pos, player, "close")

	-- transport the player to the target location

	-- may be 0.0 for some versions of MT 5 player model
	local player_model_bottom = tonumber(minetest.settings:get("player_model_bottom")) or -.5
	local player_model_vec = vector.new(0, player_model_bottom, 0)
	local target_pos = target_station.pos

	local top_pos = vector.add(node_info.pos, { x=0, y=1, z=0 })
	local top_node = minetest.get_node(top_pos)
	if top_node.name ~= "travelnet:hidden_top" then
		local def = minetest.registered_nodes[top_node.name]
		if def and def.buildable_to then
			minetest.set_node(top_pos, { name="travelnet:hidden_top" })
		end
	end

	minetest.load_area(target_pos)

	local tnode = minetest.get_node(target_pos)
	-- check if the box has at the other end has been removed.
	if minetest.get_item_group(tnode.name, "travelnet") == 0 and minetest.get_item_group(tnode.name, "elevator") == 0 then
		-- provide information necessary to identify the removed box
		local oldmetadata = {
			fields = {
				owner           = node_info.props.owner_name,
				station_name    = fields.target,
				station_network = node_info.props.station_network
			}
		}

		local success, reason = travelnet.remove_box_action(oldmetadata)
		if not success then
			return false, reason
		end

		travelnet.remove_box_message(oldmetadata, player)
	else
		-- add player model offset
		target_pos = vector.add(target_pos, player_model_vec)
		-- add travelnet bottom plate offset
		target_pos = vector.add(target_pos, { x=0, y=0.05, z=0 })

		player:set_pos(target_pos)
		travelnet.rotate_player(target_pos, player)
	end

	return true
end
