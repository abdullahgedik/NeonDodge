local Pool = {}
Pool.__index = Pool

function Pool.new(factory)
    return setmetatable({
        factory = factory,
        active = {},
        free = {},
    }, Pool)
end

function Pool:spawn(init)
    local obj = table.remove(self.free) or self.factory()
    init(obj)
    table.insert(self.active, obj)
    return obj
end

function Pool:release(index)
    local obj = self.active[index]
    if not obj then return end

    local last = #self.active
    self.active[index] = self.active[last]
    self.active[last] = nil

    table.insert(self.free, obj)
end

function Pool:clear()
    for _, obj in ipairs(self.active) do
        table.insert(self.free, obj)
    end
    self.active = {}
end

return Pool
