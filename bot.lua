HTTP = require('socket.http')
HTTPS = require('ssl.https')
URL = require('socket.url')
JSON = require('dkjson')
redis = require('redis')
colors = require 'term.colors'
db = Redis.connect('127.0.0.1', 6379)
serpent = require('serpent')
existe_apikey = io.open("./data/key","r")


bot_init = function(on_reload) 
	print(colors.blue..'Deteniendo proceso de gbans...' ..colors.reset)
	os.execute('sudo tmux kill-session -t ScriptGban')
	print(colors.blue..'Leyendo config.lua...' ..colors.reset)
	config = dofile('config.lua') 
	if not existe_apikey then
		print(colors.red..'No hay api key' ..colors.reset)
		return
	end
	print(colors.blue..'Loading utilidades.lua...' ..colors.reset)
	cross, rdb = dofile('utilidades.lua') 
	print(colors.blue..'Leyendo lenjuages.lua...' ..colors.reset)
	lang = dofile(config.languages) 
	print(colors.blue..'Iniciando un nuevo proceso de gbans...' ..colors.reset)
	os.execute('sudo tmux new-session -s "ScriptGban" -d "bash gbanner/metodo.sh gbans"')
	print(colors.blue..'Leyendo tabla de funciones...' ..colors.reset)
	api = require('metodos')
	
	tot = 0
	
	bot = nil
	while not bot do 
		bot = api.getMe()
	end
	bot = bot.result

	plugins = {} 
	for i,v in ipairs(config.plugins) do
		local p = dofile('plugins/'..v)
		print(colors.red..'Leyendo plugin...'..colors.reset, v)
		table.insert(plugins, p)
	end
	print(colors.blue..'Plugins leidos:', #plugins ..colors.reset)

	print(colors.blue..'BOT INICIADO: @'..bot.username .. ', ' .. bot.first_name ..' ('..bot.id..')' ..colors.reset)
	if not on_reload then
		save_log('starts')
		db:hincrby('bot:general', 'starts', 1)
		api.sendMessage(config.admin, '*Bot iniciado*\n'..os.date('Día %A, %d %B %Y\nHora %X')..'\n'..#plugins..' plugins leidos', true)
	end
	
	-- Generate a random seed and "pop" the first random number. :)
	math.randomseed(os.time())
	math.random()

	last_update = last_update or 0 -- Set loop variables: Update offset,
	last_cron = last_cron or os.time() -- the time of the last cron job,
	is_started = true -- whether the bot should be running or not.

end

local function get_from(msg)
	local user = msg.from.first_name
	if msg.from.last_name then
		user = user..' '..msg.from.last_name
	end
	if msg.from.username then
		user = user..' [@'..msg.from.username..']'
	end
	user = user..' ('..msg.from.id..')'
	return user
end

local function get_what(msg)
	if msg.sticker then
		return 'sticker'
	elseif msg.photo then
		return 'photo'
	elseif msg.document then
		return 'document'
	elseif msg.audio then
		return 'audio'
	elseif msg.video then
		return 'video'
	elseif msg.voice then
		return 'voice'
	elseif msg.contact then
		return 'contact'
	elseif msg.location then
		return 'location'
	elseif msg.text then
		return 'text'
	else
		return 'service message'
	end
end

local function collect_stats(msg)
	--count the number of messages
	db:hincrby('bot:general', 'messages', 1)
	--for resolve username (may be stored by groups of id in the future)
	if msg.from and msg.from.username then
		db:hset('bot:usernames', '@'..msg.from.username:lower(), msg.from.id)
		db:hset('bot:usernames:'..msg.chat.id, '@'..msg.from.username:lower(), msg.from.id)
	end
	if msg.forward_from and msg.forward_from.username then
		db:hset('bot:usernames', '@'..msg.forward_from.username:lower(), msg.forward_from.id)
		db:hset('bot:usernames:'..msg.chat.id, '@'..msg.forward_from.username:lower(), msg.forward_from.id)
	end
	if not(msg.chat.type == 'private') then
		if msg.from.id then
			db:hincrby('chat:'..msg.chat.id..':userstats', msg.from.id, 1) --3D: number of messages for each user
		end
		db:incrby('chat:'..msg.chat.id..':totalmsgs', 1) --total number of messages of the group
	end
end

local function match_pattern(pattern, text)
  if text then
  	text = text:gsub('@'..bot.username, '')
    local matches = {}
    matches = { string.match(text, pattern) }
    if next(matches) then
    	return matches
    end
  end
end

on_msg_receive = function(msg) -- The fn run whenever a message is received.
	--vardump(msg)
	if not msg then
		api.sendMessage(config.admin, 'Shit, a loop without msg!')
		return
	end
	
	if msg.date < os.time() - 5 then return end -- Do not process old messages.
	if not msg.text then msg.text = msg.caption or '' end
	
	--for commands link
	if msg.text:match('^/start .+') then
		msg.text = '/' .. msg.text:input()
	end
	
	--Group language
	msg.lang = db:get('lang:'..msg.chat.id)
	if not msg.lang then
		msg.lang = 'es'
	end
	
	collect_stats(msg) --resolve_username support, chat stats
	
	for i,v in pairs(plugins) do
		--vardump(v)
		local stop_loop
		if v.on_each_msg then
			msg, stop_loop = v.on_each_msg(msg, msg.lang)
		end
		if stop_loop then --check if on_each_msg said to stop the triggers loop
			break
		else
			if v.triggers then
				for k,w in pairs(v.triggers) do
					local blocks = match_pattern(w, msg.text)
					if blocks then
						print(colors.reset..colors.underscore..'\nMsg info:\t'..colors.reset..colors.red..get_from(msg)..colors.reset..' ['..msg.chat.type..'] ('..os.date('at %X')..')')
						if blocks[1] ~= '' then
      						print(colors.reset..colors.underscore..'Match found:', colors.reset..colors.blue..w..colors.reset)
      						db:hincrby('bot:general', 'query', 1)
      						if msg.from then db:incrby('user:'..msg.from.id..':query', 1) end
      					end
				
						local success, result = pcall(function()
							return v.action(msg, blocks, msg.lang)
						end)
						if not success then
							api.sendReply(msg, '*This is a bug!*\nPlease report the problem with `/c <bug>` :)', true)
							print(msg.text, result)
							save_log('errors', result, msg.from.id or false, msg.chat.id or false, msg.text or false)
          					api.sendLog('An #error occurred.\n'..result)
							return
						end
						-- If the action returns a table, make that table msg.
						if type(result) == 'table' then
							msg = result
						elseif type(result) == 'string' then
							msg.text = result
						-- If the action returns true, don't stop.
						elseif result ~= true then
							return
						end
					end
				end
			end
		end
	end
end



local function service_to_message(msg)
	local service
	local event
	if msg.new_chat_member then
		if tonumber(msg.new_chat_member.id) == tonumber(bot.id) then
			event = '###botadded'
		else
			event = '###added'
		end
		service = {
			chat = msg.chat,
    		date = msg.date,
    		adder = msg.from,
    		from = msg.from,
    		message_id = message_id,
    		added = msg.new_chat_member,
    		text = event,
    		service = true
    	}
	elseif msg.left_chat_member then
		if tonumber(msg.left_chat_member.id) == tonumber(bot.id) then
			event = '###botremoved'
		else
			event = '###removed'
		end
		service = {
			chat = msg.chat,
    		date = msg.date,
    		remover = msg.from,
    		from = msg.from,
    		message_id = message_id,
    		removed = msg.left_chat_member,
    		text = event,
    		service = true
    	}
	elseif msg.group_chat_created then
		service = {
			chat = msg.chat,
    		date = msg.date,
    		adder = msg.from,
    		from = msg.from,
    		message_id = message_id,
    		text = '###botadded',
    		service = true,
    		chat_created = true
    	}
	end
    return on_msg_receive(service)
end

local function forward_to_msg(msg)
	if msg.text then
		msg.text = '###forward:'..msg.text
	else
		msg.text = '###forward'
	end
    return on_msg_receive(msg)
end

local function inline_to_msg(inline)
	local msg = {
		id = inline.id,
    	chat = {
      		id = inline.id,
      		type = 'inline',
      		title = inline.from.first_name
    	},
    	from = inline.from,
		message_id = math.random(1,800),
    	text = '###inline:'..inline.query,
    	query = inline.query,
    	date = os.time() + 100
    }
    --vardump(msg)
    db:hincrby('bot:general', 'inline', 1)
    return on_msg_receive(msg)
end

local function media_to_msg(msg)
	if msg.photo then
		msg.text = '###image'
		--if msg.caption then
			--msg.text = msg.text..':'..msg.caption
		--end
	elseif msg.video then
		msg.text = '###video'
	elseif msg.audio then
		msg.text = '###audio'
	elseif msg.voice then
		msg.text = '###voice'
	elseif msg.document then
		msg.text = '###file'
		if msg.document.mime_type == 'video/mp4' then
			msg.text = '###gif'
		end
	elseif msg.sticker then
		msg.text = '###sticker'
	elseif msg.contact then
		msg.text = '###contact'
	end
	if msg.reply_to_message then
		msg.reply = msg.reply_to_message
	end
	msg.media = true
	return on_msg_receive(msg)
end

local function rethink_reply(msg)
	msg.reply = msg.reply_to_message
	if msg.reply.caption then
		msg.reply.text = msg.reply.caption
	end
	return on_msg_receive(msg)
end

local function handle_inline_keyboards_cb(msg)
	msg.text = '###cb:'..msg.data
	msg.old_text = msg.message.text
	msg.old_date = msg.message.date
	msg.date = os.time()
	msg.cb = true
	msg.cb_id = msg.id
	msg.message_id = msg.message.message_id
	msg.chat = msg.message.chat
	msg.message = nil
	return on_msg_receive(msg)
end

---------WHEN THE BOT IS STARTED FROM THE TERMINAL, THIS IS THE FIRST FUNCTION HE FOUNDS

bot_init() -- Actually start the script. Run the bot_init function.

while is_started do -- Start a loop while the bot should be running.
	local res = api.getUpdates(last_update+1) -- Get the latest updates!
	if res then
		--vardump(res)
		for i,msg in ipairs(res.result) do -- Go through every new message.
			last_update = msg.update_id
			tot = tot + 1
			if msg.message  or msg.callback_query then
				if msg.callback_query then
					handle_inline_keyboards_cb(msg.callback_query)
				elseif msg.message.migrate_to_chat_id then
					to_supergroup(msg.message)
				elseif msg.message.new_chat_member or msg.message.left_chat_member or msg.message.group_chat_created then
					service_to_message(msg.message)
				elseif msg.message.photo or msg.message.video or msg.message.document or msg.message.voice or msg.message.audio or msg.message.sticker then
					media_to_msg(msg.message)
				elseif msg.message.forward_from then
					forward_to_msg(msg.message)
				elseif msg.message.reply_to_message then
					rethink_reply(msg.message)
				else
					on_msg_receive(msg.message)
				end
			end
		end
	else
		print('Hay dos sessiones o más iniciadas.')
		return
	end
end

print('Detenido.')
