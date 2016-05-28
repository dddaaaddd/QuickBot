local function tell(msg, ln)
	if msg.reply then
		msg = msg.reply
	end
	
	local text = ''

	text = text..'*ID*: '..msg.from.id..'\n'
	
	if msg.chat.type == 'group' or msg.chat.type == 'supergroup' then
		text = text..make_text(lang[ln].bonus.tell, msg.chat.id)
		return text
	else
		return text
	end
end

local function do_keybaord_credits()
	local keyboard = {}
    keyboard.inline_keyboard = {
    	{
    		{text = 'Canal', url = 'https://telegram.me/'..config.channel:gsub('@', '')},
    		{text = 'GitHub', url = 'https://github.com/jarriztg/QuickBot'},
    		{text = 'Puntúame', url = 'https://telegram.me/storebot?start='..bot.username},
		}
	}
	return keyboard
end

local action = function(msg, blocks, ln)
	if blocks[1] == 'initgroup' then
		if msg.chat.type == 'private' then return end
		if is_mod(msg) then
			local set, is_ok = cross.getSettings(msg.chat.id, ln)
			if not is_ok then
				local nick = msg.from.first_name
				if msg.from.username then
					nick = nick..' ('..msg.from.username..')'
				end
        		cross.initGroup(msg.chat.id, msg.from.id, nick)
        		api.sendMessage(msg.chat.id, 'Should be ok. Try to run /settings command')
        		api.sendLog('#initGroup\n'..vtext(msg.chat)..vtext(msg.from))
        	else
        		api.sendMessage(msg.chat.id, 'This is already ok')
        	end
        end
    end
    if blocks[1] == 'adminlist' then
    	if msg.chat.type == 'private' then return end
    	local no_usernames
    	local send_reply = true
    	if is_locked(msg, 'Modlist') then
    		if is_mod(msg) then
        		no_usernames = true
        	else
        		no_usernames = false
        		send_reply = false
        	end
        else
            no_usernames = true
        end
    	local out
        local creator, adminlist = cross.getModlist(msg.chat.id, no_usernames)
        if not creator then
            out = lang[ln].bonus.adminlist_admin_required --creator is false, admins is the error code
        else
            out = make_text(lang[ln].mod.modlist, creator, adminlist)
        end
        if not send_reply then
        	api.sendMessage(msg.from.id, out, true)
        else
            api.sendReply(msg, out, true)
        end
        mystat('/adminlist')
    end
    if blocks[1] == 'status' then
    	if msg.chat.type == 'private' then return end
    	if is_mod(msg) then
    		local user_id = res_user_group(blocks[2], msg.chat.id)
    		if not user_id then
		 		api.sendReply(msg, lang[ln].bonus.no_user, true)
		 	else
		 		local res = api.getChatMember(msg.chat.id, user_id)
		 		if not res then
		 			api.sendReply(msg, lang[ln].status.unknown)
		 			return
		 		end
		 		local status = res.result.status
				local name = res.result.user.first_name
				if res.result.user.username then name = name..' (@'..res.result.user.username..')' end
				if msg.chat.type == 'group' and is_banned(msg.chat.id, user_id) then
					status = 'kicked'
				end
		 		local text = make_text(lang[ln].status[status], name)
		 		api.sendReply(msg, text, true)
		 	end
	 	end
 	end
 	if blocks[1] == 'tell' then
 		local text = tell(msg, ln)
 		api.sendReply(msg, text, true)
 		mystat('/tell')
 	end
end

return {
	action = action,
	triggers = {
		'^/(tell)$',
	--	'^/(initgroup)$',
		'^/(adminlist)$',
		'^/(status) (@[%w_]+)$',
	}
}
