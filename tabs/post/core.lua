module 'aux.tabs.post'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local sort_util = require 'aux.util.sort'
local persistence = require 'aux.util.persistence'
local money = require 'aux.util.money'
local scan_util = require 'aux.util.scan'
local post = require 'aux.core.post'
local scan = require 'aux.core.scan'
local history = require 'aux.core.history'
local cache = require 'aux.core.cache'
local item_listing = require 'aux.gui.item_listing'
local al = require 'aux.gui.auction_listing'

TAB 'Post'

local DURATION_12, DURATION_24, DURATION_48 = 1, 2, 3

local settings_schema = {'tuple', '#', {duration='number'}, {start_price='number'}, {buyout_price='number'}, {hidden='boolean'}}

local scan_id, inventory_records, bid_records, buyout_records = 0, {}, {}, {}

function get_default_settings()
	return O('duration', DURATION_24, 'start_price', 0, 'buyout_price', 0, 'hidden', false)
end

function LOAD2()
	data = faction_data'post'
end

function read_settings(item_key)
	item_key = item_key or selected_item.key
	return data[item_key] and persistence.read(settings_schema, data[item_key]) or default_settings
end
function write_settings(settings, item_key)
	item_key = item_key or selected_item.key
	data[item_key] = persistence.write(settings_schema, settings)
end

do
	local bid_selections, buyout_selections = {}, {}
	function get_bid_selection()
		return bid_selections[selected_item.key]
	end
	function set_bid_selection(record)
		bid_selections[selected_item.key] = record
	end
	function get_buyout_selection()
		return buyout_selections[selected_item.key]
	end
	function set_buyout_selection(record)
		buyout_selections[selected_item.key] = record
	end
end

function refresh_button_click()
	scan.abort(scan_id)
	refresh_entries()
	refresh = true
end

do
	local item
	function get_selected_item() return item end
	function set_selected_item(v) item = v end
end

do
	local c = 0
	function get_refresh() return c end
	function set_refresh(v) c = v end
end

function OPEN()
    frame:Show()
    update_inventory_records()
    refresh = true
end

function CLOSE()
    selected_item = nil
    frame:Hide()
end

function USE_ITEM(item_id, suffix_id)
	select_item(item_id .. ':' .. suffix_id)
end

function get_unit_start_price()
	return selected_item and read_settings().start_price or 0
end

function set_unit_start_price(amount)
	local settings = read_settings()
	settings.start_price = amount
	write_settings(settings)
end

function get_unit_buyout_price()
	return selected_item and read_settings().buyout_price or 0
end

function set_unit_buyout_price(amount)
	local settings = read_settings()
	settings.buyout_price = amount
	write_settings(settings)
end

function update_inventory_listing()
	local records = values(filter(copy(inventory_records), function(record)
		local settings = read_settings(record.key)
		return record.aux_quantity > 0 and (not settings.hidden or show_hidden_checkbox:GetChecked())
	end))
	sort(records, function(a, b) return a.name < b.name end)
	item_listing.populate(inventory_listing, records)
end

function update_auction_listing(listing, records, reference)
	local rows = T
	if selected_item then
		local historical_value = history.value(selected_item.key)
		local stack_size = stack_size_slider:GetValue()
		for _, record in pairs(records[selected_item.key] or empty) do
			local price_color = undercut(record, stack_size_slider:GetValue(), listing == 'bid') < reference and color.red
			local price = record.unit_price * (listing == 'bid' and record.stack_size / stack_size_slider:GetValue() or 1)
			tinsert(rows, O(
				'cols', A(
				O('value', record.own and color.green(record.count) or record.count),
				O('value', al.time_left(record.duration)),
				O('value', record.stack_size == stack_size and color.green(record.stack_size) or record.stack_size),
				O('value', money.to_string(price, true, nil, price_color)),
				O('value', historical_value and al.percentage_historical(round(price / historical_value * 100)) or '---')
			),
				'record', record
			))
		end
		if historical_value then
			tinsert(rows, O(
				'cols', A(
				O('value', '---'),
				O('value', '---'),
				O('value', '---'),
				O('value', money.to_string(historical_value, true, nil, color.green)),
				O('value', historical_value and al.percentage_historical(100) or '---')
			),
				'record', O('historical_value', true, 'stack_size', stack_size, 'unit_price', historical_value, 'own', true)
			))
		end
		sort(rows, function(a, b)
			return sort_util.multi_lt(
				a.record.unit_price * (listing == 'bid' and a.record.stack_size or 1),
				b.record.unit_price * (listing == 'bid' and b.record.stack_size or 1),

				a.record.historical_value and 1 or 0,
				b.record.historical_value and 1 or 0,

				b.record.own and 0 or 1,
				a.record.own and 0 or 1,

				a.record.stack_size,
				b.record.stack_size,

				a.record.duration,
				b.record.duration
			)
		end)
	end
	if listing == 'bid' then
		bid_listing:SetData(rows)
	elseif listing == 'buyout' then
		buyout_listing:SetData(rows)
	end
end

function update_auction_listings()
	update_auction_listing('bid', bid_records, unit_start_price)
	update_auction_listing('buyout', buyout_records, unit_buyout_price)
end

function M.select_item(item_key)
    for _, inventory_record in pairs(filter(copy(inventory_records), function(record) return record.aux_quantity > 0 end)) do
        if inventory_record.key == item_key then
            update_item(inventory_record)
            return
        end
    end
end

function price_update()
    if selected_item then
        local historical_value = history.value(selected_item.key)
        if bid_selection or buyout_selection then
	        unit_start_price = undercut(bid_selection or buyout_selection, stack_size_slider:GetValue(), bid_selection)
	        unit_start_price_input:SetText(money.to_string(unit_start_price, true, nil, nil, true))
        end
        if buyout_selection then
	        unit_buyout_price = undercut(buyout_selection, stack_size_slider:GetValue())
	        unit_buyout_price_input:SetText(money.to_string(unit_buyout_price, true, nil, nil, true))
        end
        start_price_percentage:SetText(historical_value and al.percentage_historical(round(unit_start_price / historical_value * 100)) or '---')
        buyout_price_percentage:SetText(historical_value and al.percentage_historical(round(unit_buyout_price / historical_value * 100)) or '---')
    end
end

function post_auctions()
	if selected_item then
        local unit_start_price = unit_start_price
        local unit_buyout_price = unit_buyout_price
        local stack_size = stack_size_slider:GetValue()
        local stack_count
        stack_count = stack_count_slider:GetValue()
        local duration = UIDropDownMenu_GetSelectedValue(duration_dropdown)
		local key = selected_item.key

        -- local duration_code
		-- if duration == DURATION_2 then
            -- duration_code = 2
		-- elseif duration == DURATION_8 or duration == DURATION_12 then
            -- duration_code = 3
		-- elseif duration == DURATION_24 or duration == DURATION_48 then
            -- duration_code = 4
		-- end

		post.start(
			key,
			stack_size,
			duration,
            unit_start_price,
            unit_buyout_price,
			stack_count,
			function(posted)
				for i = 1, posted do
                    record_auction(key, stack_size, unit_start_price * stack_size, unit_buyout_price, duration + 1, UnitName'player')
                end
                update_inventory_records()
				local same
                for _, record in pairs(inventory_records) do
                    if record.key == key then
	                    same = record
	                    break
                    end
                end
                if same then
	                update_item(same)
                else
                    selected_item = nil
                end
                refresh = true
			end
		)
	end
end

function validate_parameters()
    if not selected_item then
        post_button:Disable()
        return
    end
    if unit_buyout_price > 0 and unit_start_price > unit_buyout_price then
        post_button:Disable()
        return
    end
    if unit_start_price == 0 then
        post_button:Disable()
        return
    end
    if stack_count_slider:GetValue() == 0 then
        post_button:Disable()
        return
    end
    post_button:Enable()
end

function update_item_configuration()
    if not selected_item then
        refresh_button:Disable()

        item.texture:SetTexture(nil)
        item.count:SetText()
        item.name:SetTextColor(color.label.enabled())
        item.name:SetText('No item selected')

        unit_start_price_input:Hide()
        unit_buyout_price_input:Hide()
        stack_size_slider:Hide()
        stack_count_slider:Hide()
        deposit:Hide()
        duration_dropdown:Hide()
        hide_checkbox:Hide()
    else
        unit_start_price_input:Show()
        unit_buyout_price_input:Show()
        stack_size_slider:Show()
        stack_count_slider:Show()
        deposit:Show()
        duration_dropdown:Show()
        hide_checkbox:Show()

        item.texture:SetTexture(selected_item.texture)
        item.name:SetText('[' .. selected_item.name .. ']')
        do
            local color = ITEM_QUALITY_COLORS[selected_item.quality]
            item.name:SetTextColor(color.r, color.g, color.b)
        end
        if selected_item.aux_quantity > 1 then
            item.count:SetText(selected_item.aux_quantity)
        else
            item.count:SetText()
        end

        stack_size_slider.editbox:SetNumber(stack_size_slider:GetValue())
        stack_count_slider.editbox:SetNumber(stack_count_slider:GetValue())

        local deposit_factor = UnitFactionGroup'npc' and 0.05 or 0.25
        local duration_value = UIDropDownMenu_GetSelectedValue(duration_dropdown)
        local duration_factor = duration_value and (duration_value / 120) or nil
        local stack_size = selected_item.max_charges and 1 or stack_size_slider:GetValue()
        local stack_count = stack_count_slider:GetValue()

        -- Calcul sécurisé du dépôt avec minimum 1 silver par stack
        local amount = 0
        if selected_item.unit_vendor_price and duration_factor then
            amount = floor(selected_item.unit_vendor_price * deposit_factor * stack_size) * stack_count * duration_factor
            local min_deposit = 100 * stack_count -- 1 silver = 100 copper
            if amount < min_deposit then
                amount = min_deposit
            end
        else
            amount = 100 * stack_count -- dépôt minimum si données manquantes
        end

        deposit:SetText('Deposit: ' .. money.to_string(amount, nil, nil, color.text.enabled))

        refresh_button:Enable()
    end
end
