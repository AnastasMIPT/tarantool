env = require('test_run')
net_box = require('net.box')
fiber = require('fiber')
test_run = env.new()

test_run:cmd("create server test with script='box/gh-5924-implement-graceful-shutdown.lua'")

test_run:cmd("setopt delimiter ';'")
function prepare_connection_and_send_requests(server_addr, count, is_graceful_shutdown_required)
    local conn = net_box.connect(server_addr)
    if is_graceful_shutdown_required then
        conn.space._session_settings:update('graceful_shutdown_required', {{'=', 'value', true}})
    end
    local space = conn.space.test
    local futures = {}
    for i = 1, count do futures[i] = space:replace({i}, {is_async = true}) end
    return conn, space, futures
end;
function prepare_connection_and_send_long_requests(server_addr, count, func_name)
    local conn = net_box.connect(server_addr)
    local futures = {}
    for i = 1, count do futures[i] = conn:call(func_name, {}, {is_async = true}) end
    return conn, futures
end;
-- We check for the presence or absence of errors
-- Calling shutdown does not prevent receiving remaining
-- results, unlike calling close.
function check_results_with_condition(connection, futures, number, shutdown_or_close, is_error_expected)
    local results = {}
    local err = nil
    for i, future in pairs(futures) do
        if i == number then
            if shutdown_or_close == "shutdown" then
                connection:shutdown()
            elseif shutdown_or_close == "close" then
               connection:close()
            else
               assert(false)
            end
        end
        results[i], err = future:wait_result()
        if err then
            print(i , err)
            break
        end
    end
    if not is_error_expected then
        assert(not err)
    else
        assert(err)
    end
end;
test_run:cmd("setopt delimiter ''");

test_run:cmd("start server test with args='10'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

-- Check difference between close and shutdown connection:
-- after closing connection we getting error, after shutdown
-- responses
test_run:cmd("switch test")
s = box.schema.space.create('test', { engine = 'memtx' })
_ = s:create_index('primary')
test_run:cmd('switch default')

replace_count = 1000
conn, space, futures = prepare_connection_and_send_requests(server_addr, replace_count)
-- Give time to send requests to the server
fiber.yield()
check_results_with_condition(conn, futures, 1, "close", true)
test_run:cmd("switch test")
s:truncate()
test_run:cmd('switch default')

conn, space, futures = prepare_connection_and_send_requests(server_addr, replace_count)
-- Give time to send requests to the server
fiber.yield()
-- Shutdown socket for write, does not prevent
-- getting responses from the server
check_results_with_condition(conn, futures, 1, "shutdown", false)

-- error: Peer closed
-- Server received 0 after shutdown and closed
-- connection after processing all requests
space:replace({replace_count + 1})
test_run:cmd("switch test")
s:truncate()
test_run:cmd('switch default')

-- We need more requests to ensure that not all of them
-- will have time to be processed before calling `shutdown`
-- or `close`.
replace_count = 20000
conn, space, futures = prepare_connection_and_send_requests(server_addr, replace_count)
check_results_with_condition(conn, futures, 10, "close", true)
test_run:cmd("switch test")
s:truncate()
test_run:cmd('switch default')

conn, space, futures = prepare_connection_and_send_requests(server_addr, replace_count)
check_results_with_condition(conn, futures, 10, "shutdown", false)

test_run:cmd("switch test")
s:drop()
fiber = require('fiber')
long_call_count = 0
function long_call() fiber.sleep(1) long_call_count = long_call_count + 1 return long_call_count end
test_run:cmd('switch default')

-- Check that in case of shutdown, server processing all incoming
-- requests, before shutdown.
replace_count = 10
conn, futures = prepare_connection_and_send_long_requests(server_addr, replace_count, "long_call")
-- Give time to send requests to the server
fiber.yield()
test_run:cmd("stop server test")
check_results_with_condition(nil, futures, 0, "shutdown", false)

-- Now check graceful shutdown for connections with special
-- graceful shutdown support.

-- First, check the case without the "reconnect after" option.
-- In the case when we received IPPROTO_SHUT, we wait until
-- send_buf is empty, and then we send SHUT_WR to the server.
-- Server processes all remaining requests and closes connection.
-- We receive responses to all requests that were sent before we
-- received IPROTO_SHUTDOWN.
test_run:cmd("start server test with args='10'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
test_run:cmd("switch test")
s = box.schema.space.create('test', { engine = 'memtx' })
_ = s:create_index('primary')
test_run:cmd('switch default')
replace_count = 20000
conn, space, futures = prepare_connection_and_send_requests(server_addr, replace_count, true)
-- For connections with graceful shutdown support we don't need yield
-- to ensure that requests are sent to server.
-- Server does not shutdown until it receives a SHUT_WR from the client,
-- and the client does not send it until send_buf is empty.
test_run:cmd("stop server test")
check_results_with_condition(nil, futures, 0, "shutdown", false)
test_run:cmd("start server test with args='10'")
test_run:cmd("switch test")
-- Setting a small timeout for shutdown to ensure that
-- requests do not have time to be processed.
box.ctl.set_on_shutdown_timeout(0.5)
test_run:cmd("switch default")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
replace_count = 100000
conn, space, futures = prepare_connection_and_send_requests(server_addr, replace_count, true)
test_run:cmd("stop server test")
check_results_with_condition(nil, futures, 0, "shutdown", true)
opts = {}
opts.filename = 'gh-5924-implement-graceful-shutdown.log'
assert(test_run:grep_log("test", "on_shutdown triggers are timed out", nil, opts))

test_run:cmd("cleanup server test")
test_run:cmd("delete server test")
