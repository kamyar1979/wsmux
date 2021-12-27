local server = require "resty.websocket.server"
local client = require "resty.websocket.client"

function connect_to_node(uri)
   local wb_node, err = client:new { timeout=10 }
   local ok, err = wb_node:connect(uri)
   if not ok then
      ngx.say("failed to connect: " .. err)
      return
   end
   return wb_node
end

local receive_from_node = coroutine.create(function (wb_node, recv_cb)
      while true do
	 local data, typ, err = wb_node:recv_frame()
	 if not data then
	    ngx.say("failed to receive the frame: ", err)
	    return
	 end
	 recv_cb(data, typ)
	 coroutine.yield()
      end      
end)

function send_data_to_node(wb_node, data, typ)
   if typ == "text" then
      local bytes, err = wb_node:send_text(data)
   elseif typ == "binary" then
      local bytes, err = wb_node:send_binary(data)
   end
   return bytes, err
end

local wb, err = server:new{
   timeout = 10,
   max_payload_len = 65535
}
if not wb then
   ngx.log(ngx.ERR, "failed to new websocket: ", err)
   return ngx.exit(444)
end

function send_data_to_client(data, type)
   if typ == "text" then
      wb.send_text(data)
   elseif typ == "binary" then
      wb.send_binary(data)
   end
end

host = connect_to_node("ws://127.0.0.1:8765/customers", send_data_to_client)
ngx.log(ngx.INFO, "client connected")
while true do
   coroutine.resume(receive_from_node, host, send_data_to_client)
   local data, typ, err = wb:recv_frame()
   if wb.fatal then
      ngx.log(ngx.ERR, "failed to receive frame: ", err)
      return ngx.exit(444)
   end
   if not data then
      local bytes, err = wb:send_ping()
      if not bytes then
	 ngx.log(ngx.ERR, "failed to send ping: ", err)
	 return ngx.exit(444)
      end
   elseif typ == "close" then break
   elseif typ == "ping" then
      local bytes, err = wb:send_pong()
      if not bytes then
	 ngx.log(ngx.ERR, "failed to send pong: ", err)
	 return ngx.exit(444)
      end
   elseif typ == "pong" then
      ngx.log(ngx.INFO, "client ponged")
   elseif typ == "text" or typ == "binary" then
      bytes, err = send_data_to_node(host, data, typ)
      if not bytes then
	 ngx.log(ngx.ERR, "failed to send text: ", err)
      end
   end
end
wb:send_close()

