test_run = require('test_run').new()

fiber = require 'fiber'
net = require('net.box')

--
-- gh-3107: fiber-async netbox.
--
cond = nil
box.schema.user.grant('guest', 'execute', 'universe')
function long_function(...) cond = fiber.cond() cond:wait() return ... end
function finalize_long() while not cond do fiber.sleep(0.01) end cond:signal() cond = nil end
s = box.schema.create_space('test')
pk = s:create_index('pk')
s:replace{1}
s:replace{2}
s:replace{3}
s:replace{4}
c = net:connect(box.cfg.listen)
--
-- Check long connections, multiple wait_result().
--
future = c:call('long_function', {1, 2, 3}, {is_async = true})
future:result()
future:is_ready()
future:wait_result(0.01) -- Must fail on timeout.
finalize_long()
ret = future:wait_result(100)
future:is_ready()
-- Any timeout is ok - response is received already.
future:wait_result(0)
future:wait_result(0.01)
ret

_, err = pcall(future.wait_result, future, true)
err:find('Usage') ~= nil
_, err = pcall(future.wait_result, future, '100')
err:find('Usage') ~= nil

--
-- __serialize and __tostring future methods
--
future = c:call('long_function', {1, 2, 3}, {is_async = true})
tostring(future)
future
finalize_long()
future:wait_result()
future
future = c:eval('assert(false)', {}, {is_async = true})
tostring(future)
future:wait_result()
future
future = c:eval('return 123', {}, {is_async = true, skip_header = true, \
                                   buffer = require('buffer').ibuf()})
tostring(future)
future:wait_result()
test_run:cmd("push filter '0x[a-f0-9]+' to '<addr>'")
future
test_run:cmd("clear filter")

box.schema.user.revoke('guest', 'execute', 'universe')

c:close()
s:drop()
