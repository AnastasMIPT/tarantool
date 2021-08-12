env = require('test_run')
test_run = env.new()

trg = nil;
trg = box.ctl.on_shutdown(function() trg = box.ctl.on_shutdown(nil, trg) end)
test_run:cmd("restart server default")

fiber = require('fiber')
s = box.schema.space.create('test')
_ = s:create_index('primary')
_ = s:on_replace(function() fiber.sleep(1) end)
_ = fiber.create(function() s:replace({7}) end)
-- destroy on_replace triggers
s:drop()
