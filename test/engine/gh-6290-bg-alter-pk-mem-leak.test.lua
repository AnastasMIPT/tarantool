env = require('test_run')
test_run = env.new()
test_run:cmd("create server bg_index_mem_leak with script='engine/gh-6290-bg-alter-pk-mem-leak.lua'")
test_run:cmd("start server bg_index_mem_leak")
test_run:cmd("switch bg_index_mem_leak")

engine = test_run:get_cfg('engine')
fiber = require('fiber')

s = box.schema.space.create('test', {engine = engine})
_ = s:create_index('pk',  {type='tree', parts={{1, 'uint'}}})

h = box.schema.space.create('heavy', {engine = engine})
_ = h:create_index('pk')

for i = 1, 2068000 do h:replace{i, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 100 bytes"} end

for i = 0, 5000 do s:replace{i, i, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"} end

started = false
a = 0
fno = 1

test_run:cmd("setopt delimiter ';'")

function joinable(fib)
	fib:set_joinable(true)
	return fib
end;

function disturb()
    while not started do fiber.sleep(0) end
	s:replace{0, 0, a, [[VERY BIG STRING
	bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb]]}
end;

function create()
    started = true
    s.index.pk:alter({parts = {{field = fno, type = 'unsigned'}}})
end;

for i = 1, 1000 do
	started = false
	fno = fno % 2 + 1
	disturber = joinable(fiber.new(disturb))
	creator = joinable(fiber.new(create))
	a = i
	disturber:join()
	creator:join()
	collectgarbage("collect")
end;

_ = s:replace{0, 0, a, [[VERY BIG STRING
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb]]};

test_run:cmd("setopt delimiter ''");
s:drop()
h:drop()

test_run:cmd("switch default")
test_run:cmd("stop server bg_index_mem_leak")
test_run:cmd("cleanup server bg_index_mem_leak")
