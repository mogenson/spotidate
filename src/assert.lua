function assert(condition, msg)
    if not condition then
        printf("assert error: %s", msg)
        while coroutine.running() do
            coroutine.yield()
        end
        error(msg)
    end
    return condition
end
