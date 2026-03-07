--- Assert that a condition is truthy; if not, log the error and yield forever
--- inside a coroutine, or raise an error in the main thread.
---@generic T
---@param condition T The value to check
---@param msg? string Error message to print/raise on failure
---@return T condition The original value when truthy
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
